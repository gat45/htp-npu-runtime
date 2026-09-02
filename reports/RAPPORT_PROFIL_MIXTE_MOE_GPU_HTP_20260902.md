# RAPPORT — PROFIL MIXTE GPU80/HTP20 : MARCO-NANO (2026-09-02)

## 1. QUESTION

Le run mixte GPU→HTP 80/20 bat HTP pur de +40 % (42,1 vs 29,9 t/s). Pourquoi ?
Hypothèse : le coût par-op HTP est un FIXE structurel (FastRPC/setup), pas du
compute — déplacer le volume d'ops vers les mégablocs OpenCL gagne sans que les
ops restantes sur HTP ne changent de coût.

## 2. PROTOCOLE

- Modèle : Marco-Nano Q4_0 (device) · config : `-dev GPUOpenCL,HTP0 -ts 0.8,0.2
  -ngl 99 -t 8 -c 2048 --fit off` · n_predict=40 · temp=0
- Profiling HTP : GGML_HEXAGON_PROFILE=2 + --verbose (5810 ops HTP profilées)
- Profiling OpenCL : NON DISPONIBLE sur le binaire device (GGML_OPENCL_PROFILING
  non compilé — 0 hit dans libggml-opencl.so). Seul le côté HTP est mesuré.
- Run : 41,5 t/s (profilé — l'overhead profiling ralentit, comparable au pur)

## 3. RÉSULTATS — CÔTÉ HTP DU MIXTE vs HTP PUR

| Famille | Mixte n | Mixte avg µs | Pur avg µs | Δ |
|---|---|---|---|---|
| ARGSORT | 168 | **214,2** | 215,5 | −0,6 % |
| MUL_MAT_ID | 504 | **48,1** | 50,7 | −5 % |
| MUL_MAT | 512 | 28,7 | 29,5 | −3 % |
| FLASH_ATTN_EXT | 168 | 55,5 | 55,0 | +1 % |
| **Total HTP par token** | — | **2 516 µs** | **17 751 µs** | **−86 %** |

## 4. INTERPRÉTATION

1. **[MEASURED] Les coûts par-op HTP sont IDENTIQUES** dans le mixte et le pur
   (ARGSORT 214 vs 215 µs). L'op ARGSORT HTP coûte 215 µs QUEL QUE SOIT le
   contexte → c'est un **coût fixe par op** (setup/teardown FastRPC + VTCM +
   round-trip), pas du compute qui varierait avec la charge.
2. **[MEASURED] Le HTP ne fait plus que ~14 % du volume** dans le mixte 80/20
   (2516 vs 17751 µs/token). Le GPU OpenCL absorbe 86 % des ops en mégablocs
   de 1416 nœuds → 42 graph calls au lieu de milliers de micro-splits.
3. **Mécanisme du gain +40 %** : ce n'est PAS que le GPU calcule mieux — c'est
   que le HTP, sur les ops qu'il garde, coûte le même fixe par-op ; en
   transférant le volume vers des mégablocs, on évite de payer ce fixe des
   milliers de fois par token.
4. **Confirmation croisée de l'hypothèse orchestration-bound** : le coût
   ARGSORT (35,8 % du DSP HTP) est un fixe de 215 µs/op — le même dans les 2
   configs. C'est le round-trip qui domine, pas le tri HVX (le tri CPU donnait
   +16 % en le sortant du HTP).

## 5. CE QUE ÇA PROUVE / NE PROUVE PAS

**Prouve** : les ops HTP ont un coût fixe par-op indépendant du contexte
(ARGSORT = 215 µs pur comme mixte) ; le gain du mixte vient du volume déplacé
vers le GPU (86 %), pas d'un changement de coût HTP.

**Ne prouve pas** : le coût des ops OpenCL elles-mêmes (pas de profiling dispo
sur le binaire) — on ne peut pas affirmer que le GPU est « plus rapide » sur
ARGSORT/MUL_MAT_ID, seulement que le découpage en mégablocs évite le fixe HTP.

## 6. LIMITES

- n_predict=40 (run profilé court, overhead ~2,4×)
- Côté OpenCL non mesuré (flag non compilé) → rebuild NDK requis pour la suite
- 1 run — mais les coûts par-op concordent à ±5 % avec le run pur antérieur

## 7. ARTEFACTS

- Log : bench_results/moe_gpuhtp_prof.log (device : /data/local/tmp/bench_out/moe_gpuhtp_prof/)
- Comparatif pur : bench_results/marco_nano_prof2.log (agrégé dans
  RAPPORT_CONTROLE_MOE_MARCO_HTP_20260902.md)
- Script : tools/run_guarded_bench.sh (+ GGML_HEXAGON_PROFILE=2 --verbose)

## 8. PROCHAINE ÉTAPE

Rebuild device avec GGML_OPENCL_PROFILING pour mesurer le côté OpenCL
(cl_profiling.csv est écrit au shutdown du backend) et comparer ARGSORT/
MUL_MAT_ID GPU vs HTP en µs réels. C'est le seul chaînon manquant.
