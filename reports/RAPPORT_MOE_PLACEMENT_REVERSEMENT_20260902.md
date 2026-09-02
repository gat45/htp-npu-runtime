# RAPPORT — RENVERSEMENT PLACEMENT MoE : GPU BATS HTP SUR MARCO-NANO (2026-09-02)

## 1. QUESTION

La campagne ratios Qwen-dense (11,26 t/s HTP pur, toute fraction GPU dégradait)
a établi « HTP pur = optimum ». Question : ce classement tient-il pour un **MoE
ultra-sparse** (Marco-Nano 8B / 0,6B actifs, 256 experts top-8) où le compute
actif est ~13× plus petit et le routing (ARGSORT 35,7 % DSP) domine ?

## 2. CAMPAGNE SCREENING (8 configs randomisées, seed 20260903, n_predict=100)

Script : tools/campaign_ratios_npu_gpu_moe.sh (device /data/local/tmp/)
Modèle : /data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf (4,36 GiB, PAS de MTP)

| Config | -dev | -ts | t/s wall | T °C |
|---|---|---|---|---|
| gpu_htp_8020 | GPUOpenCL,HTP0 | 0.8,0.2 | **39,11** | 44→47 |
| gpu_htp_5050 | GPUOpenCL,HTP0 | 0.5,0.5 | 37,46 | 33→46 |
| htp_only | HTP0 | — | 30,64 | 37→49 |
| gpu_htp_2080 | GPUOpenCL,HTP0 | 0.2,0.8 | 29,89 | 38→49 |
| gpu_only | GPUOpenCL | — | 22,96 | 38→42 |
| htp_gpu_8020 | HTP0,GPUOpenCL | 0.8,0.2 | 22,59 | 38→42 |
| htp_gpu_5050 | HTP0,GPUOpenCL | 0.5,0.5 | 22,51 | 37→44 |
| htp_gpu_2080 | HTP0,GPUOpenCL | 0.2,0.8 | 22,50 | 38→41 |

**Pattern** : GPU EN PREMIER (gpu_htp_*) ≥ HTP pur > HTP en premier (htp_gpu_*)
≈ GPU pur. L'ordre du -dev ET le ratio comptent, différemment du Qwen.

## 3. CONFIRMATION A/B/A/B (n_predict=200, script tools/bench_moe_placement_ab.sh)

A = HTP0 pur · B = GPUOpenCL,HTP0 -ts 0.8,0.2

| Run | Config | t/s wall | T °C |
|---|---|---|---|
| A1 | HTP0 pur | 30,26 | 34→49 |
| **B1** | **GPU→HTP 80/20** | **39,18** | 37→49 |
| A2 | HTP0 pur | 29,61 | 38→49 |
| **B2** | **GPU→HTP 80/20** | **45,00** | 45→50 |

**Moyennes : A = 29,93 t/s · B = 42,09 t/s → GPU OpenCL bat HTP de +40 %**
Reproductible sur 2 paires adjacentes. B2 (départ 45 °C, le plus chaud) est le
PLUS rapide → le gain n'est PAS un artefact thermique (sens inverse attendu).

## 4. EXPLICATION MÉCANISTIQUE (logs B1)

- **OpenCL reçoit des mégablocs de 1416 nœuds** : RMS_NORM + attention complète
  + FLASH_ATTN_EXT + **SOFT_MAX + ARGSORT + MUL_MAT_ID (MoE entier fusionné)**
  + GLU — un seul graph géant envoyé au GPU
- **HTP0 ne reçoit que des micro-splits de 58 nœuds** (2-3 par layer)
- Comptage B1 : CPU 1212 · HTP0 1010 · **OpenCL 202** (mais 202 × 1416 nœuds =
  le volume dominant)

