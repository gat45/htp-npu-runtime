package com.claude.local.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

/**
 * Exécute des commandes root (`su -c`) sur le device.
 * Best-effort : toute erreur est capturée, jamais de crash.
 *
 * IMPORTANT (correctifs d'audit) :
 * - les scripts tools/ supposent un cwd précis (/data/local/tmp/npu…) :
 *   on lance via `cd /data/local/tmp && sh tools/x.sh`.
 * - au timeout on tue TOUT le process tree (pas seulement su) pour éviter
 *   les orphelins (llama-server, geniex-bench) qui continuent en root.
 */
object RootShell {
    private const val TAG = "RootShell"

    /** Retourne true si `su` est dispo (Magisk/KernelSU/APatch). */
    suspend fun available(): Boolean = withContext(Dispatchers.IO) {
        try {
            val p = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val ok = p.waitFor(5, TimeUnit.SECONDS) && p.exitValue() == 0
            p.destroy()
            ok
        } catch (e: Exception) {
            Log.w(TAG, "root check failed", e)
            false
        }
    }

    /**
     * Exécute un script root depuis /data/local/tmp (cwd correct).
     * cmd = nom du script sous /data/local/tmp/tools/ (ex. "bench_cpu.sh").
     */
    suspend fun execTool(script: String, timeoutSec: Long = 120): String? =
        exec("cd /data/local/tmp && sh /data/local/tmp/tools/$script",
             timeoutSec)

    /** Exécute une commande root ; retourne stdout+stderr ou null en échec. */
    suspend fun exec(cmd: String, timeoutSec: Long = 120): String? =
        withContext(Dispatchers.IO) {
            val p = try {
                Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            } catch (e: Exception) {
                Log.w(TAG, "exec failed: $cmd", e); return@withContext null
            }
            try {
                val out = StringBuilder()
                val err = StringBuilder()
                val reader = Thread {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                        r.forEachLine { out.append(it).append("\n") }
                    }
                }.apply { start() }
                val errReader = Thread {
                    BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                        r.forEachLine { err.append(it).append("\n") }
                    }
                }.apply { start() }
                val done = p.waitFor(timeoutSec, TimeUnit.SECONDS)
                reader.join(2000)
                errReader.join(2000)
                if (!done) {
                    // Tue TOUT le process tree (pas seulement su).
                    killTree(p)
                    Log.w(TAG, "timeout: $cmd")
                    return@withContext null
                }
                val text = out.toString() + err.toString()
                p.destroy()
                text
            } catch (e: Exception) {
                Log.w(TAG, "exec failed: $cmd", e)
                null
            }
        }

    private fun killTree(p: Process) {
        try { p.destroyForcibly() } catch (_: Exception) {}
        try {
            // Tue les enfants (llama-server/geniex-bench/llama-bench) :
            // on ne connaît pas le pgid du su → pkill par nom (sûr, root).
            Runtime.getRuntime().exec(arrayOf("su", "-c",
                "pkill -f llama-server 2>/dev/null; " +
                "pkill -f geniex-bench 2>/dev/null; " +
                "pkill -f llama-bench 2>/dev/null; " +
                "pkill -f npu_profiler 2>/dev/null"))
                .waitFor(3, TimeUnit.SECONDS)
        } catch (_: Exception) {}
    }

    /** Lit un fichier root (ex. /data/local/tmp/...) via su. */
    suspend fun readFile(path: String, lines: Int = 2000): String? =
        exec("cat $path | tail -n $lines", 60)
}