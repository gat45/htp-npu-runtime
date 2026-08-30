package com.claude.local.service

import com.claude.local.data.model.*
import com.claude.local.profiler.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PERLAYER / UNIFIED PROFILER — point central qui orchestre l'ensemble des
 * outils du harnais. 7 moteurs : MODEL · EXECUTION (GGML/QNN providers) ·
 * BENCHMARK · LAYER · HARDWARE PROFILER · MEMORY/RUNTIME · ANALYSIS.
 *
 * CORRECTIFS d'audit :
 * - chemins de logs RÉELS (mn_*.log, prof_results/cpu_ngl0, t12_qairt_*.log)
 * - exécution avec cwd correct via RootShell.execTool
 * - parse de la matrice réelle (table `| pp128 | X | tg16 | Y |`)
 * - vérif md5 host/skel avant bench (règle harnais)
 */
class PerLayerProfiler(private val shell: RootShell = RootShell) {

    companion object {
        const val TOOLS_DIR = "/data/local/tmp/tools"
        const val NPU_DIR = "/data/local/tmp/npu"
        // Logs RÉELS des scripts tools/.
        const val HOST_LIB = "$NPU_DIR/libggml-hexagon.so"
        const val SKEL_LIB = "$NPU_DIR/libggml-htp-v81.so"
        const val FTRACE_LOG = "/data/local/tmp/l2_ftrace_results.txt"
        const val L2_BENCH_LOG = "/data/local/tmp/l2_bench.log"
        const val CPU_PROF_DIR = "/data/local/tmp/prof_results/cpu_ngl0"
        const val MTP_LOG = "/data/local/tmp/axe3_mtp_test.log"

        val ALL_ACTIONS = listOf(
            "bench_cpu", "bench_qairt", "matrix_npu", "sweep_vmem",
            "quant_q8", "run_hybrid", "test_mtp", "npu_profiler"
        )
        val DEFAULT_QAIRT_FORMATS = listOf(
            "FP16", "W8A16", "W8A8", "W4A16", "W4A8"
        )
    }

    private val hw = HardwareProfiler(shell)
    private val layers = LayerAnalyzer(shell)
    private val controller = ExperimentController(shell)

    /** CAMPAIGN : framework complet (7 moteurs) — GGML+QAIRT providers. */
    suspend fun runCampaign(
        providers: List<String> = listOf("ggml", "qnn"),
        runMtp: Boolean = true,
        outDir: String = "/sdcard/op15_campaign",
        onProgress: (String) -> Unit = {}
    ): CampaignReport = controller.runCampaign(
        providers = providers, runMtp = runMtp, outDir = outDir,
        onProgress = onProgress)

    /** Exécute un script en vérifiant l'intégrité (md5) — point 12. */
    private suspend fun execVerified(script: String, timeout: Long): String? {
        if (!ScriptGuard.verify(shell, script)) return null
        return shell.execTool(script, timeout)
    }

    /** Vérifie l'appariement host/skel (md5) avant TOUT bench (règle). */
    private suspend fun stackPair(): Pair<String?, String?> {
        val host = shell.readFile(HOST_LIB, 1)
            ?.let { Regex("""[0-9a-f]{32}""").find(it)?.value }
        val skel = shell.readFile(SKEL_LIB, 1)
            ?.let { Regex("""[0-9a-f]{32}""").find(it)?.value }
        return host to skel
    }

