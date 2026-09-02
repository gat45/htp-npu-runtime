# RAPPORT — CONFIG 16 t/s TESTÉE SUR 100 ET 300 TOKENS (2026-09-02)

## 1. QUESTION POSÉE

La config « 16 t/s » (attnQ4 + MTP n_max=1 + `--fit off`) avait été validée sur
**16 tokens** (9,4-10,4 t/s wall, 16,4-18,9 effectifs). Objectif : vérifier si ce
régime **tient sur des générations longues** (100 puis 300 tokens) — le test qui
détermine si le gain est réel ou un artefact de run court.

## 2. RÉSULTATS PROPRES (device stabilisé, post-reboot > 30 min)

| Run | tokens | eval ms | ms/tok | **wall t/s** | acceptance | mean_len | **effectifs** (wall × mean_len) |
|---|---|---|---|---|---|---|---|
| ref16 (réf. matin) | 16 | 1454 | 96,9 | **10,32** | 0,750 | 1,75 | 18,1 |
| t100_clean | 100 | 8754 | 88,4 | **11,31** | 0,904 | 1,90 | 21,5 |
| t300_clean | 300 | 26814 | 89,7 | **11,15** | 0,874 | 1,87 | 20,9 |

**Verdict : le régime tient. Pas de dégradation avec la longueur.**
- 100 tokens : 11,31 t/s wall (acceptance 90 %)
- 300 tokens : 11,15 t/s wall (acceptance 87 %)
- Écart 16→300 tokens : < 8 % — débit stable, pas d'effet longueur/attention

**Le « 16 t/s » est dépassé sur TOUTES les longueurs en métrique effective
(18-21,5) ET le wall réel (10,3-11,3) est ~2× le wall historique (~5,8 t/s).**

## 3. FAUX DÉPART : LES RUNS POST-REBOOT (leçon méthodologique)

Les premiers runs (t100, t300 avant reboot, puis juste après) donnaient
1,5-1,9 t/s. Cause identifiée : **activité système post-reboot** — load average
24,8, kworker `mms_wq`, dexopt/installd en arrière-plan, CPU big figé en lecture
au repos.

**Le CPU n'était PAS bridé** (vérifié : `policy6 max=4608000`, fréquence montée à
3,4 GHz sous charge, governor `walt`). Les lectures à 883 MHz étaient la
fréquence **idle** normale.

| Run | État device | Résultat | Verdict |
|---|---|---|---|
| t100 (1er, post-boot) | load 24, kworkers | 1,71-1,83 t/s | ❌ INVALIDE (contaminé) |
| t300 (1er, post-boot) | encore chargé | 5,72 t/s | ⚠️ PARTIEL |
| ref16 (stabilisé) | load bas | 10,32 t/s | ✅ propre |
| t100_clean (stabilisé) | load bas | 11,31 t/s | ✅ propre |
| t300_clean (stabilisé) | load bas | 11,15 t/s | ✅ propre |

**Protocole imposé pour la suite : après reboot, attendre 30+ min (ou load < 4)
avant tout benchmark.** Un run post-boot n'est JAMAIS une mesure valide.

## 4. DIAGNOSTIC TECHNIQUE (ce qui tourne)

- HTP0 actif : splits MUL_MAT/FLASH_ATTN_EXT/GLU sur HTP0 confirmés dans les logs
- Modèle : Qwen3.5-9B-D2-A-MTP-attnQ4.gguf (5,45 Go, 5,08 GiB)
- Runtime : /data/local/tmp/npu (JZ 505354ed + AXE-8), MTP draft n_max=1
- Acceptance 0,87-0,90 sur long — meilleure que le 0,75 du run 16 (le draft
  profite du contexte qui s'allonge)
- Mismatches allocator présents (DIAGNOSTIC plan/identity) mais SANS impact
  wall observable (débit stable sur 300 tokens)

## 5. CROISEMENT AVEC LES DONNÉES ANTÉRIEURES

| Mesure | wall t/s | Source |
|---|---|---|
| Historique 16,6 « effectifs » (16 tok, chaud) | ~5,8 wall | 2026-08, non contrôlé |
| Config gelée 16 tokens (3 runs) | 9,40-10,40 | ce matin |
| **Config gelée 100 tokens (propre)** | **11,31** | aujourd'hui |
| **Config gelée 300 tokens (propre)** | **11,15** | aujourd'hui |
| ngram-mod (propre, 2 runs) | 2,55-3,36 | hier — réfuté |
| HTP seul sans MTP | 9,46-9,69 | campagne placement |

**Conclusion du croisement** : la config gelée est l'optimum actuel et son gain
est CONFIRMÉ sur génération longue. MTP sur HTP = seul levier spéculatif valable.

## 6. CLASSIFICATION FINALE

**A) RÉSULTAT REPRODUIT ET DÉPASSÉ** — le comportement MTP est identique
(acceptance 75-90 %, mean_len 1,75-1,90), la métrique wall est ~2× l'historique,
les effectifs (18-21,5) dépassent le 16,6 historique, y compris sur 300 tokens.

## 7. ARTEFACTS

- Scripts : `tools/test_16tps_100_300.sh`, `tools/run_guarded_bench.sh`,
  `tools/run_16tps_config.sh`
- Logs device : /data/local/tmp/test_16300/{t100_clean,t300_clean}/server.log
  + meta.txt (timing, acceptance, mean_len, PID, T_start/T_end)
- Device : propre (0 process), 38 °C

## 8. LIMITES HONNÊTES

- Prompt de test court (5 tokens) — un prompt long avec prefill important peut
  changer le ratio (à tester si besoin)
- 1 run par longueur propre (ref16 = 1, t100 = 1, t300 = 1) — les 3 concordent
  à ±5 %, mais une répétition 3× sur 300 tokens solidifierait le chiffre
- La thermique monte à 38 °C seulement sur 27 s de run — un run 300 tokens
  répété sans cooldown finirait par throttler (protocole cooldown conservé)