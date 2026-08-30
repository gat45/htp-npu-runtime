package com.claude.local.profiler

import org.json.JSONObject

/**
 * SOURCE DE VÉRITÉ UNIQUE des parseurs de logs (point 11 de l'audit).
 * Tous les moteurs (PerLayerProfiler, ExperimentController, CommonCollector)
 * passent par ici — plus de duplication de regex/timing.
 */
object LogParser {

    /** decode t/s depuis un texte (bench_one RESULT, geniex-bench, llama-bench). */
    fun parseTps(text: String?): Double? {
        if (text.isNullOrBlank()) return null
        return Regex("""["']?decode["']?\s*[:=]\s*"?([0-9.]+)""").find(text)
            ?.groupValues?.get(1)?.toDoubleOrNull()
            ?: Regex("""([0-9.]+)\s*tok/s""").find(text)
            ?.groupValues?.get(1)?.toDoubleOrNull()
            ?: Regex("""\|\s*tg16\s*\|\s*([0-9.]+)""").find(text)
            ?.groupValues?.get(1)?.toDoubleOrNull()
    }

    /** prefill t/s depuis un texte. */
    fun parsePrefill(text: String?): Double {
        if (text.isNullOrBlank()) return 0.0
        return Regex("""["']?prefill["']?\s*[:=]\s*"?([0-9.]+)""").find(text)
            ?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
    }

    /** RESULT: {"decode": 17.2, "prefill": ..., "ttft_ms": ...} (bench_one.sh). */
    fun parseResultJson(text: String?): Pair<Double, Double>? {
        if (text == null) return null
        val m = Regex("""RESULT:\s*(\{.*\})""").find(text) ?: return null
        return runCatching {
            val j = JSONObject(m.groupValues[1])
            (j.optDouble("decode", 0.0)) to
                (j.optDouble("prefill", 0.0))
        }.getOrNull()
    }

    /** Valeur d'une ligne de table llama-bench : `| pp128 | 136.84 |`. */
    fun parseMatrixVal(log: String?, test: String): Double? {
        if (log == null) return null
        val m = Regex("""\|\s*$test\s*\|\s*([0-9.]+)""").find(log)
        return m?.groupValues?.get(1)?.toDoubleOrNull()
    }

    /** Compteurs ftrace : `12 fastrpc_context_alloc:...` → map. */
    fun parseFtraceCounts(text: String?): Map<String, Long> {
        val out = mutableMapOf<String, Long>()
        if (text == null) return out
        for (m in Regex("""(\d+)\s+(fastrpc[a-z_]*:[a-z_]+)""").findAll(text)) {
            out[m.groupValues[2]] = m.groupValues[1].toLongOrNull() ?: 0L
        }
        return out
    }

    /** VMEM depuis un log sweep : `GGML_HEXAGON_VMEM=4096` ou `vmem: 4096 MiB`. */
    fun parseVmem(text: String?): Double? {
        if (text == null) return null
        return Regex("""(?:VMEM|vmem)\s*[:=]\s*(\d+)(?:\s*(MiB|MB|GiB|GB))?""")
            .find(text)?.let {
                val v = it.groupValues[1].toDoubleOrNull() ?: return null
                when (it.groupValues[2]) {
                    "GiB", "GB" -> v * 1024.0
                    else -> v
                }
            }
    }

    /** RAM MemFree kB → MB. */
    fun parseMemFreeMb(text: String?): Double {
        if (text == null) return 0.0
        return Regex("""MemFree:\s+(\d+) kB""").find(text)
            ?.groupValues?.get(1)?.toDoubleOrNull()?.div(1024.0) ?: 0.0
    }

    /**
     * Parse npu_profile.json (npu_profiler.sh) → liste de configs par ngl.
     * Format attendu (JSON produit par npu_profiler.sh) :
     *   [ {"ngl": 0, "decode": .., "prefill": .., "ttft_ms": .., "ram_mb": ..}, ... ]
     * ou {"configs": [...]}.
     */
    fun parseNpuProfilerJson(text: String?): List<Map<String, Any>> {
        if (text.isNullOrBlank()) return emptyList()
        return runCatching {
            val raw = JSONObject(text)
            val arr = if (raw.has("configs")) raw.getJSONArray("configs")
            else if (text.trimStart().startsWith("[")) null else raw.getJSONArray("results")
            if (arr == null) return emptyList()
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.getJSONObject(i)
                mapOf(
                    "ngl" to o.optInt("ngl", o.optInt("n_gpu_layers", -1)),
                    "decode" to o.optDouble("decode", 0.0),
                    "prefill" to o.optDouble("prefill", 0.0),
                    "ttft_ms" to o.optDouble("ttft_ms", 0.0),
                    "ram_mb" to o.optDouble("ram_mb", 0.0)
                )
            }
        }.getOrDefault(emptyList())
    }
}