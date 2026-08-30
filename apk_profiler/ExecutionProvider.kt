package com.claude.local.profiler

import com.claude.local.data.model.BackendPoint

/**
 * ExecutionProvider — les DEUX chemins d'exécution restent distincts
 * (GGML/llama.cpp-Hexagon vs QNN/QAIRT), mais partagent le même collecteur.
 */
interface ExecutionProvider {
    val id: String               // "ggml" | "qnn"
    val representation: String   // "gguf" | "qairt"
    val runtimes: Set<String>
    fun formats(): Map<String, Pair<Int, Int>>   // format → (W, A)
    fun backends(): List<String>
    /** Script à exécuter pour bencher ce provider+format, ou null. */
    fun benchScript(format: String): String?
    fun logPath(format: String): String
}

class GgmlExecutionProvider : ExecutionProvider {
    override val id = "ggml"
    override val representation = "gguf"
    override val runtimes = setOf("ggml-hexagon", "ggml-cpu", "ggml-gpu")
    override fun formats() = linkedMapOf(
        "Q4_0" to (4 to 0), "Q8_0" to (8 to 0),
        "Q4_K_M" to (4 to 0), "F16" to (16 to 0)
    )
    override fun backends() = listOf("cpu", "htp", "gpu", "cpu+htp")
    override fun benchScript(format: String) = when (format) {
        "Q4_0" -> "bench_one.sh"
        "Q8_0" -> "bench_q8.sh"
        else -> null
    }
    override fun logPath(format: String) =
        "/data/local/tmp/bench_${format.lowercase()}.log"
}

class QnnExecutionProvider : ExecutionProvider {
    override val id = "qnn"
    override val representation = "qairt"
    override val runtimes = setOf("qairt-qnn")
    override fun formats() = linkedMapOf(
        "FP16" to (16 to 16), "W16A16" to (16 to 16),
        "W8A16" to (8 to 16), "W8A8" to (8 to 8),
        "W4A16" to (4 to 16), "W4A8" to (4 to 8)
    )
    override fun backends() = listOf("htp", "gpu", "htp+gpu")
    override fun benchScript(format: String) =
        "bench_qairt_${format.lowercase()}.sh"
    override fun logPath(format: String) =
        "/data/local/tmp/t12_qairt_${format.lowercase()}.log"
}

object Providers {
    val ALL = listOf(GgmlExecutionProvider(), QnnExecutionProvider())
    fun byId(id: String): ExecutionProvider? =
        ALL.firstOrNull { it.id == id }

    /** Registre unifié (matrice MODEL.precision × runtime) — les deux chemins. */
    fun matrix(): Map<String, Pair<Int, Int>> = linkedMapOf(
        "Q4_0" to (4 to 0), "Q8_0" to (8 to 0), "Q4_K_M" to (4 to 0),
        "F16" to (16 to 0), "W4A16" to (4 to 16), "W8A16" to (8 to 16),
        "W8A8" to (8 to 8), "W4A8" to (4 to 8)
    )

    /** Convertit un format en BackendPoint vide (matrice toujours complète). */
    fun point(format: String, backend: String, runtime: String,
              note: String = ""): BackendPoint {
        val wa = matrix()[format]
        return BackendPoint(
            backend = backend, format = format, runtime = runtime,
            provider = if (runtime.startsWith("qairt")) "qnn" else "ggml",
            wbits = wa?.first, abits = wa?.second, note = note
        )
    }
}