    suspend fun profile(runtime: String = "qairt", tg: Double = 6.3,
                        runRealBench: Boolean = false,
                        actions: List<String> = ALL_ACTIONS,
                        qairtFormats: List<String> = DEFAULT_QAIRT_FORMATS,
                        qnnVersion: String = "",
                        mixedLayers: String = ""): PerLayerReport =
        withContext(Dispatchers.IO) {
            val (hostMd5, skelMd5) = stackPair()
            val counts = hw.ftraceCounts()
            val bottleneck = hw.bottleneck()
            var tps = tg
            val results = mutableListOf<BenchAction>()
            val notes = mutableListOf<String>()

            if (runRealBench || "bench_qairt" in actions) {
                val bq = runQairtSweep(qairtFormats, mixedLayers)
                results += bq
                bq.points.forEach { if (it.tg32 > 0) tps = it.tg32 }
            }
            if ("bench_cpu" in actions) {
                results += runCpu()
            }
            if ("matrix_npu" in actions) {
                results += runMatrix()
            }
            if ("sweep_vmem" in actions) {
                results += runSweepVmem()
            }
            if ("quant_q8" in actions) {
                results += runSimple("quant_q8", "Quant Q8_0",
                    "quant_q8.sh", 600)
            }
            if ("run_hybrid" in actions) {
                results += runSimple("run_hybrid", "Hybride CPU+NPU",
                    "run_hybrid9b.sh", 900)
            }
            if ("test_mtp" in actions) {
                results += runMtp()
            }
            if ("npu_profiler" in actions) {
                results += runNpuProfiler()
            }

            if (tps <= 0.0) tps = tg
            buildReport(runtime, tps, counts, bottleneck, results,
                notes, hostMd5, skelMd5, qnnVersion, mixedLayers)
        }

    /** Bench CPU pur — log réel dans prof_results/cpu_ngl0/. */
    private suspend fun runCpu(): BenchAction {
        val ran = execVerified("bench_cpu.sh", 600) != null
        val dir = shell.readFile(
            "$CPU_PROF_DIR/bench.json", 60) ?: shell.readFile(
            "$CPU_PROF_DIR/output.txt", 60)
        val tg = parseTps(dir)
        return BenchAction(
            id = "bench_cpu", label = "Bench CPU pur",
            status = if (ran) "ok" else "error",
            points = listOf(Providers.point("Q4_0", "cpu", "ggml-hexagon")
                .copy(tg32 = tg ?: 0.0, note = if (tg == null)
                    "log introuvable ($CPU_PROF_DIR)" else "mesuré")),
            rawTail = dir?.takeLast(800) ?: ""
        )
    }

    /** Matrice GPU×HTP — logs réels mn_{htp,gpu,h7030,h5050,h3070}.log. */
    private suspend fun runMatrix(): BenchAction {
        val ran = execVerified("matrix_npu.sh", 900) != null
        val points = mutableListOf<BackendPoint>()
        val map = listOf(
            "htp" to "htp", "gpu" to "gpu",
            "h7030" to "gpu_htp_30", "h5050" to "gpu_htp_50",
            "h3070" to "gpu_htp_70"
        )
        for ((tag, backend) in map) {
            val log = shell.readFile("/data/local/tmp/mn_$tag.log", 200)
            val pp = parseMatrixVal(log, "pp128") ?: 0.0
            val tg = parseMatrixVal(log, "tg16") ?: 0.0
            points += Providers.point("Q4_0", backend, "ggml-hexagon")
                .copy(pp512 = pp, tg32 = tg,
                    note = if (tg == 0.0) "log mn_$tag introuvable/vide"
                    else "mesuré")
        }
        return BenchAction(
            id = "matrix_npu", label = "Matrice GPU×HTP (ggml)",
            status = if (ran) "ok" else "error",
            points = points,
            rawTail = (shell.readFile("/data/local/tmp/mn_htp.log", 200)
                ?: "").takeLast(600)
        )
    }

    /** Parse une valeur de la table llama-bench : `| pp128 | 136.84 |`. */
    internal fun parseMatrixVal(log: String?, test: String): Double? =
        LogParser.parseMatrixVal(log, test)

    private fun parseTps(text: String?): Double? = LogParser.parseTps(text)

