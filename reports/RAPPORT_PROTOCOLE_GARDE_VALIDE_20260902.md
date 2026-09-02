# RAPPORT — VALIDATION DU PROTOCOLE GARDÉ (2026-09-02)

## 1. RÉSULTAT DU SMOKE TEST

Le script `tools/run_guarded_bench.sh` (protocole complet imposé par l'audit
équipe) a été exécuté sur device de bout en bout :

```
guarded bench: sh run_guarded_bench.sh guard_test 8542 16 "The capital of France is"
(resolve) => RESULT guard_test tps=1.9352 accept=(vide) mean_len=(vide) T=29->32C pid=17140
             DONE guard_test
```

Log serveur (meta.txt archivé) :
```
prompt eval time =   955.61 ms /  5 tokens (5.23 t/s)
       eval time =  7751.03 ms / 16 tokens (1.94 t/s)
      total time =  8706.64 ms / 21 tokens
   graphs reused =          15
```

- T_start = 29 °C, T_end = 32 °C (device froid)
- PID serveur = 17140, 0 process résiduel après le run
- Ce run est un SMOKE TEST structurel (prompt court de 5 tokens, runtime `/data/local/tmp/npu`,
  chemin absolu, kill + vérif port OK). Sa valeur en tok/s n'a aucune signification
  comparative — il valide le MÉCANISME, pas la performance.

## 2. CE QUE LE PROTOCOLE GARDÉ APPLIQUE (étape par étape)

| # | Étape | Implémentation | Vérifié |
|---|---|---|---|
| 1 | KILL ALL | `pkill -f llama-server` (pattern générique, matche `./llama-server`) | ✅ |
| 2 | VERIFY NO LLAMA | boucle `while` jusqu'à `n=0` (max 20×3 s) | ✅ |
| 3 | VERIFY PORT FREE | `curl /health` DOIT échouer avant start | ✅ |
| 4 | START | `nohup "$BIN"` chemin ABSOLU + env dédiée | ✅ |
| 5 | VERIFY PID + HEALTH | `kill -0 $SRV` + health `"status":"ok"` (max 90×3 s) | ✅ |
| 6 | PID lié au port | `ps` → `llama-server` réel (pid) | ✅ |
| 7 | WARMUP | `WARMUP=1` optionnel (4 tokens) | (défaut OFF) |
| 8 | BENCH | 1 requête `n_predict` donné, temperature=0 | ✅ |
| 9 | SAVE | `meta.txt` = config + T_start/T_end + timing + pid | ✅ |
| 10 | KILL + VERIFY CLEAN | kill + pkill + boucle jusqu'à 0 process | ✅ |

Contrairement aux scripts `/tmp` antérieurs :
- plus de `pkill -f npu28202/llama-server` (ne matchait jamais l'argv réel) ;
- plus de lancement concurrent sur le même port (vérification port libre) ;
- plus de réponse « fantôme » venant du serveur du run précédent
  (le cas F2 : serveur F1 vivant + bind échoué + donnée attribuée à tort).

## 3. DONNÉES NGRAM RÉÉVALUÉES (suite à l'audit)

Les anciens résultats doivent être reclassés explicitement :

| Run | t/s | Statut après audit |
|---|---|---|
| ngram3 (02:13) — 10,27 t/s | 10,27 | **INVALID / NON REPRODUCTIBLE** — état device exceptionnel (prefill 338 t/s), non retrouvé ensuite |
| ngramF1 (02:27) | 2,67 | **CONTAMINÉ** — serveur F1 jamais tué (pattern pkill faux) |
| ngramF2 (02:29) | 2,82 | **INVALID** — bind port échoué, réponse venue du serveur F1 (task 28 dans le log F1) |
| ngrmF1 (03:36, corrigé) | 2,55 | VALIDE (protocole simple corrigé) |
| ngrmF2 (03:44, corrigé) | 3,36 | VALIDE (protocole simple corrigé) |

**Valeurs ngram fiables à ce jour : 2,55 / 3,36 t/s** (et 2,67 contaminé mais cohérent).
Le ngram-mod sur ce device reste **inférieur au MTP (8,8-9,9 t/s)** et au HTP simple
(9,46-9,69 t/s). Le 10,27 n'est PAS une donnée scientifique exploitable.

## 4. ÉTAT DES OUTILS

| Outil | Statut |
|---|---|
| `tools/run_guarded_bench.sh` | ✅ validé (smoke test complet) sur device |
| `tools/bench_ngram_final_fixed.sh` | ✅ validé 2 runs propres |
| `tools/telemetry_full_sm8850.sh` | ⚠️ en cours — sortie vide en arrière-plan (buffering/noHup), fonctions validées individuellement ; à fiabiliser |
| 190 scripts `tools/*.sh` | ✅ syntaxe OK (`bash -n` / `sh -n`) |

## 5. PROCHAINE ÉTAPE

Le protocole gardé est opérationnel → relancer la **confirmation 3× propre** du
cumul attnQ4 + MTP n_max=1 + `--fit off` (le 10,69 t/s historique) avec
`run_guarded_bench.sh` en 3 runs séparés (ports 8542/8543/8544), puis la
campagne 64 tokens MTP1 vs HTP-only demandée. Ces nouvelles runs produiront
chacune un `meta.txt` exploitable et nettoieront leur process.

Device : 0 process résiduel, température nominale (32 °C).