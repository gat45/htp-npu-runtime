# TUTO PAS-À-PAS — REPRODUIRE LE RUNTIME HTP GELÉ
# (du dossier d'archive au téléphone, en conditions réelles)

Date : 2026-09-02 · Durée estimée : 25-40 min (dont ~10 min de push modèle)

Prérequis :
  - Windows avec adb (chemin utilisé ici : C:\Users\videl\Desktop\geniex_harness\tools\platform-tools\adb.exe)
  - Téléphone OnePlus 15 / SM8850 rooté Magisk, USB debugging actif
  - Ce dossier : D:\archive_16tps_20260902
  - Les commandes bash ci-dessous utilisent $ADB ; sous Windows :
        ADB="C:/Users/videl/Desktop/geniex_harness/tools/platform-tools/adb.exe"
    (ou l'équivalent sur ta machine)

================================================================================
ÉTAPE 0 — VÉRIFIER LE DEVICE
================================================================================
  "$ADB" devices
  "$ADB" shell "su -c 'id'"        → doit répondre uid=0(root) (Magisk OK)
  "$ADB" shell "cat /sys/class/thermal/thermal_zone21/temp"
                                   → viser ≤ 45 000 (45°C) avant les runs
  "$ADB" shell "ps -A | grep llama" → aucun processus llama-server résiduel

================================================================================
ÉTAPE 1 — DÉPLOYER LE RUNTIME GELÉ SUR LE DEVICE (une seule fois)
================================================================================
  # Créer le répertoire runtime (convention : /data/local/tmp/npu)
  "$ADB" shell "mkdir -p /data/local/tmp/npu && chmod 777 /data/local/tmp/npu"

  # Pousser TOUT le contenu de "runtime_device 16ts\" (binaires + .so + skel)
  cd "D:\archive_16tps_20260902\runtime_device 16ts"
  "$ADB" push llama-server libggml-base.so libggml-cpu.so libggml-hexagon.so \
      libggml-opencl.so libggml.so libllama-common.so libllama-server-impl.so \
      libllama.so libOpenCL.so libcdsprpc.so libmtmd.so libomp.so \
      vendor.qti.hardware.dsp-V1-ndk.so vendor.qti.hardware.dsp@1.0.so \
      ggml-hexagon.cfg /data/local/tmp/npu/

  # Skel HTP v81 (CRITIQUE : 734 920 octets exactement — le skel rebuildé)
  "$ADB" shell "mkdir -p /data/local/tmp/npu/htp"
  "$ADB" push htp\libggml-htp-v81.so /data/local/tmp/npu/htp/

  # Droits d'exécution
  "$ADB" shell "chmod 755 /data/local/tmp/npu/llama-server /data/local/tmp/npu/*.so /data/local/tmp/npu/htp/*.so"

  # Vérification taille du skel (sinon HTP0 refusera d'ouvrir)
  "$ADB" shell "ls -la /data/local/tmp/npu/htp/libggml-htp-v81.so"
                                    # → 734920 octets

================================================================================
ÉTAPE 2 — POUSSER LE MODÈLE (config 16 t/s)
================================================================================
  # Qwen attnQ4 (5,45 Go) — celui qui produit 11.26 t/s MTP1
  "$ADB" push "D:\archive_16tps_20260902\models\Qwen3.5-9B-D2-A-MTP-attnQ4.gguf" \
      /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf

  # (Optionnel — contrôle MoE)
  "$ADB" push "D:\archive_16tps_20260902\models\Marco-Nano-Instruct.Q4_0.gguf" \
      /data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf

  # Vérifier la RAM libre (le Qwen 9B monte ~13 Go de RAM en charge)
  "$ADB" shell "cat /proc/meminfo | grep MemAvailable"
                                    # → viser ≥ 9-10 Go libres avant de lancer

================================================================================
ÉTAPE 3 — LANCER UN RUN GARDÉ (test rapide 16 tokens)
================================================================================
  # Copier le script protocole sur le device
  "$ADB" push "D:\archive_16tps_20260902\scripts\run_guarded_bench.sh" /data/local/tmp/

  # Run de référence 16 tokens (MTP n_max=1 — config « 16 t/s »)
  "$ADB" shell "sh /data/local/tmp/run_guarded_bench.sh ref16 8541 16 \
      'The capital of France is' --spec-type draft-mtp --spec-draft-n-max 1"

  # Attendu (dans le stdout) :
  #   RESULT ref16 tps=~10.3 accept=0.75 mean_len=1.75 T=xx->xxC
  # ⚠ Le tps du serveur est le débit WALL. Ne pas multiplier par mean_len.

  # Résultats sauvegardés :
  #   /data/local/tmp/bench_out/ref16/{server.log,resp.json,meta.txt}
  "$ADB" shell "cat /data/local/tmp/bench_out/ref16/meta.txt"

================================================================================
ÉTAPE 4 — MESURE SOUTENUE (3×300 tokens, config gelée)
================================================================================
  "$ADB" push "D:\archive_16tps_20260902\scripts\campaign_3x300.sh" /data/local/tmp/
  "$ADB" shell "sh /data/local/tmp/campaign_3x300.sh"
  # → 3 runs de 300 tokens, cooldown 25 s + attente T≤45°C entre runs (~10 min)
  # Résultat de référence : 11.01 ± 0.16 t/s wall (accept ~0.90)

  # Variante rapide : 1 run de 300 via le protocole gardé
  "$ADB" shell "sh /data/local/tmp/run_guarded_bench.sh qwen300 8542 300 \
      'The capital of France is' --spec-type draft-mtp --spec-draft-n-max 1"

================================================================================
ÉTAPE 5 — TEST SANS MTP (baseline) + AUTRES PLACEMENTS
================================================================================
  # Baseline dense sans spéculation :
  "$ADB" shell "sh /data/local/tmp/run_guarded_bench.sh base 8543 100 'The capital of France is'"

  # Comparer les placements (HTP0 pur est le champion du dense) :
  #   -dev HTP0            → attendu ~11.26 t/s (MTP1)
  #   -dev GPUOpenCL       → attendu ~4.9 t/s
  #   -dev HTP0,GPUOpenCL  (ts 0.8,0.2) → attendu ~8.35 t/s
  # Pour les ratios : ajouter GGML_HEXAGON_NDEV / tensor split via
  #   GGML_HEXAGON_TENSOR_SPLIT (cf. scripts/campaign_ratios_npu_gpu.sh)

================================================================================
ÉTAPE 6 — CONTRÔLE MoE (Marco-Nano, même runtime)
================================================================================
  # Pas de MTP sur Marco (pas de tête) — tester placement pur :
  "$ADB" shell "sh /data/local/tmp/run_guarded_bench.sh marco_htp 8550 100 \
      'The capital of France is'"        # avec MODEL=/data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf
  #   → attendu ~27-31 t/s (HTP0)

  # Le GPU gagne sur le MoE :
  #   -dev GPUOpenCL,HTP0 avec split 0.8/0.2 → attendu ~39-42 t/s
  # Script complet : scripts/bench_moe_placement_ab.sh (A/B alterné)
  # Script A/B ARGSORT : scripts/bench_argsort_ab.sh
  #   → B (GGML_HEXAGON_OPFILTER=ARGSORT) attendu +16 % vs A

================================================================================
ÉTAPE 7 — TEST APK (conditions réelles, sans PC une fois installé)
================================================================================
  a) Installer l'APK (213 Mo, runtime EMBARQUÉ dans les assets) :
     "$ADB" install -r "C:\Users\videl\Desktop\geniex_harness\android\marco_moe_htp_test\app\build\outputs\apk\debug\app-debug.apk"

  b) ⚠ PERMISSION MAGISK (BUG CONNU, À FAIRE UNE FOIS PAR DEVICE) :
     L'app a un UID avec policy DENY par défaut après install → ses su échouent
     silencieusement → « runtime absent » alors que le runtime existe.
     Correctif :
     "$ADB" shell "su -c '/data/adb/magisk/magisk --sqlite \"UPDATE policies SET policy=2 WHERE uid=10375\"'"
     "$ADB" shell "su -c 'kill \$(pidof magiskd)'"     # reload (se respawn)
     (uid 10375 = com.geniex.moehtp — vérifier avec :
       "$ADB" shell "dumpsys package com.geniex.moehtp | grep userId")

  c) Pousser le modèle Marco (l'APK le cherche à cet emplacement) :
     "$ADB" push "D:\archive_16tps_20260902\models\Marco-Nano-Instruct.Q4_0.gguf" \
         /data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf

  d) Ouvrir « MoE HTP Test » sur le téléphone :
       · 1re fois : bouton « ⬇ DÉPLOYER RUNTIME » (extrait les assets vers
         /data/local/tmp/moe_npu via su)
       · « ▶ HTP0 » → ~30-60 s → « tokens_predicted=100 · ~28-30 t/s » + sortie
       · « ▶ GPU »  → ~60-90 s (compile kernels OpenCL) → ~21 t/s + sortie
       · n_predict et prompt éditables ; serveur tué automatiquement après run.

