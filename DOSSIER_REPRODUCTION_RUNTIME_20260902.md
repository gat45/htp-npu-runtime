# DOSSIER DE REPRODUCTION — RUNTIME HTP GELÉ 2026-09-02
# OnePlus 15 · SM8850 · HTP v81 · llama.cpp/ggml-hexagon (fork JZ)

Date : 2026-09-02
Statut : VALIDÉ sur Qwen3.5-9B-D2-A-MTP (dense) ET Marco-Nano MoE (contrôle)
Auteur : campagne expérimentale geniex_harness

================================================================================
0. CE QUE CE DOSSIER CONTIENT
================================================================================

Ce dossier permet de REPRODUIRE à l'identique :
  A. le runtime HTP gelé (binaires + .so + skel + config) qui a produit
     les campagnes du 2026-09-02 ;
  B. la config « 16 t/s » (attnQ4 + MTP n_max=1 + HTP0 + --fit off) ;
  C. les tests de contrôle MoE (Marco-Nano) et le test APK en conditions réelles.

Résultats consolidés (mesurés, pas reconstruits de mémoire) :

  Qwen dense attnQ4 + MTP1, HTP0 :    11.26 t/s  (n_predict=100, 1 run)
                                       11.01 ± 0.16 t/s (3×300 consolidé)
  Qwen dense, GPU→HTP 80/20 :          8.35 t/s  (HTP0 reste le meilleur)
  Marco-Nano MoE, HTP0 pur :          26.7 → 30.6 t/s
  Marco-Nano MoE, GPU→HTP 80/20 :     39.1 → 42.1 t/s  (le GPU gagne sur MoE)
  ARGSORT forcé CPU (Marco, A/B) :    +16 % (33.35 vs 28.75 t/s)
  APK (conditions réelles) HTP0 :     28.2-29.8 t/s · GPU : 21.1-21.5 t/s

  ⚠ LE « 16,6 t/s » HISTORIQUE = ARTEFACT DE FORMULE
  (verification 6.48 t/s × mean_len 2.50 ou wall × mean_len 1.75) —
  le wall-clock réel soutenu de la config est ~10.3-11.3 t/s.

================================================================================
1. MATÉRIEL / LOGICIEL (inventaire)
================================================================================

Hardware :
  - OnePlus 15, Snapdragon 8 Elite Gen 5 (SM8850)
  - Hexagon HTP v81 · cDSP · Adreno GPU OpenCL · Android 16
  - Root : Magisk 30.7 (denylist actif, zygisk off)