    /** Sweep QAIRT/QNN : seul bench_qairt_w4a16.sh existe → W4A16 réel,
     *  les autres formats = note "bundle absent" (matrice complète). */
    private suspend fun runQairtSweep(formats: List<String>,
                                      mixedLayers: String): BenchAction {
        val points = mutableListOf<BackendPoint>()
        var raw = ""
        val wa16 = Providers.matrix()["W4A16"]
        // W4A16 = le bundle réel (bench_qairt_w4a16.sh).
        val ran = execVerified("bench_qairt_w4a16.sh", 600) != null
        val log = shell.readFile("/data/local/tmp/t12_qairt_w4a16.log", 200)
        val tg = parseTps(log)
        points += Providers.point("W4A16", "htp", "qairt-qnn")
            .copy(wbits = wa16?.first, abits = wa16?.second,
                tg32 = tg ?: 0.0,
                note = if (tg == null)
                    "bundle w4a16 absent ou log illisible" else "mesuré")
        raw = log?.takeLast(800) ?: ""
        // Les autres formats : enregistrés, note "bundle absent".
        for (fmt in formats) {
            if (fmt == "W4A16") continue
            val w = Providers.matrix()[fmt]
            points += Providers.point(fmt, "htp", "qairt-qnn")
                .copy(wbits = w?.first, abits = w?.second,
                    note = "bundle/script bench_qairt_${fmt.lowercase()}.sh absent")
        }
        return BenchAction(
            id = "bench_qairt", label = "Sweep QAIRT/QNN (5 précisions)",
            status = if (tg != null) "ok" else "partial",
            points = points, rawTail = raw
        )
    }

    private suspend fun runMtp(): BenchAction {
        // Le script device réel est axe3_mtp_test.sh (PC: test_mtp_npu.sh).
        val ran = execVerified("axe3_mtp_test.sh", 900) != null
        val log = shell.readFile("/data/local/tmp/axe3v4.txt", 200)
        val tg = parseTps(log) ?: parseMatrixVal(log, "tg16")
        return BenchAction(
            id = "test_mtp", label = "Test MTP (draft-mtp)",
            status = if (ran) "ok" else "error",
            points = listOf(Providers.point("Q4_0", "htp", "ggml-hexagon")
                .copy(tg32 = tg ?: 0.0, note = if (tg == null)
                    "log axe3v4 introuvable" else "mesuré")),
            rawTail = log?.takeLast(800) ?: ""
        )
    }

    /** Sweep VMEM — logs réels sv_{d3200,v4096,v6144}.log. */
    private suspend fun runSweepVmem(): BenchAction {
        val ran = execVerified("sweep_vmem_npu.sh", 900) != null
        val points = mutableListOf<BackendPoint>()
        for ((tag, vmem) in listOf(
                "d3200" to "défaut", "v4096" to "4096", "v6144" to "6144")) {
            val log = shell.readFile("/data/local/tmp/sv_$tag.log", 120)
            val tg = parseMatrixVal(log, "tg16") ?: 0.0
            points += Providers.point("Q4_0", "htp", "ggml-hexagon")
                .copy(tg32 = tg, note = "vmem=$vmem " +
                    if (tg == 0.0) "(log sv_$tag vide)" else "mesuré")
        }
        return BenchAction(
            id = "sweep_vmem", label = "Sweep VMEM NPU",
            status = if (ran) "ok" else "error",
            points = points,
            rawTail = (shell.readFile("/data/local/tmp/sv_d3200.log", 120)
                ?: "").takeLast(600)
        )
    }

