package com.claude.local.profiler

import java.io.RandomAccessFile

/**
 * LECTEUR GGUF LOCAL — profile un modèle GGUF directement sur le SoC.
 * Lit le header (KV metadata) + la liste des tensors (nom/shape/type/offset)
 * via RandomAccessFile (pas de lib externe, marche en root sur le device).
 *
 * Permet de :
 *   - lire l'architecture (qwen35, llama, ...), block_count, hparams SSM/KDA
 *   - lister les tensors par layer avec leur type de quantification + taille
 *   - calculer le BPW réel et comparer à l'allocation D2 (traffic planner)
 */
object GgufReader {

    // GGML tensor types (mapping GGML_TYPE_* -> nom + bytes/elt)
    private val TYPES = mapOf(
        0 to "F32", 1 to "F16", 2 to "Q4_0", 3 to "Q4_1", 4 to "Q5_0",
        5 to "Q5_1", 6 to "Q8_0", 7 to "Q8_1", 10 to "Q2_K",
        11 to "Q3_K_S", 12 to "Q3_K_M", 13 to "Q3_K_L", 14 to "Q4_K_S",
        15 to "Q4_K_M", 16 to "Q5_K_S", 17 to "Q5_K_M", 18 to "Q6_K",
        24 to "IQ1_S", 25 to "IQ4_NL", 28 to "IQ4_XS", 30 to "MXFP4"
    )
    private val BPW: Map<String, Double> = mapOf(
        "F32" to 32.0, "F16" to 16.0, "Q4_0" to 4.5, "Q4_1" to 5.0,
        "Q8_0" to 8.5, "Q2_K" to 2.6, "Q3_K_M" to 3.9, "Q4_K_M" to 5.0,
        "Q5_K_M" to 5.7, "Q6_K" to 6.6, "IQ4_NL" to 4.5
    )
    private const val MT_SZ = 8  // max field size we read (uint64)

    data class TensorInfo(
        val name: String, val shape: List<Long>, val type: Int,
        val typeName: String, val offset: Long
    ) {
        fun nelements(): Long = shape.fold(1L) { a, b -> a * b }
        fun bytes(): Long {
            val bpw: Double = BPW[typeName] ?: 16.0
            val n: Double = nelements().toDouble()
            return (n * bpw / 8.0).toLong().coerceAtLeast(0L)
        }
        fun layer(): String {
            val m = Regex("""blk\.(\d+)""").find(name)
            return m?.groupValues?.get(1) ?: "root"
        }
        fun category(): String = when {
            name.startsWith("output") || name.contains("lm_head") -> "output"
            name.contains("attn") -> "attn"
            name.contains("ffn") || name.contains("mlp") -> "ffn"
            name.contains("ssm") || name.contains("conv") -> "ssm"
            name.contains("norm") || name.contains("embd") -> "norm"
            name.contains("nextn") || name.contains("mtp") -> "mtp"
            else -> "other"
        }
    }

    data class ModelInfo(
        val arch: String, val blockCount: Int, val tensorCount: Int,
        val kv: Map<String, String>, val tensors: List<TensorInfo>,
        val totalBytes: Long
    )

    /** Lit le header GGUF complet (KV + tensors). */
    fun read(path: String, maxTensors: Int = 1000): ModelInfo {
        val f = RandomAccessFile(path, "r")
        try {
            val magic = ByteArray(4)
            f.readFully(magic)
            require(String(magic) == "GGUF") { "pas un GGUF: ${String(magic)}" }
            val version = readU32(f)
            val nTensors = readU64(f)
            val nKv = readU64(f)
            val kv = mutableMapOf<String, String>()
            for (i in 0 until nKv) {
                val k = readString(f)
                kv[k] = readValue(f).toString()
            }
            // Skip tensor infos (offsets) — on lit les noms/types pour le profil.
            val tensors = mutableListOf<TensorInfo>()
            var total = 0L
            for (i in 0 until minOf(nTensors, maxTensors.toLong())) {
                val name = readString(f)
                val nDim = readU32(f).toInt()
                val shape = (0 until nDim).map { readU64(f) }
                val type = readU32(f).toInt()
                val offset = readU64(f)
                val ti = TensorInfo(name, shape, type, TYPES[type] ?: "T$type",
                    offset)
                tensors.add(ti)
                total += ti.bytes()
            }
            val arch = kv["general.architecture"] ?: "?"
            val blockCount = kv["${arch}.block_count"]?.toIntOrNull() ?: 0
            return ModelInfo(arch, blockCount, nTensors.toInt(), kv, tensors,
                total)
        } finally {
            f.close()
        }
    }

    /** Répartition par layer + catégorie (pour l'UI). */
    fun layerSummary(model: ModelInfo): List<Map<String, Any>> {
        val byLayer = model.tensors.groupBy { it.layer() }
        return byLayer.entries.sortedBy { it.key.toIntOrNull() ?: -1 }
            .map { (layer, tensors) ->
                val byCat = tensors.groupBy { it.category() }
                val types = tensors.groupBy { it.typeName }
                    .mapValues { it.value.size }
                mapOf(
                    "layer" to layer,
                    "n_tensors" to tensors.size,
                    "bytes_mb" to (tensors.sumOf { it.bytes() } / 1_048_576L),
                    "categories" to byCat.mapValues { it.value.size },
                    "types" to types
                )
            }
    }

    private fun readU32(f: RandomAccessFile): Long {
        val b = ByteArray(4); f.readFully(b)
        return (b[0].toLong() and 0xff) or ((b[1].toLong() and 0xff) shl 8) or
            ((b[2].toLong() and 0xff) shl 16) or ((b[3].toLong() and 0xff) shl 24)
    }

    private fun readU64(f: RandomAccessFile): Long {
        val b = ByteArray(8); f.readFully(b)
        var v = 0L
        for (i in 7 downTo 0) v = (v shl 8) or (b[i].toLong() and 0xff)
        return v
    }

    private fun readString(f: RandomAccessFile): String {
        val n = readU64(f)
        val b = ByteArray(n.toInt().coerceAtMost(1_000_000))
        f.readFully(b)
        return String(b, Charsets.UTF_8)
    }

    private fun readValue(f: RandomAccessFile): Any {
        val t = readU32(f).toInt()
        return when (t) {
            8 -> readString(f)
            6 -> { // float32
                val b = ByteArray(4); f.readFully(b)
                java.nio.ByteBuffer.wrap(b).order(
                    java.nio.ByteOrder.LITTLE_ENDIAN).float
            }
            0 -> readU32(f)
            1 -> { val b = ByteArray(1); f.readFully(b); b[0] }
            4 -> readU32(f)
            5 -> { val b = ByteArray(4); f.readFully(b);
                java.nio.ByteBuffer.wrap(b).order(
                    java.nio.ByteOrder.LITTLE_ENDIAN).int }
            10 -> readU64(f)
            else -> { // skip inconnu (max 8 octets)
                val sz = when (t) { 2 -> 2; 3 -> 2; 11 -> 8; 12 -> 8; 7 -> 1
                    else -> 8 }
                f.skipBytes(sz); null ?: "<type $t>"
            }
        }
    }
}