package com.claude.local.profiler

import com.claude.local.data.model.CommonMetrics
import com.claude.local.service.RootShell

/**
 * COLLECTOR COMMUN — peu importe GGML ou QAIRT, on récupère les MÊMES
 * catégories de métriques (speed / memory / hardware) → résultats comparables.
 */
private data class Quad<A, B, C, D>(val a: A, val b: B, val c: C, val d: D)
private data class Six<A, B, C, D, E, F>(
    val a: A, val b: B, val c: C, val d: D, val e: E, val f: F)

class CommonCollector(private val shell: RootShell = RootShell) {

    suspend fun collect(providerId: String, format: String,
                        tgHint: Double = 0.0): CommonMetrics {
        val speed = collectSpeed(tgHint)
        val (ram, vram, vmem, buffers) = collectMemory()
        val (smmu, interconnect, fastrpc, fallback, split, temp) =
            collectHardware()
        return speed.copy(
            ramMb = ram, vramMb = vram,
            vmemMb = vmem, buffersMb = buffers,
            smmu = smmu, interconnect = interconnect,
            fastrpc = fastrpc, cpuFallback = fallback,
            graphSplit = split, tempC = temp
        )
    }

    private suspend fun collectSpeed(tgHint: Double): CommonMetrics {
        var tg = tgHint
        var pp = 0.0
        shell.readFile("/data/local/tmp/l2_bench.log", 120)?.let {
            tg = parseTps(it) ?: tg
        }
        shell.readFile("/data/local/tmp/prof_results/cpu_ngl0/bench.json", 120)?.let {
            tg = parseTps(it) ?: tg
        }
        shell.readFile("/data/local/tmp/t12_qairt_w4a16.log", 200)?.let {
            tg = parseTps(it) ?: tg
            pp = parsePrefill(it)
        }
        return CommonMetrics(
            pp512 = pp, tg32 = tg,
            latencyMs = if (tg > 0) 1000.0 / tg else 0.0
        )
    }

    private suspend fun collectMemory(): Quad<Double, Double, Double, Double> {
        // RAM (MemFree), VRAM GPU, VMEM NPU, buffers.
        var ram = 0.0; var vmem = 0.0; var buffers = 0.0
        shell.readFile("/proc/meminfo", 40)?.let { t ->
            Regex("""MemFree:\s+(\d+) kB""").find(t)?.let {
                ram = it.groupValues[1].toDoubleOrNull()?.div(1024.0) ?: 0.0
            }
        }
        shell.readFile("/sys/class/kgsl/kgsl-3d0/gpu_mem_total", 10)?.let {
            vmem = parseKbOrMb(it)
        }
        shell.readFile("/data/local/tmp/sv_d3200.log", 200)?.let {
            vmem = parseVmem(it) ?: vmem
        }
        return Quad(ram, vmem, 0.0, buffers)
    }

    private suspend fun collectHardware():
            Six<Long, Long, Long, Long, Long, Double> {
        var smmu = 0L; var interconnect = 0L; var fastrpc = 0L
        var fallback = 0L; var split = 0L; var temp = 0.0
        shell.readFile("/data/local/tmp/l2_ftrace_results.txt", 800)?.let { t ->
            for (m in Regex("""(\d+)\s+(fastrpc[a-z_]*:[a-z_]+)""")
                .findAll(t)) {
                val v = m.groupValues[1].toLongOrNull() ?: 0L
                when {
                    m.groupValues[2].contains("interconnect") ->
                        interconnect += v
                    m.groupValues[2].contains("smmu") -> smmu += v
                    else -> fastrpc += v
                }
            }
        }
        shell.readFile("/data/local/tmp/l2_bench.log", 120)?.let {
            fallback = Regex("""fallback\s*[:=]\s*(\d+)""")
                .find(it)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
            split = Regex("""split\s*[:=]\s*(\d+)""")
                .find(it)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
        }
        shell.exec("cat /sys/class/thermal/thermal_zone0/temp", 10)
            ?.trim()?.toDoubleOrNull()?.let { temp = it / 1000.0 }
        return Six(smmu, interconnect, fastrpc, fallback, split, temp)
    }

    private fun parseTps(text: String): Double? {
        val m = Regex("""["']?decode["']?\s*[:=]\s*"?([0-9.]+)""").find(text)
            ?: Regex("""([0-9.]+)\s*tok/s""").find(text)
        return m?.groupValues?.get(1)?.toDoubleOrNull()
    }

    private fun parsePrefill(text: String): Double {
        return Regex("""["']?prefill["']?\s*[:=]\s*"?([0-9.]+)""")
            .find(text)?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
    }

    private fun parseKbOrMb(text: String): Double {
        val t = text.trim()
        val m = Regex("""(\d+(?:\.\d+)?)\s*(kB|KB|MB|B)?""").find(t)
            ?: return 0.0
        val v = m.groupValues[1].toDoubleOrNull() ?: 0.0
        return when (m.groupValues[2]) {
            "kB", "KB" -> v / 1024.0
            "B" -> v / (1024.0 * 1024.0)
            else -> v
        }
    }

    private fun parseVmem(text: String): Double? {
        return Regex("""(?:vmem|VMEM)\s*[:=]\s*(\d+(?:\.\d+)?)\s*(MiB|MB|GiB|GB)?""")
            .find(text)?.let {
                val v = it.groupValues[1].toDoubleOrNull() ?: return null
                when (it.groupValues[2]) {
                    "GiB", "GB" -> v * 1024.0
                    else -> v
                }
            }
    }
}