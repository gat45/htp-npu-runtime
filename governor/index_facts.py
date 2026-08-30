"""Indexe les faits bench GPU/NPU dans RAG (provenance) + graph (causal).

Sources : RAPPORT_SESSION_D2_20260824.md, ADDENDUM, RUNTIMES_COMPARATIF_20260826.md
+ mesures v6 (2×2 serveur) — paires appariées, MD5 host/skel verrouillés.

Conflits réconciliés (2026-08-26) :
- output.weight=CPU est CONTEXTE-dépendant : +27,2 % (llama-bench) vs −30 %
  (llama-server, REJECTED) → scindé en 2 faits.
- CPU pur 9,5 t/s = outlier/config différente, contredit AXE-1a (~6,2,
  DVFS verrouillé 1,997 GHz) → requalifié en quarantaine.
- synergy(output_weight, mtp) mesurée : I≈0, combo 6,47 < mtp seul 8,26 →
  enregistrée dans le graphe (ne pas combiner).

Usage : py -m governor.index_facts [--dry-run]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from governor.causal import CausalMemory
from governor.provenance import ProvenanceMemory

SRC = "bench:RAPPORT_SESSION_D2_20260824+ADDENDUM+RUNTIMES_COMPARATIF_20260826"

# (key, value, confidence, reproducible) — 9B Q4_0, -ngl99 -p512 -n32 -r1.
FACTS = [
    ("bench:gpu_seul_tg", {"tg32": 6.03, "pp512": 110.99,
                           "config": "-ngl99 -p512 -n32 -r1 -dev GPUOpenCL"},
     0.9, True),
    ("bench:htp_seul_tg", {"tg32": 5.95, "pp512": 355.16,
                           "config": "-ngl99 -p512 -n32 -r1 -dev HTP0"},
     0.9, True),
    ("bench:gpu70_htp30_tg", {"tg32": 5.96, "pp512": 352.17}, 0.9, True),
    ("bench:gpu50_htp50_tg", {"tg32": 6.44, "pp512": 349.73}, 0.9, True),
    ("bench:gpu30_htp70_tg", {"tg32": 6.41, "pp512": 341.37}, 0.9, True),
    ("bench:gpu_htp_meilleur_tg", {"config": "GPU50/HTP50", "tg32": 6.44,
                                   "delta_pct_vs_htp": +8.2}, 0.9, True),
    ("bench:cpu_full_decode_9b", {"tg32_moy": 6.2, "plage": [5.69, 6.90],
                                  "verdict": "REJECTED (pas production)",
                                  "cause": "variabilité inexpliquée par DVFS"},
     0.8, True),
    # CONFLIT 1 — output.weight scindé par contexte.
    ("bench:output_weight_cpu_htp", {"context": "llama-bench",
                                     "tg32": 7.43,
                                     "delta_pct_vs_htp_full": +27.2,
                                     "statut": "observed_replicated_n2",
                                     "note": "valide UNIQUEMENT sur "
                                             "llama-bench (op lm_head "
                                             "isolée) ; en llama-server → "
                                             "bench:output_weight_cpu_server"},
     0.7, True),
    ("bench:output_weight_cpu_server", {"context": "llama-server",
                                        "tg": 4.16, "baseline": 5.97,
                                        "delta_pct": -30.0,
                                        "verdict": "REJECTED production",
                                        "cause": "contention CPU sampling + "
                                                 "HTTP + tokenizer (v6 2×2)"},
     0.85, True),
    ("bench:mtp_htp_9b", {"tg32": 8.29, "std": 0.05,
                          "delta_pct_vs_htp": +38.2,
                          "baseline_htp": "6.00 ± 0.08",
                          "statut": "validé sur 3 paires, COHERENT"}, 0.9, True),
    ("bench:qairt_8b_w4a16", {"tg32": 15.6, "statut": "observed",
                              "normalisation": "AXE-2 en cours (×2,48 vs GGML "
                                               "non isolé format/runtime)"},
     0.7, True),
    ("bench:qwen3_8b_qairt_confirme", {"decode": 17.2, "prefill": 287,
                                       "ttft_ms": 90, "pile": "QAIRT w4a16, "
                                       "5 shards, QNN 2.45.0"}, 0.9, True),
    ("bench:mnn_llm_sm8850", {"tg": 13.85, "precision": "~q4",
                              "conclusion": "runtime > format (bat llama.cpp "
                                            "GGUF 7.26)"}, 0.85, True),
    # CONFLIT 2 — CPU pur requalifié (outlier/config, contredit AXE-1a).
    ("bench:cpu_pur_q40_ngl0", {"tg_reference": 6.2,
                                "plage": [5.69, 6.90],
                                "tg_9_5": "outlier ou config différente "
                                          "(threads/mmap) — non reproductible",
                                "reconciliation": "contredit AXE-1a (REJECTED "
                                                  "~6,2 ; DVFS verrouillé "
                                                  "1,997 GHz) — à re-mesurer"},
     0.5, True),
    ("bench:trafic_decode_par_couche", {"ffn_pct": 51.5, "attn_pct": 18.0,
                                        "lm_head_pct": 15.3, "embed_pct": 10.5,
                                        "lm_head_mb_token": 795,
                                        "trafic_token_gb": 4.53},
     0.85, True),
    ("bench:bw_effective_chemins", {"ggml": "27-32 GB/s",
                                    "qairt_w4a16": "~74 GB/s (estimé)"},
     0.6, True),
    ("rule:ordre_dev_gpu", {"rule": "-dev GPUOpenCL,HTP0 fonctionne ; "
                                   "-dev HTP0,GPUOpenCL fige (deadlock build)"},
     0.9, True),
    ("rule:appariement_abi", {"rule": "paires appariées par génération ; "
                                      "JZ↔GenieX = mismatch opbatch (PR "
                                      "#21705 non mergée), rejets CDSP 0xc"},
     0.9, True),
    ("doc:bench_gpu_npu_matrix", {"rapport": "docs_onesplus/"
                                             "RAPPORT_SESSION_D2_20260824.md",
                                  "addendum": "docs_onesplus/"
                                              "RAPPORT_SESSION_D2_L2_ADDENDUM.md"},
     1.0, True),
    # 2026-08-26 : RUNTIMES_COMPARATIF + littérature orx.
    ("bench:qairt_vs_ggml_dispatch", {"conclusion": "×2,48 ≠ bits : graphe QNN "
       "pré-compilé vs op-par-op FastRPC + packing",
       "source": "RUNTIMES_COMPARATIF_20260826",
       "mecanisme": "GGML-Hexagon envoie CHAQUE op au DSP via FastRPC "
                    "(~230 round-trips/token x ~50-100us = ~17ms overhead/token, "
                    "le goulot = dispatch pas compute) ; QNN/QAIRT compile le "
                    "graphe ENTIER en UNE seule soumission DSP, eliminant "
                    "l'overhead",
       "mecanisme_source": "github ara142/llama-cpp-hexagon-npu, "
                           "chraac/llama-cpp-qnn-builder",
       "headroom": "bundle QAIRT v79 (dsp_arch v79) tourne en COMPAT sur ce "
                   "v81 -> ratio 1.92x sous-estime le potentiel QNN natif v81"},
      0.9, True),
    ("bench:mnn_cpu_13_85", {"tg": 13.85, "chemin": "CPU ARM SIMD (pas NPU)",
      "conclusion": "vrai challenger de QAIRT = MNN, pas GGML"}, 0.85, True),
    ("bench:mtp_axe3_valide", {"acceptance": 72.7, "speedup_pct": 38.2,
      "paires": "3/3", "statut": "VALIDATED/REPRODUCED/COHERENT",
      "reco": "--spec-type draft-mtp seul ; lm_head-CPU = -30% en prod",
      "nuance": "gain nul à 32 tokens, réel sur générations longues"},
     0.9, True),
    ("lit:2607.05475", {"conclusion": "NPU = prefill compute-bound ; CPU bat "
      "tous les backends en decode memory-bound ; 40% gaspillage scheduling"},
     0.8, True),
    ("lit:2606.27550", {"conclusion": "EntMTP : profondeur de spéculation "
      "pilotée par l'entropie, +1.15× vs Hydra — candidat MTP adaptatif"},
     0.7, True),
    ("lit:2607.22785", {"conclusion": "FusionML : co-exécution CPU+GPU n'aide "
      "PAS le decode (bande partagée) — tension avec notre GPU50/HTP50 +8,2% "
      "à re-mesurer"}, 0.7, True),
    # CONFLIT 3 — synergie output.weight × MTP mesurée.
    ("bench:synergy_outputweight_x_mtp", {"I": 0.02, "independance": "≈0",
      "combo_tg": 6.47, "mtp_seul_tg": 8.26,
      "conclusion": "gains indépendants MAIS combo 6,47 < mtp seul 8,26 "
                    "(contention) — NE PAS combiner"}, 0.85, True),
    # PREUVES EXTERNES (croisées 2026-08-26) — confirment les 3 conflits.
    ("lit:extern_cpu_roundtrip_penalty", {"source": "github.com/NodeNestor/"
      "qwen3.5-27b-mtp-llamacpp REPORT.md",
      "preuve": "MTP avec checkpoint CPU (GPU→CPU→GPU) = −31% (−26% en "
                "GPU→GPU) ; checkpoint CPU ~42ms vs GPU ~20ms → confirme "
                "que placer des tensors sur CPU pendant decode HTP coute",
      "conflit": "CONFLIT 1 (output.weight=CPU contexte-dépendant)"},
     0.9, True),
    ("lit:extern_fallback_penalty_1_5x", {"source": "arXiv 2605.27435 "
      "(Leiden, Snapdragon 8 Gen 3 / Hexagon v75)",
      "preuve": "cross-backend fallback penalty 1.5× ; scheduling tax "
                "8-22× sur opérateurs légers ; NPU decode seulement 1.05-1.2× "
                "vs CPU en bout-à-bout",
      "conflit": "CONFLIT 1 + CONFLIT 2 (CPU≈NPU decode, pas 'domine')"},
     0.9, True),
    ("lit:extern_mtp_acceptance_range", {"source": "Substack "
      "johnpaulwile (MTP llama.cpp) + PR #20700 llama.cpp + petter-b",
      "preuve": "acceptance typique Qwen3.5/3.6 MTP = 70-85% (82% PR #20700, "
                "63.5% petter-b, 47.5% NodeNestor 27B hybride) → notre 72.7% "
                "est DANS la plage normale, signal sain",
      "conflit": "validité AXE-3 MTP"}, 0.9, True),
    ("lit:extern_draft_bug_alerte", {"source": "github.com/randomaibullshitgo/"
      "1bit-spec-decode",
      "preuve": "bug 'draft[0] unconditionally accepted' = texte faux qui "
                "semble correct ; acceptance peut grimper avec un bug partagé "
                "→ le contrôle de cohérence (baseline==MTP==CPU pur) est "
                "REQUIS et a PASSÉ pour notre MTP",
      "conflit": "alerte méthodologique intégrée (coherence checks)"}, 0.9, True),
    # AXE-2 — mesure DIRECTE GGML-Hexagon NPU (même famille que bundle QAIRT)
    ("bench:qwen3_8b_q4km_ggml_npu", {"model": "Qwen3-8B Q4_K_M",
      "pp_tps": 40.98, "tg_tps": 8.14, "n_prompt": 512, "n_gen": 256,
      "backend": "OpenCL,HTP", "ngl": 99, "fa": 1, "device": "HTP0 (nsp1000)",
      "cond": "AXE-2 2026-08-26 adb-wifi shell, cd /data/local/tmp/npu + "
              "LD_LIBRARY_PATH=./lib + GGML_HEXAGON_NDEV=1",
      "note": "jambe GGML du A/B QAIRT-vs-GGML sur Qwen3-8B"}, 0.95, True),
    # AXE-2 — QAIRT/QNN MESURE LIVE (geniex-bench natif, root shell).
    ("bench:qwen3_8b_w4a16_qairt_tg", {"model": "Qwen3-8B W4A16 (QAIRT bundle)",
       "tg_tps": 14.1, "tg_tps_t12": 15.6,
       "pp_tps": 1167.5, "ttft_ms": 438.6, "n_gen": 163,
       "source": "LIVE geniex-bench natif (root shell) 2026-08-26 + T12",
       "note": "MESURE LIVE 2026-08-26 (geniex-bench --plugin qairt --device "
               "npu). L'erreur 14001 etait specifique a l'invocation python "
               "ctypes (mauvais chemin plugin/libs), PAS au binaire natif.",
       "conflit": "AXE-2"}, 0.95, True),
    # AXE-2 — ratio normalise (meme famille Qwen3-8B, runtime seul)
    ("bench:axe2_ratio_qairt_sur_ggml", {"qairt_tg": 14.1, "qairt_tg_t12": 15.6,
       "ggml_tg": 8.14, "ratio_live": 1.73, "ratio_t12": 1.92,
       "meme_famille": "Qwen3-8B",
       "caveat": "QAIRT W4A16 vs GGML Q4_K_M (tous deux ~4-bit) ; QAIRT live "
                 "mesure (geniex-bench natif), bundle v79 en compat v81",
       "concl": "QNN (graphe precompile par token) ~1,7-1,9x plus rapide que "
                "GGML-Hexagon (op-dispatch + repacking par token)"},
       0.95, True),
    # AXE-2 — cross-validation analyseur statique (HardwareGovernor /governor/profile)
    ("bench:qwen3_8b_q4km_static_analysis", {"predicted_tps_bw": 6.45,
      "bottleneck": "memory-bound", "bw_eff_gbs": 32.4,
      "n_layers_analyzed": 36, "source": "HardwareGovernor app /governor/profile",
       "note": "confirme GGML live 8,14 ~ bandwidth-limited (compute overlap "
               "explique +26% vs pred 6,45) ; QAIRT non exposable en live via "
               "REST (POST qairt crash le serveur -> UI app requise)"},
       0.9, True),
    # AXE-2 — per-layer structural profile (en-tete GGUF reel, parse_gguf_layer.py).
    ("bench:axe2_layer_decompose", {"model": "Qwen3-8B Q4_K_M",
       "decode_weight_bytes_per_token_gib": 4.32,
       "est_memory_bound_ms": 143.28, "measured_ms_per_token": 122.85,
       "memory_bound_understimate_pct": 16.6,
       "hotspots_pct": {"ffn_down": 27.0, "ffn_gate": 22.0, "ffn_up": 21.3,
                        "lm_head": 11.0, "attn": 18.6},
       "ffn_share_pct": 70.3,
       "format_effect": "QAIRT W4A16 decode ~4.1 GiB vs 4.64 GiB Q4_K_M => "
                        "~13% moins de trafic (FORMAT, pas runtime)",
       "residual_runtime_gap_vs_qairt": "~1.53x (1.73/1.13) attribuable "
                        "dispatch/queue/compute/packing",
       "source": "en-tete GGUF reel (parse_gguf_layer.py) + HardwareGovernor "
                 "bw_eff 32.4 GB/s",
       "limite": "timing cycle-level queue/compute/sync requiert profiler "
                 "upstream ggml-hexagon (ce build n'emet que mode PMU)",
       "conflit": "AXE-2 per-layer structural"}, 0.9, True),
    # AXE-2 — preuve externe du mecanisme dispatch (MCP web + orx).
    ("lit:ggml_hexagon_fastrpc_dispatch_overhead", {"preuve": "GGML-Hexagon "
       "dispatch chaque op au DSP via FastRPC (~230 round-trips/token x ~50-100us "
       "= ~17ms overhead/token) ; QNN EP (QAIRT/ONNX) compile le graphe entier "
       "en UNE soumission DSP, eliminant l'overhead",
       "source": "github ara142/llama-cpp-hexagon-npu, chraac/llama-cpp-qnn-"
                 "builder",
       "conflit": "AXE-2 (mecanisme du x2-2.5)"}, 0.7, True),
    ("lit:2608.08730", {"conclusion": "dispatch overhead domine batch=1 ; "
       "reduire le NOMBRE de dispatch > qualite kernel (principe general NPU)",
       "preuve": "WebGPU per-dispatch 24-71us, fusion kernel +53%",
       "conflit": "AXE-2 (corroboration mecanisme dispatch)"}, 0.6, True),
    # AXE-2 — excavation SOURCES (governor web_research/orx + webfetch sur repos JZ).
    ("src:ggml_qnn_fastrpc_arch", {"repo": "chraac/llama-cpp-qnn-builder",
       "chemin": "ggml/src/ggml-qnn/npu/{host,device,idl} + shared/",
       "elements": {"host_device.cpp": "NPU device lifecycle",
         "graph.cpp(host)": "graph creation/caching/execution coordination",
         "buffer.cpp": "ION/RPC buffers, zero-copy",
         "device/graph.cpp": "NPU-side graph compute, 4-thread",
         "op_impl.cpp": "HVX kernels (mul_mat)",
         "quants.cpp": "HVX dequant Q4_0/Q8_0/Q4_K",
         "hexagon_npu.idl": "FastRPC contract"},
       "principe": "Graph-Level Execution (graphe entier sur NPU) + zero-copy ION "
                   "+ 4-thread pool + VTCM = exactement l'archi JZ v2 "
                   "(JZPlan / batched dispatch)",
       "fastrpc_overhead": "host_param_update 700-800us/op (comm FastRPC)",
       "conflit": "AXE-2 / JZ v2"}, 0.85, True),
    ("src:ggml_qnn_dequant_dominant", {"repo": "chraac/llama-cpp-qnn-builder",
       "preuve": "bench matmul 16384^2 sur 8gen2: Q4_0 device_dequant 86927us "
                 "(90% du device time) vs device_compute 10005us ; Q8_0 dequant "
                 "245178us (90%)",
       "concl": "pour Q4_0/Q8_0 le GOULOT NPU = dequantization (unpack+dequant), "
                "pas compute (~4x compute pur plus rapide que CPU FP32)",
       "implication": "QAIRT (graphe precompile) fuse dequant dans le graph + "
                      "evite repack par op => grosse part du ratio AXE-2 ; JZ v4 "
                      "doit fusionner unpack+dequant+GEMV (Q4 GEMV fused)",
       "conflit": "AXE-2 mecanisme"}, 0.85, True),
    ("src:hexagon_mlir", {"paper": "2602.19762 Hexagon-MLIR (Qualcomm, 2026-02)",
       "concl": "compilation stack open-source MLIR -> Hexagon NPU ; mega-kernels "
                "maximisant la localite TCM, reduisent bandwidth bottlenecks des "
                "approches par lib",
       "role": "reference compilateur HTP (JZ v>4 / IR JZ)",
       "conflit": "JZ compiler"}, 0.8, True),
    ("bench:axe2_causal_refined", {"ratio_live": 1.73,
       "decompose": "~1.13x FORMAT (W4A16 -13% trafic vs Q4_K_M) + ~1.53x RUNTIME",
       "runtime_breakdown": "per-op FastRPC host_param_update (~700-800us x N_ops) "
         "+ per-op dequant (90% device time Q4_0) ; QAIRT elimine les deux via "
         "graphe unique precompile + dequant fundu dans le graph",
       "concl": "le delta QAIRT/GGML est majoritairement dispatch-per-op + "
                "dequant-per-op, PAS compute ni bits",
       "sources": "src:ggml_qnn_fastrpc_arch + src:ggml_qnn_dequant_dominant + "
                  "bench:axe2_layer_decompose",
        "conflit": "AXE-2"}, 0.9, True),

    # AXE-2 — (a) profiler upstream : instrumentation presente dans le source JZ
    # mais binaire device filtre DEBUG -> profile-op injoignable sans rebuild.
    ("src:ggml_hexagon_profile_mechanism", {"opt_profile": "GGML_HEXAGON_PROFILE 0/1/2/3",
        "opt_opstage": "QUEUE|COMPUTE (0x1 queue, 0x2 compute, 0x3 both)",
        "opt_opbatch": 1024, "opt_opqueue": 16, "opt_opfusion": 1,
        "profile_op_line": "ggml-hexagon.cpp:167 GGML_LOG_DEBUG profile-op "
          "<OP>|names|dims|types|strides|kparams|usec N cycles N start N mhz",
        "opbatch_line": "ggml-hexagon.cpp:183 profile-op OPBATCH|...|usec N cycles N",
        "trace_evt_line": "ggml-hexagon.cpp:201 trace-evt <EVT>: thread N info N start/stop C",
        "call_site": "pop() line 1540 if(opt_profile && rsp.n_ops>0) -> dump_op_prof per op",
        "parser": "scripts/snapdragon/ggml-hexagon-profile.py (UPSTREAM) : agrege par op "
          "tot/avg/max usec + cycles + PMU ; --timeline bubbles => queue/compute idle %",
        "conflit": "AXE-2"}, 0.95, True),

    ("bench:axe2_profile_blocker", {"symptom": "PROFILE=1/2 affiche 'Profiling mode N : "
        "pmu-evt [...]' mais 0 ligne profile-op/trace-evt, meme avec -v",
        "root_cause": "instrumentation COMPILEE dans source (ggml-hexagon.cpp:167/183/201) "
          "mais binaire device filtre GGML_LOG_DEBUG : common/log.cpp:85 callback ne sort "
          "DEBUG sur stderr que si common_log_verbosity_thold>=LOG_DEFAULT_DEBUG(=5) ; "
          "defaut=INFO(3) -> DEBUG drop. -v met ggml level DEBUG mais seuil commun non leve. "
          "Binaire device (ancien) ignore -lv et LLAMA_ARG_LOG_* (error: invalid -lv).",
        "no_runtime_fix": "aucun env/flag du binaire device ne remonte le seuil -> profile-op "
          "injoignable sans rebuild",
        "patch": "changer 3 lignes GGML_LOG_DEBUG->GGML_LOG_INFO dans ggml-hexagon.cpp "
          "(167, 183, 201) => profile-op/trace-evt sortent toujours (INFO non filtre)",
        "rebuild": "cmake --preset arm64-android-snapdragon-release -B build-snapdragon ; "
          "ANDROID_NDK_ROOT=android-ndk-r29 ; HEXAGON_SDK_ROOT=Hexagon_SDK/6.6.0.0 ; "
          "cmake --build ; cmake --install ; push libggml-htp-v81.so + bin/llama-bench",
        "build_env": "cross-compile Linux/WSL requis (hexagon-clang est ELF) ; SDK+NDK "
          "present dans tools/_toolchains",
        "conflit": "AXE-2"}, 0.95, True),

    # AXE-2 (b)/JZ — backend FastRPC-based de zhouwg/ggml-hexagon (branche self-build-jz)
    # = le vrai "JZ" ; sur SM8850 (notre device) il bat le dspqueue Qualcomm.
    ("src:ggml_hexagon_jz_fastrpc", {"repo": "zhouwg/ggml-hexagon branche self-build-jz "
        "(default) ; FastRPC-based dans ggml/src/ggml-hexagon/htp/ (entry.c=FastRPC "
        "entry, dsp-ctx.h=session ctx). Meme branche contient le backend dspqueue "
        "Qualcomm (celui de NOTRE binaire device).",
        "batch_model": "AP pack hex_batch_hdr+hex_op_desc[]+hex_tensor_desc[] dans UN "
          "mempool ION ; DSP execute tout le batch via UN seul appel FastRPC "
          "(ggml_htp_execute_batch) -> supprime host_param_update per-op",
        "op_dispatch": "g_op_dispatch[] function-pointer table indexee par htp_op_code "
          "(pas de chaine de branches)",
        "cache_opts": "dsp_cache_mode bits: 0x1 first-touch weight bitmap (skip dcinva "
          "poids apres 1er acces) ; 0x2 skip dcinva prior-dst ; 0x4 bulk dst flush a "
          "batch-end (merge ranges + 1 syncht) -> supprime dcinva/syncht per-op",
        "matmul": "DSP-side HMX-first (v81) puis HVX fallback ; AP peut precompute "
          "kernel_params (kernel_type!=0) pour skip recompute DSP",
        "prof": "HEX_OP_PROF=1 -> dump_op_prof FARF [OP-PROF] op=.. cum/avg/min/max us ; "
          "nonop_queue_us (QUEUE wait) + nonop_w_inval_us + nonop_a_inval_us + "
          "nonop_bulk_flush_us + nonop_dst_track_us = decomposition NON-compute",
        "conflit": "AXE-2"}, 0.95, True),

    ("bench:axe2_jz_fastrpc_advantage", {"claims": "README: sur Snapdragon 8 Elite "
        "(SM8850 = NOTRE device) PP & TG du FastRPC-based JZ > dspqueue Qualcomm "
        "depuis 2026-07-21 (#18)",
        "why": "dspqueue = wrapper async au-dessus de FastRPC natif ; LLM inference "
          "synchrone ; ION shared mem = meme DDR vu AP+NPU ; FastRPC pur batché "
          "supprime host_param_update per-op + dcinva/syncht per-op",
        "link_axe2": "notre delta 1.73x (GGML Q4_K_M dspqueue vs QAIRT) = per-op "
          "dispatch + per-op dequant. Le backend FastRPC batched attaque le MEME "
          "overhead dispatch per-op (host_param_update ~700-800us/op chraac + "
          "dcinva/syncht per-op entry.c). Donc un build JZ FastRPC devrait "
          "reprendre une partie du 1.73x SANS changer le format -> teste "
          "directement l'hypothese dispatch-dominance.",
        "hard_numbers": "pour T_queue/T_sync reels: builder self-build-jz (HEX_OP_PROF=1) "
          "OU patcher binaire dspqueue (voir bench:axe2_profile_blocker) ; "
          "nonop_queue_us etc donnent la decomposition",
        "conflit": "AXE-2"}, 0.95, True),

    # AXE-2 / JZ-next — excavation PROFONDE du vrai backend FastRPC JZ
    # (ggml-hexagon-fastrpc.cpp host + htp/entry.c DSP + ggml_htp.idl + dsp-ctx.h,
    #  branche zhouwg/ggml-hexagon self-build-jz / pr_to_upstream_v3).
    ("src:ggml_hexagon_fastrpc_runtime", {"files": "ggml-hexagon-fastrpc.cpp (host) + "
        "htp/entry.c (DSP) + ggml_htp.idl + dsp-ctx.h ; self-build-jz / pr_to_upstream_v3",
        "already_exists": "mempool + cgraph cache + op fusion + kernel param cache + "
          "HMX/HVX auto-select + VTCM tuning + graph reorder + dirty tracking + "
          "batch execution (ONE execute_batch) + multi-device + 10-phase profiling",
        "phases_p1_p10": "p1 collect tensors, p2 build op desc, p3 op fusion, p4 layout "
          "sizes, p5 tensor mirroring, p6 repacked-weight offsets, p7 batch desc alloc, "
          "p8 descriptor construction, p9 FastRPC (rpc_setup+dsp_exec), p10 copyback, + unaccounted",
        "graph_cache": "FNV-1a hash op/ne[]/nb[]/src ptrs/data/op_params ; reuse "
          "hex_op_desc+tensors+flags ; jusqu'a 1024 graphes pre-reserves",
        "fusion": "RMS_NORM+MUL, MUL_MAT+ADD (refuse si budget VTCM depasse), QKV, "
          "FFN gate/up ; compte succes/echecs",
        "reorder": "N_FORWARD=16 : rapproche MUL_MAT/ID meme src1 pour reuse activation "
          "quantifiee VTCM (memory-locality scheduler embryon)",
        "weight_class": "src0 MUL_MAT jamais dst -> flags=2 -> DSP skip 1ere invalidation cache",
        "mempool": "v79+ : cibles 4032/3968/3840/3072/2048 MiB ; legacy 3830/3072/2048 ; "
          "best-fit + region reuse + split ; reserve target-8 (explique MBUF)",
        "mirror": "tensor hors mempool -> heap mirror + memcpy(data->mirror) ; fallback "
          "route CPU si pool plein (PR #27642)",
        "multisession": "device>0 reserve session FastRPC supplementaire (PD defaut "
          "reutilise pour device0) -> device-aware planning HTP0/HTP1",
        "idl": "setclocks / register_rpcmem / execute_batch(offset,size) ; host build "
          "batch -> UN execute_batch (PAS un RPC par op)",
        "conflit": "AXE-2"}, 0.95, True),

    ("src:ggml_hexagon_fastrpc_phases", {"T_overhead": "T_graph - T_p9 (min/max/sum par appel)",
        "p9_split": "T_p9 = T_rpc_setup + T_dsp_exec ; dump runtime imprime les 3",
        "corrected_model": "T_token = T_AP_build + T_mirror + T_descriptor + "
          "T_FastRPC(batch, PAS per-op) + T_DSP_execute + T_copyback",
        "warmup_0xFFFB": "warmup special sans compute -> borne sup pure transport "
          "FastRPC/mempool ; RPC_pure <= T_rpc_setup",
        "gap_ap_dsp": "cum_p1..cum_p10 + cum_unaccounted -> unaccounted = hors phases",
        "hwprof_phases": "ap_prepare, graph_cache, op_fusion, layout, mirror, repack, "
          "descriptor, rpc, dsp_compute, copyback, unaccounted (waterfall causal)",
        "conflit": "AXE-2"}, 0.95, True),

    ("src:ggml_hexagon_fastrpc_planner", {"retract": "JZ n'a PAS a creer graph cache / "
          "fusion / VTCM tuning / transport FastRPC : TOUS existent deja",
        "gap_A": "cost model GLOBAL (cost_HMX/HVX/fusion/reorder/VTCM/cache/memory/"
          "dispatch) pas seulement per-kernel",
        "gap_B": "global graph planner : remplace heuristique fenetre-16 par score = "
          "reuse_VTCM - cost_reorder - dependency_penalty",
        "gap_C": "memory regime detector : pool fit / heap mirror / copyback / "
          "fragmentation / VA extension",
        "gap_D": "cross-runtime profiler : GGML/JZ vs QAIRT vs MNN ontologie commune",
        "gap_E": "hardware profiles SM8750/v79 et SM8850/v81 (NOTRE device) pas tuning generique",
        "first_metric_9B": "weight_resident_bytes, weight_mirror_bytes, "
          "activation_mirror_bytes, mirror_copy_us, copyback_us, mempool_peak, mempool_fragmentation",
        "strategy": "utiliser ce code comme SPEC JZ v1 ; batir JZ-next SEULEMENT ou "
          "manque optimisation (cost_model/global_planner/memory_regime/cross_runtime/"
          "adaptive_kernel) ; ne pas cloner/repartir de zero",
        "conflit": "AXE-2"}, 0.95, True),

    ("bench:axe2_dispatch_model", {"supersedes": "bench:axe2_causal_refined (per-op "
          "FastRPC) -> le backend JZ FastRPC fait UN execute_batch par batch, PAS un RPC par op",
        "dispatch_dominance": "vraie mais mecanisme = rpc_setup (1/batch) + cache "
          "maintenance per-op (dcinva/syncht, reduits par dsp_cache_mode 0x1/0x2/0x4) ; "
          "PAS N*RTT_FastRPC",
        "queue_sync_measurable": "p9=rpc_setup+dsp_exec + nonop_queue_us (entry.c) "
          "donnent T_queue/T_sync directement",
        "internal_bench_first": "meme 9B / meme HTP / MTP OFF -> dump p1..p10 + cgraph "
          "cache + mirror bytes + HMX/HVX/fusion ; voir ou restent les ~8-14 ms/token AP",
        "conflit": "AXE-2"}, 0.95, True),

    # AXE-2/JZ — audit failure modes via governor (report/plan/step/bench/gate)
    ("bench:axe2_governor_risk", {"calibration": "samples=0, confidence=0.25 dans le "
          "domaine AXE-2/JZ -> decisions NON fondees (UCB/kappa pourraient rater l'optimum)",
        "bench_transfer": "domaine neuf (seeds 11-15): governor mean_best 12.73 < greedy "
          "14.12 (delta -1.39) ; perf/compute governor 0.328 > greedy 0.292 (s'arrete "
          "plus tot) ; verdict texte 'equivalent' CONTRADICT ses propres chiffres",
        "cost_model_stale": "bw_eff=1.011 GB/s (vs 32.4 reel HardwareGovernor) -> "
          "predictions memory-bound fausses -> utilite des actions format/layer erronee",
        "hw_snapshot_incoherent": "report: hardware_summary soc/root/selinux=NULL ; plan: "
          "soc=sm8850/npu=true -> snapshot incoherent -> state/gate lit parfois NULL",
        "risk_complacent": "risk_exposure=0.0 -> governor sous-estime le risque ; ne code "
          "PAS les risques JZ (build, contradictions de faits)",
        "gate_works": "anti-regression OK: variant stabilite 89 (regress -6.3%>5%) REJECT "
          "('capacite critique stability < -5%') ; stabilite 93 ACCEPT (Pareto). Risque "
          "corrolaire: un build JZ benefique mais instable au warmup pourrait etre REJECT",
        "mitigations": "1) nourrir calibration par benchmark interne JZ p1..p10 (>=1 echantillon "
          "reel) avant toute decision JZ-next ; 2) recalibrer bw_eff=32.4 ; 3) rollback "
          "provenance de causal_refined (supersede par dispatch_model) ; 4) build = dry-run "
          "+ capability check ; 5) exclure warmup du score stability pour le gate ; "
          "6) valider dsp_cache_mode sur petit modele avant 9B (bug L2 prompt-repeat 33%)",
        "conflit": "AXE-2"}, 0.95, True),

    # Format EXACT du dump JZ self-build-jz (verifie dans source) -> parser bench_results/jz_waterfall.py
    ("src:ggml_hexagon_fastrpc_logfmt", {"dump_trigger": "ggmlhexagon_dump_perf_stats() a la "
          "destruction du contexte (fastrpc.cpp:1640), UNE fois par run",
        "niveau": "GGMLHEXAGON_LOG_VERBOSE -> GGML_LOG_LEVEL_CONT = terminal + logcat "
          "(fastrpc.cpp:504/dsp-ctx.h:65) -> capture stdout/adb logcat",
        "lignes": [
          "AP phase cumulative: p1..p10 + unaccounted (us)",
          "p9 2-way cumulative: rpc_setup + dsp_exec (us)",
          "rpc stats: batch_calls (=batch_count)",
          "graph ops (post-fusion): min/max (=op_count=max)",
          "cgraph cache: hits/misses/hit_rate%",
          "mul_mat coverage: total/hmx/qkv_fused/ffn_fused/mm_add_fused",
          "hmx eligibility: total/pass (HMX_rejected=total-pass, conditionnel)",
          "[OP-PROF-NONOP] batch#N ... queue=Q us/batch (=nonop_queue_us)",
          "[OP-PROF] batch#N ... non-op avg=K us/batch"],
        "derive": "T_AP=p1..p8+p10+unaccounted ; T_RPC=rpc_setup ; T_DSP=dsp_exec ; "
          "T_total=T_AP+T_RPC+T_DSP ; tout /tokens_reels = per-token. fusion_count="
          "qkv_fused+ffn_fused+mm_add_fused ; HVX_used=total-hmx",
        "gap_mirror_repack": "self-build-jz N'emet PAS mirror_bytes/mirror_copies/repack_bytes "
          "en agrege (seulement [SET_TENSOR] DEBUG per-tensor). Patch build requis: ajouter "
          "cum_mirror_bytes/copies + cum_repack_bytes et 2 LOG_VERBOSE ('mirror: bytes=.. "
          "copies=..' / 'repack: bytes=..') dans dump_perf_stats. Parser supporte deja ces "
          "lignes (affiche n/a sinon)",
        "parser": "bench_results/jz_waterfall.py --log run.log --tokens N ; --self-test inclus "
          "(fixture valide reproduit l'exemple 122.8/4.1/0.7/112.4/1.2/4.4 ms)",
        "conflit": "AXE-2"}, 0.95, True),
]

# Graph : interactions A×B → synergy() exploitable par le governor.
CAUSAL = [
    (["gpu_seul"], +1.3, {"kind": "backend"}),
    (["gpu_htp_50"], +8.2, {"kind": "backend"}),
    (["gpu_htp_30"], +7.7, {"kind": "backend"}),
    (["gpu_htp_70"], +0.2, {"kind": "backend"}),
    (["output_weight_cpu"], +27.2, {"kind": "modify",
                                    "context": "llama-bench"}),
    (["mtp"], +38.2, {"kind": "modify", "statut": "validated_3_paires"}),
    (["qairt"], +152.0, {"kind": "runtime"}),
]

# Combos mesurés — effet RÉEL (ne pas confondre avec l'indépendance I).
SYNERGY_RECORDS = [
    (["output_weight_cpu", "mtp"], +9.1, {"kind": "modify",
      "mesure": "v6 2×2 serveur (6,47 vs baseline 5,93)",
      "note": "combo 6,47 < mtp seul 8,26 → ne pas combiner"}),
]


def run(dry_run=True):
    pm = ProvenanceMemory(os.path.join(ROOT, "governor_state",
                                       "provenance.json"))
    cm = CausalMemory(os.path.join(ROOT, "governor_state", "causal.json"))
    if dry_run:
        return {"dry_run": True, "facts": len(FACTS),
                "causal": len(CAUSAL), "synergy_records": len(SYNERGY_RECORDS)}
    writes = []
    for key, value, conf, rep in FACTS:
        r = pm.write(key, value, source=SRC, confidence=conf,
                     reproducible=rep)
        writes.append({"key": key, "stored": r.get("stored", False),
                       "quarantined": r.get("quarantined", False),
                       "reason": r.get("reason")})
    for changes, eff, ctx in CAUSAL + SYNERGY_RECORDS:
        cm.record(changes, eff, ctx)
    recall = pm.query("gpu htp tps")
    syn = cm.synergy("output_weight_cpu", "mtp")
    return {"writes": writes,
            "n_quarantined": sum(1 for w in writes if w["quarantined"]),
            "recall_demo": [{"key": e["key"], "value": e["value"]}
                            for e in recall],
            "synergy_outputweight_x_mtp": syn,
            "meta_rules": cm.meta_rules()}


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    dry = "--dry-run" in sys.argv
    print(json.dumps(run(dry_run=dry), ensure_ascii=False, indent=2))