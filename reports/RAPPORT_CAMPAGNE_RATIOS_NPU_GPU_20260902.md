# RAPPORT — CAMPAGNE RATIOS NPU × GPU — CONFIG 16 t/s (2026-09-02)

## 1. QUESTION

La config gelée « 16 t/s » (attnQ4 + MTP n_max=1 + `--fit off`) fait 11,0-11,3 t/s
wall sur HTP0 pur. Question : l'ajout du GPU Adreno (OpenCL) — dans les DEUX ordres
et à différents ratios `-ts` — peut-il dépasser ce plafond en répartissant les
opérations (CPU resté en fallback auto partout) ?

## 2. PROTOCOLE

- Modèle : Qwen3.5-9B-D2-A-MTP-attnQ4.gguf (5,08 GiB) — config 16 t/s GELÉE
- Runtime : /data/local/tmp/npu (JZ 505354ed) — devices vus : HTP0 + GPUOpenCL
  (Adreno 840, 7556 MiB)
- Flags fixes : `-dev <X> -ts <R> -ngl 99 -t 8 -c 2048 --fit off
  --spec-type draft-mtp --spec-draft-n-max 1` · n_predict=100 · temperature=0
  · prompt "The capital of France is" · CPU = fallback auto (jamais listé)
- Ordre RANDOMISÉ (seed 20260902) pour neutraliser la dérive thermique
- Protocole gardé : kill complet, port libre, health check, kill post-run,
  cooldown < 45 °C entre runs
- Runs courts (predicted < 100) = EOS précoce déterministe (temp=0), pas un bug
  (`truncated = 0` vérifié) — le t/s reste la moyenne sur l'éval effective

## 3. RÉSULTATS (ordre randomisé réel = ordre de la table)

| # | Config | -dev | -ts | t/s wall | accept | tokens | T °C |
|---|--------|------|-----|----------|--------|--------|------|
| 1 | gpu_only | GPUOpenCL | — | 4,92 | 0,85 | 100 | 35→47 |
| 2 | htp_gpu_5050 | HTP0,GPUOpenCL | 0.5,0.5 | 6,11 | 0,83 | 43 | 41→48 |
| 3 | gpu_htp_5050 | GPUOpenCL,HTP0 | 0.5,0.5 | 5,28 | 0,72 | 32 | 40→53 |
| 4 | **htp_only** | HTP0 | — | **11,26** | 0,90 | 100 | 39→60 |
| 5 | htp_gpu_8020 | HTP0,GPUOpenCL | 0.8,0.2 | 8,35 | 0,90 | 100 | 39→50 |
| 6 | gpu_htp_8020 | GPUOpenCL,HTP0 | 0.8,0.2 | 4,46 | 0,85 | 100 | 38→41 |
| 7 | gpu_htp_2080 | GPUOpenCL,HTP0 | 0.2,0.8 | 4,17 | 0,68 | 38 | 35→36 |
| 8 | htp_gpu_2080 | HTP0,GPUOpenCL | 0.2,0.8 | 5,26 | 0,85 | 100 | 34→39 |

## 4. CLASSEMENT

| Rang | Config | t/s | vs htp_only |
|------|--------|-----|-------------|
| 1 | **HTP0 pur** | **11,26** | référence |
| 2 | HTP0→GPU 80/20 | 8,35 | −26 % |
| 3 | HTP0→GPU 50/50 | 6,11 | −46 % |
| 4 | HTP0→GPU 20/80 | 5,26 | −53 % |
| 5 | GPUOpenCL pur | 4,92 | −56 % |
| 6 | GPU→HTP0 50/50 | 5,28 | −53 % |
| 7 | GPU→HTP0 80/20 | 4,46 | −60 % |
| 8 | GPU→HTP0 20/80 | 4,17 | −63 % |

## 5. INTERPRÉTATION

1. **Le HTP0 pur est imbattable sur ce workload.** Toute fraction GPU dégrade,
   proportionnellement à la part GPU. Même 20 % de GPU coûtent −26 %.
2. **L'ordre compte, et pas en faveur du GPU** : GPU premier est systématiquement
   PIRE que HTP premier au même ratio (80/20 : 4,46 vs 8,35 ; 50/50 : 5,28 vs
   6,11). Le pipeline est limité par le maillon GPU + coûts de frontière
   (sync/transfert/repack inter-devices).
3. **Le GPU Adreno seul (4,92) est 2,3× plus lent que le HTP seul (11,26)** sur
   ce Qwen3.5-D2-A en decode MTP — le HTP n'est PAS le goulot, c'est le GPU.
4. **Cohérence avec le corpus** : AXE-7 (forcing par-op HTP dégrade), literature
   FusionML « GPU50/HTP50 +8 % » NON reproduit ici (tension déjà documentée
   AGENTS.md), coût de frontière > gain de parallélisme = même famille que le
   finding « réduire le compute ne réduit pas le wall ».
5. Acceptance MTP reste saine partout (0,68-0,90) — la dégradation est un pur
   effet d'exécution/chemin, pas une perte de qualité spéculative.

## 6. VERDICT

**Le mélange NPU×GPU ne débloque pas le plafond — il l'aggrave. HTP0 pur reste
l'optimum.** Le plafond ~11 t/s n'est pas un sous-emploi du GPU ; c'est le
coût d'orchestration/DMA du chemin HTP seul. Prochain levier = orchestration
HTP (opbatch/opqueue/async), pas le GPU.

## 7. ARTEFACTS

- Script : tools/campaign_ratios_npu_gpu.sh (device : /data/local/tmp/)
- Logs : /data/local/tmp/camp_ratios/{gpu_only,htp_only,htp_gpu_5050,
  gpu_htp_5050,htp_gpu_8020,gpu_htp_8020,htp_gpu_2080,gpu_htp_2080}/server.log
  + resp.json
- Synthèse brute : /data/local/tmp/camp_ratios/synthese.txt
- Device : propre (0 process), ~34 °C

## 8. LIMITES

- 1 run par config (screening) — les 2 meilleurs candidats méritent 3×
- EOS précoces sur 4 runs (43/32/38 tokens) — t/s valide mais n court
- Température maximale atteinte : 60 °C (htp_only) — pas de throttling sévère,
  mais htp_only était pénalisé thermiquement vs les runs mixtes plus froids
  (le gain réel du HTP pur est donc > 11,26 si mesuré au même T)
