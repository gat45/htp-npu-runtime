package com.claude.local.profiler

import com.claude.local.service.RootShell

/**
 * GARDE D'INTÉGRITÉ DES SCRIPTS (point 12 de l'audit).
 *
 * L'APK exécute des scripts en ROOT depuis /data/local/tmp/tools/ — un
 * script tamponné = compromission root. On vérifie le md5 de chaque script
 * AVANT exécution :
 *   - 1er run : on enregistre le md5 (onboarding) dans
 *     /data/local/tmp/tools/.md5_ok (propriété root).
 *   - runs suivants : md5 différent → REFUS d'exécuter (status "integrity").
 *
 * Modèle : trust-on-first-use + détection de modification.
 */
object ScriptGuard {
    private const val ALLOWLIST = "/data/local/tmp/tools/.md5_ok"

    /** Vérifie un script ; retourne true si OK à exécuter. */
    suspend fun verify(shell: RootShell, script: String): Boolean {
        val md5 = md5Of(shell, script) ?: return false
        val known = loadAllowlist(shell)
        val prev = known[script]
        return when {
            prev == null -> {
                // Onboarding : enregistrer le md5 actuel.
                saveAllowlist(shell, known + (script to md5))
                true
            }
            prev == md5 -> true
            else -> false    // script modifié → refuse (risque root)
        }
    }

    private suspend fun md5Of(shell: RootShell, script: String): String? {
        val out = shell.exec(
            "md5sum /data/local/tmp/tools/$script | cut -d' ' -f1", 15)
        return out?.trim()?.takeIf { it.isNotBlank() }
    }

    private suspend fun loadAllowlist(shell: RootShell): Map<String, String> {
        val text = shell.readFile(ALLOWLIST, 200) ?: return emptyMap()
        val out = mutableMapOf<String, String>()
        for (line in text.lineSequence()) {
            val parts = line.trim().split(Regex("\\s+"), limit = 2)
            if (parts.size == 2) out[parts[1]] = parts[0]
        }
        return out
    }

    private suspend fun saveAllowlist(shell: RootShell,
                                      map: Map<String, String>) {
        val body = map.entries.joinToString("\n") { (s, m) -> "$m $s" }
        shell.exec("echo \"$body\" > $ALLOWLIST", 10)
    }
}