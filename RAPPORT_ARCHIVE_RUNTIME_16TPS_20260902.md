# RAPPORT COMPLET REPRODUCTIBLE — CONFIG 16 T/S + CAMPAGNES 2026-09-02
======================================================================

Date       : 2026-09-02
Auteur     : campagne automatisée (team), consigné le 2026-09-02
Statut     : RAPPORT FINAL + ARCHIVE RUNTIME GELÉE
Archive    : `D:\archive_16tps_20260902\` (copie EXACTE du runtime device)

Ce rapport est la synthèse reproductible de TOUTES les campagnes du
02/09/2026. Il référence l'archive runtime gelée (binaires + .so + skel)
qui a produit les chiffres, les scripts exacts, et les rapports détaillés.

======================================================================
1. OBJECTIF ET CONTENU DE L'ARCHIVE
======================================================================

```
D:\archive_16tps_20260902\
├── runtime_device\              ← COPIE GELÉE du runtime QUI A PRODUIT LES CHIFFRES
│   ├── llama-server             (binaire Android, 7 424 o)
│   ├── ggml-hexagon.cfg
│   ├── libggml.so / libggml-base.so / libggml-cpu.so
│   ├── libggml-hexagon.so       (backend hexagon JZ, 3 536 560 o)
│   ├── libggml-opencl.so        (GPU Adreno / OpenCL)
│   ├── libllama.so / libllama-common.so / libllama-server-impl.so
│   ├── libmtmd.so / libcdsprpc.so / libOpenCL.so / libomp.so
│   ├── vendor.qti.hardware.dsp@1.0.so / vendor.qti.hardware.dsp-V1-ndk.so
│   └── htp\
│       ├── libggml-htp-v81.so        ← SKEL HTP v81 REBUILDÉ (734 920 o, md5 07baf2c0…)
│       ├── libggml-htp-v68/69/73/75/79.so   (versions de référence)
│       ├── libggml-htp-v81.so.dspqueue-works  (variante dspqueue)
│       └── lib_june_20260602\       ← VIEUX STACK juin (avant rebuild skel)
├── scripts\
│   ├── run_guarded_bench.sh      (protocole gardé v2 — kill/port/PID/health)
│   ├── run_16tps_config.sh       (config gelée 16 t/s — voir §2)
│   ├── test_16tps_100_300.sh     (test 100 puis 300 tokens)
│   ├── campaign_3x300.sh         (3 × 300 tokens)
│   ├── campaign_ratios_npu_gpu.sh      (8 configs Qwen dense)
│   ├── campaign_ratios_npu_gpu_moe.sh  (8 configs Marco-Nano MoE)
│   ├── bench_moe_placement_ab.sh       (A/B/A/B HTP vs GPU→HTP 80/20)
│   ├── bench_argsort_ab.sh             (A/B/A/B ARGSORT HTP vs CPU)
│   ├── telemetry_full_sm8850.sh        (télémétrie 250-500 ms)
│   └── device\                    (320 scripts device bruts — historique complet)
├── models\
│   ├── [non copiés — 5 Go+ chaque ; manifeste §8 avec chemins + tailles]
│   └── NOTE : Qwen attnQ4/MXFP4/7.3G sur device ; Marco-Nano Q4_0 sur
│             device ET D:\models_marco\
├── results\
│   ├── bench_out_16tps\          (metas réels : ref16 10,32 t/s accept 0,75…)
│   ├── camp_ratios_qwen\synthese.txt   (8 configs Qwen — §3)
│   ├── camp_ratios_moe\synthese.txt    (8 configs MoE — §4)
│   └── argsort_ab\synthese.txt         (A/B/A/B — §5)
├── reports\                       (9 rapports détaillés .md — §9)
├── sha256_runtime.txt             (empreintes SHA-256 des .so + binaire)
└── git_state_jz_fork.txt          (état exact du fork au moment de l'archive)
```

**Source device de la copie** : `/data/local/tmp/npu/` (llama-server + .so
top-level) — c'est le runtime « JZ » du 29-30/08/2026 qui a produit les
chiffres (voir §2). Les .so du sous-répertoire `/data/local/tmp/npu/lib/`
datent du 02/06/2026 (vieux stack, gardé en référence).

======================================================================
2. LA CONFIG « 16 T/S » — GELÉE ET REPRODUITE
======================================================================

**Modèle** : `Qwen3.5-9B-D2-A-MTP-attnQ4.gguf` — 5 450 272 384 o (5,08 GiB),
attention re-quantifiée Q8→Q4_0, MTP 1 couche (442 tensors), sur le device :
`/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf`

**Runtime** : `/data/local/tmp/npu/llama-server` — fork JZ construit sur
`505354ed` (qwen35 GDN fix) + AXE-8 (gallocr, commit 5618c305) + opt_mm_rows
(5291e12a) ; skel HTP v81 rebuildé 734 920 o. Source build :
`D:/jz_work/ggml-hexagon-fork` (NDK clang 18.0.3, r27c). Voir §7 pour
l'état git exact.

**Commande exacte** (run_16tps_config.sh + run_guarded_bench.sh) :
```sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

/data/local/tmp/npu/llama-server \
    -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf \
    -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
    --spec-type draft-mtp --spec-draft-n-max 1 \
    --host 127.0.0.1 --port <port>
```
Requête : `{"prompt":"The capital of France is","n_predict":N,"temperature":0}`

**Contraintes opératoires** (non négociables) :
1. Départ froid < 45 °C (zone thermique qmx, thermal_zone21 sur ce device).
2. `--fit off` OBLIGATOIRE (HTP0 ne rapporte pas sa mémoire libre au CDSP ;
   le fit auto avorte après lancements répétés).
3. Un seul process à la fois + kill vérifié + port libre vérifié avant start
   (protocole gardé run_guarded_bench.sh — voir l'audit
   RAPPORT_AUDIT_SCRIPTS_20260902.md : les anciens pkill non vérifiés ont
   contaminé des runs).
4. ZRAM 5 Go = seuil d'arrêt (protection OOM/reboot).

**Mesures réelles archivées** (results/bench_out_16tps/) :
```
ref16  (q4m1_ref16, n=16) : eval 1454,01 ms / 16 tok → 10,32 t/s
                             acceptance 0,75 (6/8) · mean_len 1,75
                             T 32→47 °C
16tps_r2 (n=16)            : eval 2940,97 ms / 16 tok → 5,10 t/s (contaminé
                             par load résiduel post-reboot — cf. rapport)
q4m1_100t (n=100)          : ~11,0-11,3 t/s (voir RAPPORT_16TPS_SOUTENU)
```

**INTERPRÉTATION CORRECTE DU « 16 t/s »** (⚠ à ne pas mal citer) :
Le « 16,4-18,9 effectifs » = wall t/s × mean_len (formule historique).
Le wall-clock réel = **8,3-11,3 t/s** selon la fenêtre thermique/charge.
Le 16 t/s est un artefact de formule (drafts supposés gratuits) — jamais
un débit wall soutenu. La campagne 3×300 tokens a consolidé :
**11,01 ± 0,16 t/s wall** (r1 11,12 · r2 10,78 · r3 11,13), accept 0,83-0,87.

======================================================================
3. CAMPAGNE RATIOS NPU×GPU — QWEN DENSE (résultats bruts archivés)
======================================================================

Script : campaign_ratios_npu_gpu.sh (ordres randomisés seed 20260902)
Modèle  : attnQ4 + MTP n_max=1, n_predict=100, CPU en auto (fallback)
Source  : results/camp_ratios_qwen/synthese.txt

| Rang | Config (-dev / -ts)      | t/s    | vs HTP pur | accept |
|------|--------------------------|--------|------------|--------|
| 🥇   | HTP0 pur                 | 11,26  | référence  | 0,90   |
| 2    | HTP0,GPUOpenCL 80/20     | 8,35   | −26 %      | 0,90   |
| 3    | HTP0,GPUOpenCL 50/50     | 6,11   | −46 %      | 0,83   |
| 4    | HTP0,GPUOpenCL 20/80     | 5,26   | −53 %      | 0,85   |
| 5    | GPUOpenCL seul           | 4,92   | −56 %      | 0,85   |
| 6    | GPUOpenCL,HTP0 50/50     | 5,28   | −53 %      | 0,72   |
| 7    | GPUOpenCL,HTP0 80/20     | 4,46   | −60 %      | 0,85   |
| 8    | GPUOpenCL,HTP0 20/80     | 4,17   | −63 %      | 0,68   |

Enseignements : toute fraction GPU dégrade le Qwen dense (GPU 2,3× plus
lent que HTP sur ce modèle) ; l'ordre -dev compte (GPU premier pire au
même ratio) ; acceptance MTP saine partout → la dégradation est un effet
de chemin d'exécution, pas une perte spéculative.

======================================================================
4. CAMPAGNE RATIOS NPU×GPU — MARCO-NANO MoE (RENVERSEMENT !)
======================================================================

Script : campaign_ratios_npu_gpu_moe.sh (seed 20260903) +
         bench_moe_placement_ab.sh (A/B/A/B n=200)
Modèle  : Marco-Nano-Instruct 8B-A0,6B (256 experts top-8, qwen3moe),
          Q4_0 4,57 Go — /data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf
          (re-quantisé par notre llama-quantize depuis mradermacher Q8_0 ;
          sources : D:\models_marco\Marco-Nano-Instruct.Q8_0.gguf 8,53 Go
          + Marco-Nano-Instruct.Q4_0.gguf 4,36 GiB)
Source  : results/camp_ratios_moe/synthese.txt

| Rang | Config (-dev / -ts)      | t/s    | vs HTP pur |
|------|--------------------------|--------|------------|
| 🥇   | GPUOpenCL,HTP0 80/20     | 39,11  | +28 %      |
| 2    | GPUOpenCL,HTP0 50/50     | 37,46  | +22 %      |
| 3    | HTP0 pur                 | 30,64  | référence  |
| 4    | GPUOpenCL,HTP0 20/80     | 29,89  | −2 %       |
| 5    | GPUOpenCL seul           | 22,96  | −25 %      |
| 6    | HTP0,GPUOpenCL 20/80     | 22,50  | −27 %      |
| 7    | HTP0,GPUOpenCL 50/50     | 22,51  | −27 %      |
| 8    | HTP0,GPUOpenCL 80/20     | 22,59  | −26 %      |

**A/B/A/B confirmé (n=200)** : A (HTP pur) 30,26/29,61 → **29,9 t/s** ;
B (GPU→HTP 80/20) 39,18/45,00 → **42,1 t/s = +40 %**. B2 a démarré à
45 °C (le plus chaud) et fut le plus rapide → PAS un artefact thermique.

**Explication mécanistique** (logs) : OpenCL reçoit des mégablocs de
1416 nœuds (attention + SOFT_MAX + ARGSORT + MUL_MAT_ID fusionnés) ;
HTP0 ne reçoit que des micro-splits de 58 nœuds (coût fixe par-op payé
des milliers de fois). Le MoE sparse a un compute si faible que
l'orchestration domine → le mega-kernel Adreno gagne. C'est l'INVERSE du
Qwen dense (HTP 11,26 > tout mélange GPU).

======================================================================
5. ARGSORT TOP-K — MESURE A/B (HTP vs CPU)
======================================================================

Script : bench_argsort_ab.sh (A/B/A/B n=200, Marco-Nano Q4_0, HTP0)
Source  : results/argsort_ab/synthese.txt

| Run | ARGSORT sur | t/s   | Sortie |
|-----|-------------|-------|--------|
| A1  | HTP0        | 29,54 | identique A2 |
| A2  | HTP0        | 27,96 | (moy A 28,75) |
| B1  | CPU (OPFILTER='ARGSORT') | 31,08 | identique B2 |
| B2  | CPU                      | 35,61 | (moy B 33,35) |

→ **+16 % wall en déplaçant le tri sur CPU**, reproductible sur 2 paires
adjacentes. Cause : le graph MoE trie les 256 experts complets
(`ggml_argsort_top_k` ggml.c:5376) pour n'en garder que 8 (96,9 % jeté) ;
le tri bitonic HVX coûte 215 µs/op. ⚠️ La sortie DIFFÈRE entre backends
(départage des égalités ≠, déterministe par backend) → tout patch doit
implémenter `GGML_OP_TOP_K` natif HTP aligné CPU (op native top-k existe
ggml.c:5403 mais PAS côté hexagon).

**Sur le Qwen dense : gain = 0** — 0 ARGSORT / 0 MUL_MAT_ID / 0 TOP_K
dans ses logs (dense Mamba-2, pas de routing d'experts).

======================================================================
6. PROFILAGE MIXTE MoE — COÛT FIXE PAR-OP HTP
======================================================================

Run mixte GPU→HTP 80/20 profilé (GGML_HEXAGON_PROFILE=2, 5 810 ops HTP) :
| Famille    | Mixte GPU80/HTP20 | HTP pur | Δ |
|------------|-------------------|---------|---|
| ARGSORT    | 214 µs/op         | 215 µs/op | −0,6 % (identique) |
| MUL_MAT_ID | 48 µs/op          | 51 µs/op  | −5 % |
| MUL_MAT    | 28,7 µs/op        | 29,5 µs/op | −3 % |
| Volume HTP | 2 516 µs/token    | 17 751 µs/token | −86 % |

→ Le coût par-op HTP est un FIXE structurel (round-trip FastRPC/setup),
indépendant du contexte. Le gain du mixte = volume déplacé vers mégablocs
OpenCL, pas un GPU « plus rapide ». Limite : côté OpenCL non mesuré
(GGML_OPENCL_PROFILING non compilé dans le binaire — rebuild requis).

======================================================================
7. ÉTAT GIT DU FORK JZ (source du runtime)
======================================================================

Fork   : `D:\jz_work snapdragon\ggml-hexagon-fork`
Branche: exp-pr28202-0983d01 (worktree EN COURS de merge PR #28202 —
         ⚠ 2 fichiers en conflit UU : ggml-hexagon.cpp, matmul-ops.c —
         le runtime device N'EST PAS issu de cet état de merge)
HEAD   : 9ef4543daf26e5123dd3676fccb230c782b3ab77
         "hex-mm: correct overhead sizing to make sure we dont exceed
          vtcm budget for large dims" (Max Krasnyansky, 2026-08-29)
Dirty  : M scripts/ui-assets.cmake · M src/llama-mmap.cpp
         (fix madvise __ANDROID__ — bug portabilité glibc) · M tools/ui/CMakeLists.txt

Le runtime device qui a produit les chiffres = build-android construit
sur la ligne 505354ed → 5291e12a → 5618c305 (gallocr) → 9ef4543d
(avant merge #28202). Le binaire embarque le path
`D:/jz_work/ggml-hexagon-fork` + NDK clang 18.0.3 (r27c, build 12470979).

======================================================================
8. MANIFESTE DES MODÈLES (device + hôte)
======================================================================

| Fichier device /data/local/tmp/ | Taille octets | Modèle | Usage |
|----------------------------------|---------------|--------|-------|
| Qwen3.5-9B-D2-A-MTP.gguf         | 7 838 191 232 | 9B Q4_0 attention Q8 | référence historique |
| Qwen3.5-9B-D2-A-MTP-attnQ4.gguf  | 5 450 272 384 | attnQ4 | **config 16 t/s** |
| Qwen3.5-9B-D2-A-MTP-attnMXFP4.gguf | 5 407 805 056 | attnMXFP4 | campagne quant |
| Marco-Nano-Instruct.Q4_0.gguf    | 4 569 976 352 | MoE 8B-A0,6B | campagnes MoE |
| Qwen3-8B-Q4_K_M.gguf             | 5 027 783 488 | réf 8B | comparaison |

Hôte : `D:\models_marco\` = Marco-Nano Q8_0 (8 527 233 568 o) + Q4_0
(4 356 MiB) — sources re-quantization (mradermacher / HF).

SHA-256 runtime : voir `sha256_runtime.txt` (llama-server, libggml*,
libllama*, libggml-htp-v81.so). SHA-256 des GGUF 5 Go : non calculé ici
(cohérents côté device — tailles/dates vérifiées, cf. ls ci-dessus).

======================================================================
9. RAPPORTS DÉTAILLÉS (copiés dans reports/)
======================================================================

- RAPPORT_CONFIG_16TPS_GELÉE_CROISEMENT_20260902.md — la config et le croisement
- RAPPORT_PROTOCOLE_GARDE_VALIDE_20260902.md — protocole kill/port/PID validé
- RAPPORT_16TPS_SOUTENU_100_300_TOKENS_20260902.md — 3×300 = 11,01 ± 0,16
- RAPPORT_CAMPAGNE_RATIOS_NPU_GPU_20260902.md — Qwen dense 8 configs
- RAPPORT_CONTROLE_MOE_MARCO_HTP_20260902.md — 26,72 t/s MoE + pipeline
- RAPPORT_MOE_PLACEMENT_REVERSEMENT_20260902.md — GPU bat HTP sur MoE (+40 %)
- RAPPORT_ARGSORT_TOPK_REPRODUCTIBLE_20260902.md — top-k 256→8, A/B +16 % CPU
- RAPPORT_PROFIL_MIXTE_MOE_GPU_HTP_20260902.md — coût fixe par-op 215 µs
- RAPPORT_MOE_NATIF_MTP_INTROUVABLE_20260902.md — impasse MoE≤8B+MTP

======================================================================
10. SYNTHÈSE DES RÉSULTATS CLÉS (02/09/2026)
======================================================================

| # | Fait | Chiffre | Statut |
|---|------|---------|--------|
| 1 | Config 16 t/s wall réel (3×300) | 11,01 ± 0,16 t/s, accept 0,83-0,87 | MEASURED consolidé |
| 2 | « 16,4-18,9 effectifs » | wall × mean_len = artefact de formule | REJETÉ comme métrique wall |
| 3 | Qwen dense : HTP pur imbattable | 11,26 vs GPU 4,92 (−56 %) | MEASURED 8 configs |
| 4 | MoE : GPU→HTP 80/20 bat HTP | 42,1 vs 29,9 (+40 %) | MEASURED A/B/A/B |
| 5 | ARGSORT HTP→CPU | +16 % (33,35 vs 28,75) | MEASURED A/B/A/B |
| 6 | Coût fixe par-op HTP | ~215 µs ARGSORT identique pur/mixte | MEASURED profil |
| 7 | MoE ≤8B + MTP natif public | inexistant (≥35B) | ÉTABLI (impasse) |
| 8 | Qwen dense : pas d'ARGSORT | 0 hit logs → gain TOP_K = 0 | ÉTABLI |

**Hypothèse centrale consolidée** : le plafond decode n'est PAS le
silicium (compute actif ÷7-15 → wall ÷2,4 seulement) mais la chaîne
par-étape : orchestration FastRPC/DMA/host + coût fixe par-op + découpage
du graph (micro-splits HTP vs mégablocs). Mécanisme réutilisable :
mega-kernel fusionné > op-par-op quand le compute actif est faible.

======================================================================
11. POUR REPRODUIRE (procédure minimale)
======================================================================

1. Copier runtime_device/ → /data/local/tmp/npu/ sur le device (mêmes
   permissions : chmod 755 llama-server, .so 644) + skel libggml-htp-v81.so.
2. Pousser le GGUF attnQ4 → /data/local/tmp/ (cf. manifeste §8).
3. Pousser scripts/device/*.sh → /data/local/tmp/ + npu/.
4. Attendre < 45 °C (thermal_zone21), 0 process llama, port libre.
5. `sh /data/local/tmp/npu/run_16tps_config.sh 300 q4m1_300t`
6. Vérifier meta.txt : eval time / tokens → wall t/s ; draft acceptance ;
   T_start/T_end. Répéter ×3 avec cooldown.
7. Pour les campagnes : campaign_ratios_npu_gpu.sh / _moe.sh /
   bench_argsort_ab.sh (adaptés MoE : MODEL=Marco-Nano...Q4_0.gguf, pas
   de --spec-type).

Écarts acceptables : ±0,3 t/s en fenêtre thermique identique ; ±15 %
entre chaud/froid — TOUJOURS rapporter T_start/T_end avec chaque chiffre.

======================================================================
12. LIMITES HONNÊTES
======================================================================

- Côté OpenCL non profilé (GGML_OPENCL_PROFILING absent du binaire).
- Le 16,4-18,9 « effectifs » n'est pas un débit wall.
- Un seul device ; firmware Android 16 non gelé (reboot OOM possible
  pendant campagnes → runs marqués INVALID dans les rapports).
- La sortie MoE diffère entre backends (départage top-k) — A/B de perf
  seulement sur sorties identiques par backend.
- Les GGUF 5 Go ne sont pas copiés dans l'archive (manifeste + chemins
  source suffisent ; copie possible sur demande).
