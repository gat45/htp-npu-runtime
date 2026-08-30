package com.claude.local.profiler

import kotlin.math.max

import kotlin.math.max

/**
 * ROOFLINE PREDICTOR — prédit le decode t/s AVANT de lancer un bench.
 *
 * Réplique l'équation roofline du simulateur Hextimate (reverse du compilateur
 * QAIRT, datavorous) :
 *     bandwidth = channels * width * efficiency * frequency
 *     time = bytes / bandwidth
 *
 * Calibré sur les mesures réelles du OnePlus 15 (SM8850, HTP v81) :
 *     BW_GGML  ~30.5 GB/s   (6.74 t/s × 4.53 GB/token mesurés)
 *     BW_QAIRT ~74 GB/s     (estimé — à re-mesurer)
 *     facteur "fast DDR" (biais LLM du compilateur) : x1.0 par défaut.
 *
 * Usage : gate AVANT de builder/bencker une variante.
 *   predict(bytesPerTokenMb=4530, bw=74)  → ~16.7 t/s (QAIRT)
 *   predict(bytesPerTokenMb=4530, bw=30.5)→ ~6.9 t/s (GGML)
 */
object RooflinePredictor {

    const val BW_GGML = 30.5      // GB/s mesuré (GGML/HTP)
    const val BW_QAIRT = 74.0     // GB/s estimé (QAIRT/QNN)
    const val TRAFIC_Q4_0_MB = 4530.0   // MB/token mesuré (decode 9B)
    const val BASELINE_GGML_TPS = 6.7   // t/s baseline device

    /** decode t/s prédit = bw * fastDdr / octets_par_token. */
    fun predict(bytesPerTokenMb: Double = TRAFIC_Q4_0_MB,
                bwGbs: Double = BW_QAIRT,
                fastDdr: Double = 1.0): Double {
        if (bytesPerTokenMb <= 0.0 || bwGbs <= 0.0) return 0.0
        val gbPerToken = bytesPerTokenMb / 1024.0
        val secPerToken = gbPerToken / (bwGbs * fastDdr)
        return if (secPerToken > 0) 1.0 / secPerToken else 0.0
    }

    /** Trafic estimé W4A16 (~moitié du Q4_0 si per-tensor). */
    fun w4a16TrafficMb(): Double = TRAFIC_Q4_0_MB / 2.0

    /** Gate : le build vaut-il le coup vs baseline ? */
    fun gate(bytesPerTokenMb: Double, bwGbs: Double,
             fastDdr: Double = 1.0): Boolean {
        return predict(bytesPerTokenMb, bwGbs, fastDdr) >= BASELINE_GGML_TPS
    }

    /** Sanity-check calibré (à afficher en log). */
    fun sanityCheck(): String {
        val ggml = predict(TRAFIC_Q4_0_MB, BW_GGML)
        val qairt = predict(TRAFIC_Q4_0_MB, BW_QAIRT)
        val w4 = predict(w4a16TrafficMb(), BW_QAIRT)
        return "sanity: Q4_0@GGML=%.1f (mesure ~6.7) · Q4_0@QAIRT=%.1f " +
                "(mesure 15-17) · W4A16@QAIRT=%.1f".format(ggml, qairt, w4)
    }

    /** Rapport complet pour l'UI. */
    fun report(bytesPerTokenMb: Double = TRAFIC_Q4_0_MB,
               bwGbs: Double = BW_QAIRT,
               fastDdr: Double = 1.0): Map<String, Any> {
        val tps = predict(bytesPerTokenMb, bwGbs, fastDdr)
        return mapOf(
            "bytes_per_token_mb" to bytesPerTokenMb,
            "bytes_per_token_gb" to bytesPerTokenMb / 1024.0,
            "bw_gbs" to bwGbs,
            "fast_ddr" to fastDdr,
            "predicted_tps" to tps,
            "gate_pass" to (tps >= BASELINE_GGML_TPS),
            "baseline_tps" to BASELINE_GGML_TPS,
            "speedup_x" to max(0.0, tps / BASELINE_GGML_TPS)
        )
    }
}