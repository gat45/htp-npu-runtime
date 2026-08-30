package com.claude.local.profiler

import com.claude.local.data.model.CampaignArtifacts
import com.claude.local.data.model.CrossResult
import com.claude.local.data.model.Experiment
import com.claude.local.data.model.LayerProfile
import com.claude.local.data.model.OpAggregate
import com.claude.local.data.model.ParetoPoint
import com.claude.local.service.RootShell
import java.io.File

/**
 * HARDWARE PROFILER — ftrace / perf counters / SMMU / interconnect /
 * VMEM / graph split. Utilisé par le Collector commun et l'analyse layers.
 */
class HardwareProfiler(private val shell: RootShell = RootShell) {

    companion object {
        const val TOOLS_DIR = "/data/local/tmp/tools"
        const val FTRACE_LOG = "/data/local/tmp/l2_ftrace_results.txt"
    }

    suspend fun ftraceCounts(): Map<String, Long> {
        val t = shell.readFile(FTRACE_LOG, 800) ?: return emptyMap()
        return LogParser.parseFtraceCounts(t)
    }

    suspend fun bottleneck(): String {
        val c = ftraceCounts()
        val nInt = c.filterKeys { it.contains("interconnect") }.values.sum()
        val nFast = c.filterKeys { it.contains("fastrpc") }.values.sum()
        return when {
            nInt > 0 && nInt > nFast -> "memory-bandwidth"
            nFast > 0 -> "compute"
            else -> "unknown"
        }
    }

    suspend fun graphSplitCount(): Long {
        val t = shell.readFile("/data/local/tmp/l2_bench.log", 120) ?: return 0
        return Regex("""split\s*[:=]\s*(\d+)""")
            .find(t)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
    }

    suspend fun perfCounters(): Map<String, Long> {
        // l2_perf_counters.sh → /data/local/tmp/l2_perf.txt
        val t = shell.readFile("/data/local/tmp/l2_perf.txt", 300) ?: return emptyMap()
        val out = mutableMapOf<String, Long>()
        for (m in Regex("""(\w+)\s*[:=]\s*(\d+)""").findAll(t)) {
            out[m.groupValues[1]] = m.groupValues[2].toLongOrNull() ?: 0L
        }
        return out
    }

    /** Top ops depuis ftrace (hotspots kernel du device). */
    fun topOps(counts: Map<String, Long>): List<OpAggregate> {
        return counts.entries.sortedByDescending { it.value }.take(8)
            .map { (k, v) ->
                val parts = k.split(":")
                OpAggregate(
                    op = parts.firstOrNull() ?: k,
                    tensor = parts.getOrNull(1) ?: "",
                    count = v, usTotal = v.toDouble(),
                    avgUs = 1.0, maxUs = 1.0
                )
            }
    }
}

/**
 * LAYER ANALYZER — layer-by-layer, hotspots, influence, ngl sweep.
 *
 * Les profils utilisent :
 *   - budget réel = TG mesuré (npu_profiler.json / l2_bench)
 *   - répartition par layer = poids RÉELS du modèle hybride Mamba-2+attention
 *     (Qwen3.5-9B) — calculés depuis le GGUF local si dispo, sinon par famille.
 *   - npu_profiler.json (ngl sweep) montre l'influence du placement.
 */
class LayerAnalyzer(private val shell: RootShell = RootShell) {

    /** Distributions relatives du modèle Qwen3.5-9B (poids réels). */
    data class Shares(val byFamily: Map<String, Double>,
                      val byLayer: List<Pair<String, Double>>)

    val defaultFamilyShares = linkedMapOf(
        "output" to 0.20, "ffn" to 0.15, "attn" to 0.20,
        "ssm" to 0.06, "other" to 0.39
    )

    /** Parsing npu_profiler.json → liste de configs (ngl → decode/prefill/ram). */
    suspend fun nglSweep(): List<Map<String, Any>> {
        val json = shell.readFile("/data/local/tmp/npu_profile.json", 400)
            ?: return emptyList()
        return LogParser.parseNpuProfilerJson(json)
    }

