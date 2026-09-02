# RAPPORT — CONTRÔLE MoE-SPARSE : MARCO-NANO SUR HTP0 + PROFILAGE (2026-09-02)

## 1. OBJECTIF

Trancher compute-bound vs orchestration-bound avec un **modèle de contrôle** :
un MoE ultra-sparse (17,3B total / 0,86B actifs chez Marco-Mini ; on teste le
**Marco-Nano 8B / 0,6B actifs**, Q4_0, archi qwen3moe) sur le MÊME HTP0, mêmes
conditions que le Qwen3.5-9B dense (11,26 t/s wall).

Prédiction : si le plafond est le volume de calcul actif → le MoE doit beaucoup
accélérer. S'il est orchestration/mouvement de données → gain limité alors que
le compute chute.

## 2. MATÉRIEL / MODÈLE

- Device : OnePlus 15 / SM8850 / HTP v81 — SAME runtime JZ 505354ed
- Modèle : Marco-Nano-Instruct (ATH-MaaS) converti par mradermacher en Q8_0
  (8 527 233 568 o), re-quantisé Q4_0 par notre fork llama-quantize :
  **4 569 976 352 o (4 356 MiB, 4,56 BPW)** — SHA à archiver
- Archi : qwen3moe — supportée par le fork (qwen3moe.cpp) + HTP_OP_MUL_MAT_ID
- Flags : `-dev HTP0 -ngl 99 -t 8 -c 2048 --fit off` · n_predict=100 · temp=0
- PAS de MTP (Marco-Nano n'a pas de tête MTP) — mesure baseline pure

## 3. RÉSULTATS WALL

| Modèle | fichier | t/s wall | ms/tok | contexte |
|---|---|---|---|---|
| Qwen3.5-9B dense + MTP1 | 5,08 GiB | 11,26 | 88,8 | même HTP0 froid |
| **Marco-Nano 8B MoE** | 4,36 GiB | **26,72** | **37,4** | même HTP0 froid |
| Marco-Nano + profil PMU | idem | 15,81 | 63,2 | overhead profil |

**×2,4 de wall-clamp sur calculateur actif 13× plus petit (0,6 vs ~9,2B actifs).

## 4. PROFILAGE MAISON (GGML_HEXAGON_PROFILE=2 + --verbose, 39 170 ops, 40 tokens)

| Famille | n | total us | avg us | % DSP |
|---|---|---|---|---|
| **ARGSORT** (tri top-k experts) | 1 176 | 253 386 | 215,5 | **35,7 %** |
| **MUL_MAT_ID** (experts) | 3 528 | 178 990 | 50,7 | **25,2 %** |
| MUL_MAT (attention/proj) | 3 584 | 105 746 | 29,5 | 14,9 % |
| FLASH_ATTN_EXT | 1 176 | 64 696 | 55,0 | 9,1 % |
| ADD | 9 504 | 22 998 | 2,4 | 3,2 % |
| RMS_NORM | 4 746 | 20 831 | 4,4 | 2,9 % |
| ROPE | 2 352 | 19 132 | 8,1 | 2,7 % |
| MUL / SWIGLU / DIV / divers | ~9 000 | ~44 000 | — | ~6 % |
| **TOTAL DSP ops** | — | **710 034** | — | 100 % |
| OPBATCH (batches HTP) | 1 218 | 812 184 | — | vs wall |

### Décomposition par token (40 tokens)

- Temps DSP pur (somme ops) : 710 ms / 40 = **17,75 ms/token**
- Temps OPBATCH (FastRPC+batch) : 812 ms / 40 = **20,3 ms/token**
- Wall profilé : 2 530 ms / 40 = **63,2 ms/token** (overhead profiling ~2,4×)
- Wall propre (run non profilé) : 3 705 ms / 100 = **37,4 ms/token**

## 5. LA PREUVE MÉCANISTIQUE (croisement Qwen-dense vs Marco-MoE)

| Métrique | Qwen dense (MTP1) | Marco-MoE | Ratio |
|---|---|---|---|
| Paramètres actifs/token | ~9,2B | 0,6B | ×0,07 |
| DSP MUL_MAT total/token | ~65 ms | ~8,7 ms (MUL_MAT+MUL_MAT_ID) | ×0,13 |
| **Wall / token** | 88,8 ms | 37,4 ms | **×0,42** |

**Lecture** : le compute actif a été divisé par ~7-15×, mais le wall n'est divisé
que par 2,4×. Le composant de wall qui ne suit PAS la réduction (88,8 → 37,4 :
~50 ms de surcoût par token au-delà du compute) est l'**orchestration fixe** :
FastRPC/batches, ARGSORT routing, DMA, sync, CPU host-side.

**Nouveau fait dans ce profil** : sur un MoE, le goulot DSP n'est plus le
MUL_MAT mais l'**ARGSORT (tri du top-k des 256 experts — 215 µs/op, 35,7 % du
temps DSP)**. Même le HTP va vite : 26,7 t/s par token unique. La limite est la
chaîne par-étape, pas le silicium.

## 6. CONSÉQUENCE EXPÉRIMENTALE

L'hypothèse « réduction du compute → gain wall » est réfutée par contraste :
- Q8→Q4 du Qwen (MUL_MAT −17 %) → wall ~inchangé
- MoE ×7-15 moins de compute actif → wall ×2,4 seulement

Le prochain levier est l'**ARGSORT/top-k routing (35,7 % DSP)** — réutilisable
dans le Qwen hybride via la sélection d'experts, et l'orchestration host-side.

## 7. LIMITES

- Marco-Nano n'a pas de MTP : le gain MTP du Qwen (×1,8) reste orthogonal
- Le run profilé (15,8 t/s) sous-estime : overhead de logging massif
- mmap : fichier 4,36 GiB → pas de pression ZRAM (aucun OOM, contrairement aux 7,3 Go)
- 1 run par config — à répéter 3× pour écart-type
- La re-quantisation Q8_0→Q4_0 double-quantifie (perte) — acceptable pour un
  test de throughput, pas de qualité

## 8. ARTEFACTS ET PISTES

- DLL : EL1 2055047A /d/models_marco (Q8_0 8527233568 o, Q4_0 4569976352 o)
- Logs : bench_results/marco_nano_prof.log (prof1), marco_nano_prof2.log (prof2)
- Scripts : tools/campaign_ratios_npu_gpu.sh (éprouvé), run_guarded_bench.sh
- Pipeline de contrôle réutilisable : download Q8_0 → llama-quantize Q4_0
  (build-wsl/bin/llama-quantize) → push adb → run_guarded_bench + PROFILE=2
- Prochain test : Marco-Nano × ratios HTP/GPU (le même fichier est prêt) pour
  vérifier si le MoE change le classement placement ; et ubatch/opqueue sur le MoE