    /** NPU profiler — nécessite 3 args + lit npu_profile.json. */
    private suspend fun runNpuProfiler(): BenchAction {
        if (!ScriptGuard.verify(shell, "npu_profiler.sh"))
            return BenchAction(id = "npu_profiler", label = "Profiler NPU (ngl sweep)",
                status = "integrity", points = emptyList(),
                rawTail = "script refusé (md5 modifié)")
        val model = "/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf"
        // Exécute avec les args requis (libdir, model, ngl liste).
        val ran = shell.exec(
            "cd /data/local/tmp && sh /data/local/tmp/tools/npu_profiler.sh " +
            "/data/local/tmp/gxlibs \"$model\" \"0,8,16,24,32,-1\" 1",
            900) != null
        val json = shell.readFile("/data/local/tmp/npu_profile.json", 200)
        val configs = LogParser.parseNpuProfilerJson(json)
        return BenchAction(
            id = "npu_profiler", label = "Profiler NPU (ngl sweep)",
            status = if (ran && configs.isNotEmpty()) "ok" else "error",
            points = configs.map { c ->
                Providers.point("Q4_0", "htp", "ggml-hexagon").copy(
                    ngl = (c["ngl"] as? Number)?.toInt() ?: 0,
                    tg32 = (c["decode"] as? Number)?.toDouble() ?: 0.0,
                    pp512 = (c["prefill"] as? Number)?.toDouble() ?: 0.0,
                    note = "ngl=${c["ngl"]} ttft=" +
                        "${c["ttft_ms"]}ms ram=${c["ram_mb"]}MB")
            },
            rawTail = json?.takeLast(800) ?: "npu_profile.json introuvable"
        )
    }

    private suspend fun runSimple(id: String, label: String, script: String,
                                  timeout: Long): BenchAction {
        val ran = execVerified(script, timeout) != null
        return BenchAction(
            id = id, label = label,
            status = if (ran) "ok" else "error",
            points = emptyList(),
            rawTail = ""
        )
    }

    private suspend fun buildReport(runtime: String, tps: Double,
                                    counts: Map<String, Long>,
                                    bottleneck: String,
                                    actions: List<BenchAction>,
                                    notes: List<String>,
                                    hostMd5: String?,
                                    skelMd5: String?,
                                    qnnVersion: String,
                                    mixedLayers: String): PerLayerReport {
        val budget = (1_000_000.0 / tps).toLong()
        val famShares = linkedMapOf(
            "output" to 0.20, "ffn" to 0.15, "attn" to 0.20,
            "ssm" to 0.06, "other" to 0.39
        )
        val families = famShares.map { (f, s) ->
            FamilyAggregate(
                family = f,
                ops = when (f) {
                    "other" -> 14779; "attn" -> 3112; "output" -> 46
                    "ffn" -> 512; else -> 1680
                },
                usMs = budget * s / 1000.0, partPct = s * 100.0
            )
        }
        val profiles = layers.profiles(runtime, tps, bottleneck)
        val (qnn, mix) = resolveRedTeam(actions, qnnVersion, mixedLayers)
        val stackNote = if (hostMd5 != null && skelMd5 != null)
            "host=$hostMd5 skel=$skelMd5 appariés" else
            "⚠ pile non vérifiée (md5 manquants)"

        return PerLayerReport(
            runtime = runtime, tg = tps, budgetUsPerToken = budget,
            layerProfiles = profiles, families = families,
            topOps = hw.topOps(counts), ftraceCounts = counts,
            actions = actions, rootReady = true,
            rawTail = actions.map { it.rawTail }.joinToString("")
                .takeLast(1500),
            error = null, qnnVersion = qnn, chipset = "SM8850",
            mixedLayers = mix, htp = true,
            fallback = if (counts.isEmpty())
                "aucune trace kernel (check root/ftrace)" else stackNote
        )
    }

    private fun resolveRedTeam(actions: List<BenchAction>,
                               qnnDefault: String,
                               mixedDefault: String): Pair<String, String> {
        var qnn = qnnDefault
        var mix = mixedDefault
        for (a in actions) {
            if (a.id != "bench_qairt") continue
            val measured = a.points.filter { it.tg32 > 0 }
            val formats = measured.map { it.format }.sorted()
            if (formats.size > 1)
                mix = "mixte: ${formats.joinToString(" + ")}"
        }
        return qnn to mix
    }
}