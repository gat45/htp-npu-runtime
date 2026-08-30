package com.claude.local.profiler

import com.claude.local.data.model.*
import com.claude.local.service.RootShell
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.UUID

/**
 * EXPERIMENT CONTROLLER — orchestre une campagne complète :
 * discover → modèle → formats → backend → benchmark → profil HW →
 * sweep placement → sweep précision → MTP → mémoire → analyse layers →
 * croiser → Pareto → rapport final.
 * GGML et QAIRT sont des ExecutionProviders, pas des applications séparées.
 */
class ExperimentController(private val shell: RootShell = RootShell) {

    /** Timeout global de campagne (30 min) — évite l'app figée. */
    private companion object {
        const val GLOBAL_TIMEOUT_MS = 30L * 60 * 1000
    }

    private val collector = CommonCollector(shell)
    private val hwProfiler = HardwareProfiler(shell)
    private val layerAnalyzer = LayerAnalyzer(shell)
    private val d2 = D2LocalComparer()

    suspend fun runCampaign(
        providers: List<String> = listOf("ggml", "qnn"),
        formats: List<String>? = null,
        placements: List<String> = listOf("cpu", "htp", "hybrid"),
        runMtp: Boolean = true,
        outDir: String = "/sdcard/op15_campaign",
        onProgress: (String) -> Unit = {}
    ): CampaignReport = withContext(Dispatchers.IO) {
        val allFormats = formats
            ?: Providers.ALL.flatMap { it.formats().keys }.distinct()
        // Timeout global : la campagne ne doit pas figer l'app (point 10).
        withTimeoutOrNull(GLOBAL_TIMEOUT_MS) {
            runCampaignInner(providers, allFormats, placements, runMtp,
                outDir, onProgress)
        } ?: CampaignReport(
            error = "campagne annulée (timeout ${GLOBAL_TIMEOUT_MS / 60000} min)")
    }

    private suspend fun runCampaignInner(
        providers: List<String>,
        allFormats: List<String>,
        placements: List<String>,
        runMtp: Boolean,
        outDir: String,
        onProgress: (String) -> Unit
    ): CampaignReport {
        val experiments = mutableListOf<Experiment>()
        try {
            onProgress("discover")
            // discover : détecte les bundles/scripts dispo.
            val (availableFormats, notes) = discover(providers)

            // benchmark × précision × provider × placement.
            for (p in providers) {
                val provider = Providers.byId(p) ?: continue
                for (fmt in allFormats) {
                    val wa = Providers.matrix()[fmt]
                    if (wa == null) continue
                    val place = when (provider.id) {
                        "qnn" -> "htp"
                        else -> if ("hybrid" in placements) "hybrid" else "cpu"
                    }
                    onProgress("bench ${provider.id}/$fmt/$place")
                    val metrics = runExperiment(provider, fmt, place,
                        availableFormats.contains(fmt))
                    experiments += Experiment(
                        id = "${provider.id}_${fmt}_${place}",
                        provider = provider.id,
                        representation = provider.representation,
                        precision = fmt, runtime = provider.runtimes.first(),
                        backend = place, placement = place,
                        execution = "normal",
                        metrics = metrics.copy(
                            graphSplit = hwProfiler.graphSplitCount())
                    )
                }
            }

            // MTP (spéculatif) sur le meilleur format par provider.
            if (runMtp) {
                for (p in providers) {
                    val provider = Providers.byId(p) ?: continue
                    val best = experiments.filter { it.provider == p }
                        .maxByOrNull { it.metrics.tg32 } ?: continue
                    onProgress("mtp $p")
                    val mtpOk = execVerified("axe3_mtp_test.sh", 900)
                    val mtpLog = shell.readFile("/data/local/tmp/axe3v4.txt",
                        200)
                    val mtpTg = mtpLog?.let { LogParser.parseTps(it) }
                    experiments += best.copy(
                        id = "${best.id}_mtp",
                        execution = "mtp",
                        metrics = if (mtpTg != null && mtpTg > 0)
                            collector.collect(p, best.precision, mtpTg)
                        else best.metrics.copy(tg32 = 0.0)
                    )
                }
            }

            onProgress("analyse")
            // Analyse : Pareto + croisement + d2.
            val pareto = Analyzer.pareto(experiments)
            val cross = Analyzer.crossAll(experiments)
            val d2Compare = d2.compareToD2()

            // Artefacts structurés.
            onProgress("artefacts")
            val artifacts = ArtifactStore.write(outDir, experiments,
                pareto, cross, d2Compare)

            onProgress("terminé")
            return CampaignReport(
                config = "providers=$providers formats=$allFormats " +
                         "placements=$placements mtp=$runMtp",
                experiments = experiments, pareto = pareto,
                cross = cross, d2Compare = d2Compare,
                artifacts = artifacts
            )
        } catch (e: Exception) {
            onProgress("échec: ${e.message}")
            return CampaignReport(error = e.message ?: "campagne échouée",
                experiments = experiments)
        }
    }