Runtime gelé (fork JZ, branche exp-pr28202-0983d01) :
  - Commit HEAD  : 9ef4543d  (hex-mm: overhead VTCM ; dernier commit appliqué)
  - Ancêtres clés (ordre chronologique) :
      859926e7  pass 4.5 topological reorder
      1248f04f  rebuild skel (fix standalone ADD hang)
      505354ed  qwen35: fix GDN state crash (ggml_cont_4d)
      5291e12a  MUL_MAT row limit configurable (lm-head offload)
      5618c305  gallocr reserve/compute mismatch detection (+ test pass45)
      9ef4543d  overhead sizing VTCM (extrait PR #28202 : 0983d01)
  - Version ggml-hexagon : 0.99.7.7 (ggml-hexagon.cfg)
  - skel HTP : libggml-htp-v81.so = 734 920 octets (skel REBUILDÉ — celui qui
    ouvre HTP0 en user shell, contrairement au skel juin 410 408 o qui ne
    marchait pas / 0x80000406 sous su).

Modèles :
  - Qwen3.5-9B-D2-A-MTP-attnQ4.gguf   5 450 272 384 o  (5,08 GiB)  config 16 t/s
  - Qwen3.5-9B-D2-A-MTP-attnMXFP4.gguf 5 407 805 056 o  campagne quant
  - Qwen3.5-9B-D2-A-MTP.gguf          7 838 191 232 o  référence historique
  - Marco-Nano-Instruct.Q4_0.gguf     4 569 976 352 o  contrôle MoE (qwen3moe)
  - Qwen3-8B-Q4_K_M.gguf              5 027 783 488 o  autre dense

================================================================================
2. ARBORESCENCE DU DOSSIER (D:\archive_16tps_20260902)
================================================================================

D:\archive_16tps_20260902\
│
├── RAPPORT_ARCHIVE_RUNTIME_16TPS_20260902.md   ← rapport maître 12 sections
├── sha256_runtime.txt                          ← SHA-256 de chaque binaire/.so
├── git_state_jz_fork.txt                       ← état exact du fork (HEAD,
│                                                 branche, log -12)
│
├── runtime_device 16ts\                        ← COPIE GELÉE DU RUNTIME
│   │                                            (ce qui tourne sur le device)
│   ├── llama-server                            ← binaire Android (7 424 o,
│   │                                            launcher → libllama-server-impl.so)
│   ├── ggml-hexagon.cfg                        ← config backend (0.99.7.7,
│   │                                            thread_counts=6, opfusion,
│   │                                            dsp_cache_mode=5, fa_select=2)
│   ├── libOpenCL.so · libcdsprpc.so · libomp.so
│   ├── libggml-base.so · libggml-cpu.so · libggml-hexagon.so
│   ├── libggml-opencl.so · libggml.so
│   ├── libllama-common.so · libllama-server-impl.so · libllama.so
│   ├── libmtmd.so
│   ├── vendor.qti.hardware.dsp-V1-ndk.so
│   ├── vendor.qti.hardware.dsp@1.0.so
│   ├── htp\
│   │   ├── libggml-htp-v81.so                  ← skel REBUILDÉ 734 920 o (HTP0)
│   │   ├── libggml-htp-v81.so.dspqueue-works   ← variante dspqueue testée
│   │   ├── libggml-htp-v68/69/73/75/79.so      ← skels autres archis (réf.)
│   │   └── lib_june_20260602\                  ← ancien skel juin (410 408 o,
│   │       libggml-htp-v81.so / libllama.so /     celui qui ne marchait pas)
│   │       libggml-hexagon.so
│   └── bin\ lib\                                ← (structure interne du runtime)
│
├── scripts\                                     ← protocole + campagnes (HÔTE PC)
│   ├── run_guarded_bench.sh                    ← protocole GARDÉ (référence)
│   ├── campaign_3x300.sh                       ← 3×300 tokens config gelée
│   ├── campaign_ratios_npu_gpu.sh              ← ratios Qwen (8 configs)
│   ├── campaign_ratios_npu_gpu_moe.sh          ← ratios Marco (8 configs)
│   ├── bench_argsort_ab.sh                     ← A/B ARGSORT HTP vs CPU
│   ├── bench_moe_placement_ab.sh               ← A/B HTP pur vs GPU→HTP
│   ├── device\                                 ← ~320 scripts device bruts
│   │   ├── aa_launch.sh · act*.sh · bench*.sh · axe*.sh · balance_npu_gpu.sh
│   │   ├── run_guarded_bench.sh (copie device)
│   │   └── ... (scripts shell exécutés sur le téléphone)
│   └── devices\                                ← helpers
│
├── results\                                     ← RÉSULTATS BRUTS (méta par run)
│   ├── bench_out_16tps\
│   │   ├── 16tps_r1\meta.txt · 16tps_r2\meta.txt · 16tps_r3\meta.txt
│   │   ├── q4m1_ref16\meta.txt                 ← run 16 tokens (accept 0.75)
│   │   └── q4m1_100t\meta.txt
│   ├── camp_ratios_qwen\synthese.txt           ← 8 configs placement (Qwen)
│   ├── camp_ratios_moe\synthese.txt            ← 8 configs placement (Marco)
│   └── argsort_ab\synthese.txt                 ← A/B/A/B ARGSORT (4 runs 200)
│
├── reports\                                     ← 9 rapports détaillés
│   ├── RAPPORT_PROTOCOLE_GARDE_VALIDE_20260902.md
│   ├── RAPPORT_CONFIG_16TPS_GELÉE_CROISEMENT_20260902.md
│   ├── RAPPORT_16TPS_SOUTENU_100_300_TOKENS_20260902.md
│   ├── RAPPORT_CAMPAGNE_RATIOS_NPU_GPU_20260902.md
│   ├── RAPPORT_CONTROLE_MOE_MARCO_HTP_20260902.md
│   ├── RAPPORT_MOE_PLACEMENT_REVERSEMENT_20260902.md
│   ├── RAPPORT_PROFIL_MIXTE_MOE_GPU_HTP_20260902.md
│   ├── RAPPORT_ARGSORT_TOPK_REPRODUCTIBLE_20260902.md
│   └── RAPPORT_MOE_NATIF_MTP_INTROUVABLE_20260902.md
│
└── models\
    ├── Qwen3.5-9B-D2-A-MTP-attnQ4.gguf          ← 5,45 Go (config 16 t/s)
    └── Marco-Nano-Instruct.Q4_0.gguf            ← 4,57 Go (contrôle MoE)

Autres artefacts liés (hors archive) :
  D:\profil_40tokens\                           ← logs de profiling 40 tokens
  D:\models_marco\                              ← Marco Q8_0 source + Q4_0
  D:\jz_work snapdragon\ggml-hexagon-fork\      ← SOURCE du fork (7,8 Go)
  C:\Users\videl\Desktop\geniex_harness\bench_results\  ← rapports + scripts
  C:\Users\videl\Desktop\geniex_harness\android\marco_moe_htp_test\  ← projet APK

================================================================================
3. CONFIGURATION EXACTE (env + commande)
================================================================================

Environnement (identique pour TOUS les runs) :
  LD_LIBRARY_PATH=<RUNTIME>          (ex : /data/local/tmp/npu)
  ADSP_LIBRARY_PATH=<RUNTIME>
  GGML_HEXAGON_NDEV=1
  GGML_HEXAGON_ARCH=v81
  (pas de GGML_HEXAGON_OPPOLL dans la config validée — neutre)
  ggml-hexagon.cfg : thread_counts=6 · enable_opfusion=1 ·
                     dsp_cache_mode=5 · fa_select=2 · enable_graph_optimize=1

Commande serveur EXACTE (protocole gardé, run_guarded_bench.sh) :
  nohup "$BIN" -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
      $SPEC_ARGS --host 127.0.0.1 --port "$PORT" > server.log 2>&1 &

  avec $SPEC_ARGS = --spec-type draft-mtp --spec-draft-n-max 1   (config 16 t/s)
       $SPEC_ARGS = (vide)                                        (baseline / MoE)

  BIN   = /data/local/tmp/npu/llama-server     (runtime gelé)
  MODEL = /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
  PORT  = 8520 (3×300) / 8541-8562 (campagnes)

Requête benchmark :
  curl -s -X POST http://127.0.0.1:$PORT/completion -H 'Content-Type: application/json' \
    -d '{"prompt":"The capital of France is","n_predict":<N>,"temperature":0}'

Séquence du protocole GARDÉ (chaque run) :
  KILL ALL → VERIFY NO LLAMA → VERIFY PORT FREE → START (chemin absolu)
  → VERIFY PID + HEALTH → [WARMUP 4 tokens] → BENCH → SAVE (log+resp+meta+T)
  → KILL + VERIFY CLEAN → cooldown T≤45°C entre les runs

================================================================================
4. VÉRIFICATION D'INTÉGRITÉ
================================================================================

  sha256sum -c sha256_runtime.txt        (depuis D:\archive_16tps_20260902)
  git -C "D:\jz_work snapdragon\ggml-hexagon-fork" log --oneline -12
      → doit finir par 9ef4543d, branche exp-pr28202-0983d01

  Skel critique : libggml-htp-v81.so = EXACTEMENT 734 920 octets
  (le skel juin = 410 408 o → HTP0 KO / 0x80000406 ; ne pas utiliser)

================================================================================
5. RÉSULTATS DE RÉFÉRENCE (pour comparaison après reproduction)
================================================================================

Qwen attnQ4 + MTP1 (config gelée) :
  ref16 (n_predict=16) : tps=10.32 wall · draft acceptance 0.75 (6/8) · mean_len 1.75
  3×300 (consolidé)    : 11.01 ± 0.16 t/s wall
  htp_only 100 tokens  : 11.26 t/s · accept 0.90

Placement Qwen (8 configs, n=100) : HTP0 pur 11.26 > HTP→GPU 80/20 8.35
  > GPU→HTP 8.35 zone basse 4.2-6.1 → HTP0 reste imbattable sur dense.

Placement Marco MoE (8 configs, n=100, pas de MTP) : GPU→HTP 80/20 39.1
  > gpu_htp_5050 37.5 > HTP0 30.6 > gpu_htp_2080 29.9 > GPU pur 23.0
  > HTP→GPU 22.5 → LE GPU GAGNE SUR MoE SPARSE (inversion du classement).

ARGSORT A/B (Marco, n=200) : A HTP = 29.54/27.96 → 28.75 moy
                             B CPU = 31.08/35.61 → 33.35 moy  (+16 %)
  Sortie : déterministe PAR backend (A1=A2, B1=B2) mais A≠B (départage CPU≠HTP).

================================================================================
6. RÉFÉRENCES RAPPORTS DÉTAILLÉS
================================================================================

  reports/RAPPORT_PROTOCOLE_GARDE_VALIDE_20260902.md
      → pourquoi les anciens chiffres (10,27 ngram) étaient contaminés (kill
        du mauvais process, port, serveur orphelin) et le protocole qui fixe ça
  reports/RAPPORT_CONFIG_16TPS_GELÉE_CROISEMENT_20260902.md
      → config gelée + croisement avec tous les résultats
  reports/RAPPORT_16TPS_SOUTENU_100_300_TOKENS_20260902.md
      → 3×300 tokens : 11.01 ± 0.16 → le « 16 » est un artefact de formule
  reports/RAPPORT_CAMPAGNE_RATIOS_NPU_GPU_20260902.md → 8 configs Qwen
  reports/RAPPORT_CONTROLE_MOE_MARCO_HTP_20260902.md → MoE 26.7 t/s HTP0
  reports/RAPPORT_MOE_PLACEMENT_REVERSEMENT_20260902.md → GPU +40 % sur MoE
  reports/RAPPORT_PROFIL_MIXTE_MOE_GPU_HTP_20260902.md → fixe par-op 215 µs
  reports/RAPPORT_ARGSORT_TOPK_REPRODUCTIBLE_20260902.md → +16 % CPU, sortie≠
  reports/RAPPORT_MOE_NATIF_MTP_INTROUVABLE_20260902.md → impasse MoE≤8B+MTP

================================================================================
7. LIMITES HONNÊTES
================================================================================

  - Les runs n'étaient PAS thermiquement contrôlés à ±0.5°C : variance inter-
    runs de plusieurs % possible ; toujours comparer moyennes ± écart-type sur
    3 runs, jamais le meilleur run.
  - « 16,6 t/s effective » = artefact (wall × mean_len). Ne jamais publier ce
    chiffre comme débit soutenu ; le débit wall réel = 10.3-11.3 t/s (Qwen) et
    26-30 t/s (Marco HTP0).
  - Le runtime tourne en user shell (adb shell, SANS su) : lancer via su
    (contexte root) = crash HTP0 (0x80000406 / mémoire CDSP non rapportée).
    Exception : l'APK lance via su avec setsid (validé 2026-09-02, HTP0 28-30).
  - Le modèle D2-A est hybride Mamba-2 (pas MoE) : pas d'ARGSORT/MUL_MAT_ID
    dans son graphe → le levier TOP_K ne s'applique QU'AUX MoE.