================================================================================
ÉTAPE 8 — CRITÈRES DE VALIDATION (reproduction = OK si…)
================================================================================
  [ ] llama-server répond sur /health avec "status":"ok"
  [ ] ref16 : tps ≈ 10.3 ± 0.5 · acceptance ≈ 0.75 · mean_len ≈ 1.75
  [ ] 3×300 : moyenne ≈ 11.0 ± 0.3 t/s (jamais 16 — le 16 est un artefact)
  [ ] Sortie du modèle = « Paris. ... » (texte cohérent, pas de boucle/garble)
  [ ] Marco HTP0 : 26-31 t/s · Marco GPU→HTP 80/20 : 39-42 t/s
  [ ] 0 processus llama-server résiduels après chaque run
  [ ] T_end ≤ ~70°C (au-delà = throttling → résultats invalides à comparer)
  [ ] sha256 des binaires = sha256_runtime.txt (si doute d'intégrité)

================================================================================
DÉPANNAGE
================================================================================
  Symptôme                           Cause / action
  --------------------------------   ----------------------------------------
  « device HTP0 did not report       Lancement via su (contexte root) → lancer
    memory »                          en user shell (adb shell simple)
  0x80000406 au load                 Mauvais skel (juin 410 408 o) → vérifier
                                      libggml-htp-v81.so = 734 920 o
  Serveur mort au chargement          RAM insuffisante (Qwen ~13 Go) → libérer
                                      MemAvailable ≥ 9-10 Go
  APK « runtime absent » alors        Policy Magisk DENY → ÉTAPE 7b
    que le runtime existe
  Port occupé / vieux serveur         ps -A | grep llama → pkill -f llama-server
  t/s qui chutent en fin de sweep     Thermique → cooldown T≤45°C entre runs
  Sortie différente entre 2 runs      Normal (sampling) ; mettre temperature=0
                                      et seed fixe pour comparer