**Pourquoi le renversement** : sur un MoE ultra-sparse, le goulot n'est PAS le
matmul (0,6B actifs seulement) mais le **routing + orchestration par op**.
L'Adreno exécute le MoE en un mega-kernel fusionné (202 graph calls) alors que
le HTP le découpe en milliers de micro-splits FastRPC → l'avantage compute du
HTP s'efface et son coût d'orchestration par-op domine. C'est le MÊME
mécanisme que le gap dispatch QAIRT/GGML documenté (mega-kernels vs op-par-op),
mais cette fois au bénéfice du GPU.

## 5. CROISEMENT QWEN-DENSE vs MARCO-MoE

| Modèle | HTP pur | GPU→HTP 80/20 | Champion |
|---|---|---|---|
| Qwen3.5-9B dense (MTP1) | **11,26** | 8,35 (−26 %) | HTP |
| Marco-Nano 8B MoE | 29,93 | **42,09 (+40 %)** | GPU |

**Le classement de placement dépend de l'architecture du modèle.** Pour un
modèle dense compute-bound → HTP. Pour un MoE sparse orchestration-bound → GPU
(Adreno, mega-kernels OpenCL).

## 6. CONSÉQUENCES

1. **[MEASURED]** Le « HTP pur optimum » n'est PAS universel — il vaut pour le
   Qwen dense, PAS pour les MoE sparses
2. **[MEASURED]** Sur Marco-Nano : GPU→HTP 80/20 = 42 t/s vs HTP pur 30 →
   potentiel **+40 %** si un MoE sparse devait être servi par ce device
3. **[MEASURED]** L'ordre -dev prime : GPU premier gagne, HTP premier perd
   (22,5 t/s — pire que HTP pur !). Le scheduler pipe-line est sensible à
   l'ordre exact des backends
4. **[PROBABLE]** Le levier n'est pas « quel silicium » mais « comment découper
   le graph » : mega-kernels fusionnés (OpenCL) > micro-splits (HTP) quand le
   compute actif est faible. Cohérent avec AXE-8 (topo sort, 2030→291 splits)
5. Sorties A vs B diffèrent (déterministes par config) — attendu (routing)

## 7. LIMITES / HONNÊTETÉ

- 1 run/config en screening, mais la confirmation A/B/A/B (2 paires, n=200)
  est propre : B > A dans les DEUX paires, amplitudes 39-45 vs 29-30
- B2 à 45 °C de départ (le plus chaud) = le plus rapide : variance CDSP/device,
  pas thermique — à noter mais ne change pas le signe du résultat
- Marco-Nano n'a PAS de MTP : le gain MTP du Qwen reste orthogonal
- Re-quantisation Q8_0→Q4_0 (double quant) : OK perf, pas qualité
- Pas de contrôle GPU pur long : gpu_only (22,96) semble souffrir d'un autre
  effet (peut-être lm_head/CPU fallback) — à creuser si le MoE devient un axe

## 8. ARTEFACTS

- Scripts : tools/campaign_ratios_npu_gpu_moe.sh, tools/bench_moe_placement_ab.sh
- Logs device : /data/local/tmp/camp_ratios_moe/{8 configs}/ ·
  /data/local/tmp/moe_ab/{moe_A1,moe_B1,moe_A2,moe_B2}/
- Synthèses : camp_ratios_moe/synthese.txt · moe_ab/synthese.txt
- Device : propre (0 process)

## 9. PROCHAINES ÉTAPES PROPOSÉES

1. Marco-Nano × MTP n'est pas possible (pas de tête MTP) — tester un MoE AVEC
   MTP (ex : Marco-Mini 17,3B est trop gros ; chercher un MoE ≤ 8B avec MTP)
2. Confirmer le mécanisme : run B avec GGML_HEXAGON_PROFILE pour comparer le
   coût ARGSORT/MUL_MAT_ID sur OpenCL vs HTP (le tri GPU est-il inclus dans le
   mega-bloc ?)
3. Pour le Qwen dense : l'implémentation TOP_K HTP (axe ARGSORT) reste le
   levier, MAIS le Qwen n'utilise PAS MUL_MAT_ID → gain attendu ~0 (vérifié :
   0 ARGSORT/0 MUL_MAT_ID dans les logs Qwen)