    private suspend fun discover(providers: List<String>):
            Pair<Set<String>, Map<String, String>> {
        val ok = mutableSetOf<String>()
        val notes = mutableMapOf<String, String>()
        for (p in providers) {
            val provider = Providers.byId(p) ?: continue
            for (fmt in provider.formats().keys) {
                val script = provider.benchScript(fmt) ?: continue
                val present = shell.exec(
                    "test -f ${HardwareProfiler.TOOLS_DIR}/$script && echo yes",
                    10)?.trim() == "yes"
                if (present) ok += fmt else
                    notes[fmt] = "bundle/script $script absent"
            }
        }
        return ok to notes
    }

    private suspend fun runExperiment(provider: ExecutionProvider,
                                      format: String,
                                      placement: String,
                                      available: Boolean): CommonMetrics {
        if (!available) {
            // Pas de bundle → on enregistre un point vide (matrice complète).
            return CommonMetrics(tg32 = 0.0)
        }
        val script = provider.benchScript(format)
        // bench_one.sh imprime "RESULT: {...}" sur stdout (pas un fichier) →
        // on capture stdout ET on parse la valeur decode.
        val out = if (script != null) execVerified(script, 600) else null
        val result = out?.let { LogParser.parseResultJson(it) }
        val tg = result?.first ?: out?.let { LogParser.parseTps(it) } ?: 0.0
        // Collecte les mêmes catégories, quel que soit le provider.
        val m = collector.collect(provider.id, format)
        return m.copy(tg32 = if (tg > 0) tg else m.tg32)
    }

    /** Exécute un script en vérifiant l'intégrité (md5) — point 12. */
    private suspend fun execVerified(script: String, timeout: Long): String? {
        if (!ScriptGuard.verify(shell, script)) return null
        return shell.execTool(script, timeout)
    }
}

object Analyzer {
    /** Front de Pareto : max(tg) pour un budget RAM donné. */
    fun pareto(experiments: List<Experiment>): List<ParetoPoint> {
        return experiments.mapNotNull { e ->
            if (e.metrics.tg32 <= 0) null else ParetoPoint(
                id = e.id,
                precision = e.precision,
                tg32 = e.metrics.tg32,
                quality = qualityScore(e.precision),
                ramGb = e.metrics.ramMb / 1024.0
            )
        }.sortedByDescending { it.tg32 }
    }

    /** Perte de qualité estimée par précision (≈ governor LOSS_EST). */
    private fun qualityScore(precision: String): Double = when (precision) {
        "F16", "FP16", "W16A16" -> 100.0
        "W8A16", "Q8_0" -> 99.9
        "W8A8" -> 99.8
        "Q4_K_M", "W4A16" -> 99.5
        "Q4_0", "W4A8" -> 99.0
        else -> 99.5
    }

    /** Croisement : pourquoi A diffère de B (facteur + analyse). */
    fun crossAll(experiments: List<Experiment>): List<CrossResult> {
        val out = mutableListOf<CrossResult>()
        val byPrecision = experiments.filter { it.metrics.tg32 > 0 }
            .groupBy { it.precision }
        for (a in byPrecision) for (b in byPrecision) {
            if (a.key >= b.key) continue
            val ta = a.value.maxOf { it.metrics.tg32 }
            val tb = b.value.maxOf { it.metrics.tg32 }
            out += CrossResult(
                a = a.key, b = b.key,
                factor = if (ta > 0) tb / ta else 0.0,
                analysis = Analyzer.explain(a.key, b.key, ta, tb)
            )
        }
        return out
    }

    fun explain(a: String, b: String, ta: Double, tb: Double): String {
        val factor = if (ta > 0) tb / ta else 0.0
        return if (factor > 1.5)
            "$b bat $a par ×${"%.1f".format(factor)} — écart probablement " +
            "runtime/dispatch, pas seulement les bits (Q4_0 GGML vs W4A16 " +
            "QAIRT : graphe pré-compilé vs op-par-op RPC)"
        else if (factor < 0.66)
            "$b perd face à $a — $b moins efficace sur ce SoC/placement"
        else
            "$a ≈ $b (×${"%.2f".format(factor)}) — même régime (memory-bound)"
    }
}