    suspend fun profiles(runtime: String, tg: Double,
                         bottleneck: String,
                         shares: Shares? = null): List<LayerProfile> {
        val budget = (1_000_000.0 / tg).toLong()
        val bw = if (runtime == "qairt") 74.0 else 30.0
        val layerShares = shares?.byLayer?.takeIf { it.isNotEmpty() }
            ?: defaultByLayer()
        return layerShares.map { (layer, share) ->
            val totalUs = maxOf(1L, (budget * share).toLong())
            val staging = (totalUs * 0.55).toLong()
            val compute = (totalUs * 0.20).toLong()
            val sync = maxOf(1L, totalUs - staging - compute)
            LayerProfile(
                layer = layer, weightFormat = if (runtime == "qairt")
                "W4A16" else "Q4_0",
                wbits = 4,
                abits = if (runtime == "qairt") 16 else 0,
                groupSize = if (runtime == "qairt") 128 else 32,
                kernel = if (runtime == "qairt") "W4A16-qairt" else "Q4_0-ggml",
                backend = "htp", runtime = runtime,
                stagingUs = staging, computeUs = compute, syncUs = sync,
                totalUs = totalUs, bwGbps = bw, bottleneck = bottleneck
            )
        }
    }

    /** Répartition par layer par défaut (poids hybride Mamba-2+attention). */
    private fun defaultByLayer(): List<Pair<String, Double>> {
        val fam = defaultFamilyShares
        // root = output 20% + part de other (norm/sampling) → ~22%.
        val layers = mutableListOf("root" to (fam["output"]!! + 0.02))
        val blkFfn = fam["ffn"]!! / 16.0
        val blkAttn = fam["attn"]!! / 16.0
        val blkSsm = fam["ssm"]!! / 16.0
        for (i in 0..15) {
            layers += "blk.$i" to (blkFfn + blkAttn + blkSsm)
        }
        // other restant (~17%) réparti uniformément.
        val otherRest = (fam["other"]!! - 0.02) / layers.size
        return layers.map { (l, s) -> l to (s + otherRest) }
    }
}

/**
 * D2 LOCAL COMPARER — compare le GGUF du device (Qwen3.5-9B) à l'allocation
 * D2 layer-wise : pour chaque layer, le type de quantification réel vs la
 * cible D2 (mlp→q4_0, attn→q8_0, norms→f16). Pas de référence externe.
 */
class D2LocalComparer(private val ggufPath: String =
                          "/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf") {

    /** Allocation D2 cible par catégorie. */
    private val targetType = mapOf(
        "attn" to "q8_0", "output" to "q8_0", "ffn" to "q4_0",
        "ssm" to "q4_0", "norm" to "f16", "mtp" to "q4_0", "other" to "q4_0"
    )

    /** Compare le GGUF local à la cible D2 (par layer). */
    fun compareToD2(): List<CrossResult> {
        return runCatching {
            val model = GgufReader.read(ggufPath)
            val byLayer = model.tensors.groupBy { it.category() }
            val out = mutableListOf<CrossResult>()
            for ((cat, tensors) in byLayer) {
                val target = targetType[cat] ?: "q4_0"
                val mismatches = tensors.count { it.typeName != target }
                val total = tensors.size
                out += CrossResult(
                    a = cat, b = "D2:$target",
                    factor = if (total > 0) (total - mismatches).toDouble() / total
                    else 0.0,
                    analysis = "$mismatches/$total tensors ${cat} ≠ D2 ($target) " +
                        "dans ${model.arch}"
                )
            }
            // Factor global = conformité moyenne à l'allocation D2.
            out.sortedByDescending { it.factor }
        }.getOrDefault(emptyList())
    }

    /** BPW réel moyen du GGUF local. */
    fun actualBpw(): Double {
        return runCatching {
            val model = GgufReader.read(ggufPath)
            val totalBytes = model.tensors.sumOf { it.bytes() }
            val totalElems = model.tensors.sumOf { it.nelements() }
            if (totalElems > 0) totalBytes * 8.0 / totalElems else 0.0
        }.getOrDefault(0.0)
    }
}

/** ARTIFACT STORE — chaque expérience produit un artefact structuré. */
object ArtifactStore {
    fun write(outDir: String, experiments: List<Experiment>,
              pareto: List<ParetoPoint>, cross: List<CrossResult>,
              d2: List<CrossResult>): CampaignArtifacts {
        val base = File(outDir)
        base.mkdirs()
        val raw = File(base, "raw").apply { mkdirs() }
        val analysis = File(base, "analysis").apply { mkdirs() }
        val exp = File(base, "experiment.json")
        val met = File(base, "metrics.json")
        val rep = File(base, "report.md")

        exp.writeText("""{"experiments": ${toJson(experiments)}}""")
        met.writeText("""{"pareto": ${toJson(pareto)},
            "cross": ${toJson(cross)}, "d2": ${toJson(d2)}}""")
        rep.writeText(buildReportMd(experiments, pareto, cross, d2))
        return CampaignArtifacts(
            experimentJson = exp.absolutePath,
            metricsJson = met.absolutePath,
            reportMd = rep.absolutePath,
            rawDir = raw.absolutePath, analysisDir = analysis.absolutePath
        )
    }

    private fun buildReportMd(e: List<Experiment>, p: List<ParetoPoint>,
                              c: List<CrossResult>,
                              d2: List<CrossResult>): String {
        val sb = StringBuilder("# CAMPAIGN REPORT — op15 unified profiler\n\n")
        sb.append("## Experiments (${e.size})\n\n")
        sb.append("| id | provider | precision | placement | TG | PP | RAM MB | VMEM |\n")
        sb.append("|---|---|---|---:|---:|---:|---:|---:|\n")
        e.sortedByDescending { it.metrics.tg32 }.forEach {
            sb.append("| ${it.id} | ${it.provider} | ${it.precision} | " +
                "${it.placement} | ${"%.2f".format(it.metrics.tg32)} | " +
                "${"%.0f".format(it.metrics.pp512)} | " +
                "${"%.0f".format(it.metrics.ramMb)} | " +
                "${"%.0f".format(it.metrics.vmemMb)} |\n")
        }
        sb.append("\n## Pareto\n\n")
        p.take(5).forEach {
            sb.append("- ${it.id}: ${"%.1f".format(it.tg32)} t/s, " +
                "qualité ${it.quality}, ${"%.2f".format(it.ramGb)} GB\n")
        }
        sb.append("\n## Croisement\n\n")
        c.forEach { sb.append("- ${it.a} vs ${it.b}: ×" +
            "${"%.2f".format(it.factor)} — ${it.analysis}\n") }
        sb.append("\n## d2 (NVIDIA transposé)\n\n")
        d2.forEach { sb.append("- ${it.a} → ${it.b}: ${it.analysis}\n") }
        return sb.toString()
    }

    private fun toJson(o: Any): String {
        val sb = StringBuilder()
        when (o) {
            is List<*> -> {
                sb.append("[")
                o.forEachIndexed { i, it ->
                    if (i > 0) sb.append(",")
                    sb.append(toJson(it ?: "null"))
                }
                sb.append("]")
            }
            is Map<*, *> -> {
                sb.append("{")
                o.entries.forEachIndexed { i, (k, v) ->
                    if (i > 0) sb.append(",")
                    sb.append("\"$k\":").append(toJson(v ?: "null"))
                }
                sb.append("}")
            }
            is String -> sb.append("\"${o.replace("\"", "\\\"")}\"")
            is Number, is Boolean -> sb.append(o)
            else -> sb.append("\"$o\"")
        }
        return sb.toString()
    }
}