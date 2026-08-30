# Documentation Reproductible — NPU HTP/GPU + MTP (OnePlus 15 SM8850)

**Version :** 2026-08-30
**Arborescence complète** de tous les artefacts (code, scripts, rapports) + reproduction pas à pas.

---

## 1. État du dossier (propre ?)

**NON entièrement propre** — il reste des changements non committés dans le fork.

### Commits validés (travail stable)
| Commit | Contenu |
|--------|---------|
| `859926e7` | pass 4.5 (topological sort HTP-first) + compat24o + EINTERRUPTED |
| `1248f04f` | rebuild skel corrige hang ADD (pipeline fonctionne) |
| `505354ed` | **fix GDN** Qwen3.5-9B (`ggml_cont_4d`) |

### Non committé (à décider)
| Fichier | Contenu |
|---------|---------|
| `ggml/src/ggml-hexagon/ggml-hexagon.cpp` | **opt_mm_rows** (limite lm-head configurable) + debug |
| `ggml/src/ggml-backend.cpp` | debug scheduler (pass 4.5) |
| `conversion/qwen.py` | (autre session) |
| `ggml-alloc.c/h`, `test-alloc.cpp`, `test-pass45-determinism.cpp` | (autre session — fix gallocr) |

---

## 2. Arborescence du fork (`D:\jz_work\ggml-hexagon-fork`)

```
ggml-hexagon-fork/
├── ggml/
│   ├── src/
│   │   ├── ggml-backend.cpp        ← pass 4.5 (topo sort) + debug
│   │   ├── ggml-alloc.c            ← [autre session] fix gallocr + fingerprint
│   │   └── ggml-hexagon/
│   │       ├── ggml-hexagon.cpp    ← opt_mm_rows, compat24o, EINTERRUPTED
│   │       ├── ggml-hexagon-fastrpc.cpp  ← variante mempool (dispatch graphe)
│   │       └── htp/
│   │           ├── main.c          ← skel dspqueue (rebuild 735KB)
│   │           ├── entry.c         ← skel fastrpc/mempool
│   │           └── cmake-toolchain.cmake ← toolchain hexagon
│   ├── include/
│   │   └── ggml-alloc.h            ← [autre session] API debug_mismatch_count
│   └── ...
├── src/
│   └── models/
│       └── qwen35.cpp              ← fix GDN ggml_cont_4d
├── common/
│   └── speculative.cpp             ← contexte MTP
├── tests/
│   ├── test-alloc.cpp              ← [autre session]
│   └── test-pass45-determinism.cpp ← [autre session] (nouveau, non commité)
├── build-android/
│   └── bin/                        ← libs ARM64 + llama-bench + llama-cli + llama-server
└── build-mempool/
    └── bin/                        ← backend mempool (fastrpc)
```

---

## 3. Arborescence des scripts device (`/data/local/tmp/`)

```
/data/local/tmp/
├── Qwen3.5-9B-D2-A.gguf            ← modèle optimisé (mlp/ssm Q4_0, attn Q8_0, norms F16)
├── Qwen3.5-9B-D2-A-MTP.gguf        ← modèle MTP (têtes nextn, fonctionnel)
├── Qwen3-8B-Q4_K_M.gguf            ← modèle Q4_K_M (GPU optimal)
├── Qwen3-8B-Q4_0.gguf              ← Q4_0 converti
├── qwen3.5-9b-pocketpal/           ← modèles pocketpal
├── sweep/                          ← Qwen3-1.7B, Qwen3-4B (petits modèles)
├── qwen3-8b-w4a16/                 ← bundle QAIRT (oracle spill)
├── npu/                            ← LIBRAIRIES + BINAIRES
│   ├── llama-bench, llama-cli, llama-server
│   ├── libggml-hexagon.so          ← backend (opt_mm_rows)
│   ├── libggml-htp-v81.so          ← skel (rebuild 735KB)
│   ├── libggml-base.so, libggml.so, libggml-cpu.so, libggml-opencl.so
│   ├── libllama.so, libllama-common.so, libllama-cli-impl.so
│   ├── libmtmd.so                  ← module MTP
│   └── libcdsprpc.so, libOpenCL.so ← libs HAL (issue #27677)
├── thermal_governor.sh / _2 / _3   ← bascule GPU↔NPU à 60°C
├── monitor_hw.sh                   ← températures + util GPU
├── gpu_temp.sh                     ← température GPU (gpuss)
├── check_npu_active.sh             ← compteur fastrpc (root)
├── balance_npu_gpu.sh              ← balance NPU/GPU
├── run_mtp_d2a*.sh, run_server_mtp.sh ← tests MTP
├── test_fn_split.sh, sweep_d2a*.sh ← tests layer-split/sweep
└── ram_monitor.sh                  ← monitoring RAM
```

---

## 4. Arborescence des scripts locaux (`C:\Users\videl\AppData\Local\Temp\opencode\`)

```
opencode/
├── build_skel_wsl.sh               ← build skel dspqueue (WSL)
├── build_skel_mempool_wsl.sh       ← build skel fastrpc (WSL)
├── host-cxx.cmd / .sh              ← host compiler WSL (llama-ui-embed)
├── libggml-htp-v81-new.so          ← skel dspqueue rebuildé
├── libggml-htp-v81-mempool.so      ← skel fastrpc rebuildé
├── opencl-headers/                 ← headers Khronos (build OpenCL)
├── opencl-lib/                     ← libOpenCL.so du device
├── recover_rag.py                  ← récupération provenance depuis RAG
├── prov_*.py                       ← mises à jour provenance
└── *_monitor.sh, *_measure.sh      ← scripts de test
```

---

## 5. Arborescence des rapports (`C:\Users\videl\Desktop\geniex_harness\docs_onesplus`)

```
docs_onesplus/
├── RAPPORT_NPU_HTP_GPU_20260830.md          ← RAPPORT PRINCIPAL (croisé MCP + RE datavorous)
├── GUIDE_REPRODUCTION_NPU_HTP_20260829.md   ← guide reproduction sans scripts
├── RAPPORT_RESOLUTION_SKEL_HANG_20260829.md ← tuto résolution hang skel
├── RAPPORT_SESSION_20260829.md              ← session 29
├── LEVIERS_OPTIMISATION_MTP_GRAPHE_20260829.md ← leviers MTP + dispatch graphe
├── build_skel_wsl.sh                        ← script build skel (copie)
├── deploy_skel_and_run.ps1                  ← déploiement + bench
└── ... (rapports antérieurs 24-28 août)
```

---

## 6. Reproduction pas à pas

### A. Rebuild skel (WSL)
```bash
# dspqueue (corrige hang ADD)
wsl -d Ubuntu -e bash -c 'cp /mnt/c/Users/videl/AppData/Local/Temp/opencode/build_skel_wsl.sh /tmp/ && chmod +x /tmp/build_skel_wsl.sh && /tmp/build_skel_wsl.sh'
# fastrpc/mempool (dispatch graphe)
wsl -d Ubuntu -e bash -c 'cp /mnt/c/Users/videl/AppData/Local/Temp/opencode/build_skel_mempool_wsl.sh /tmp/ && chmod +x /tmp/build_skel_mempool_wsl.sh && /tmp/build_skel_mempool_wsl.sh'
```

### B. Build AP avec OpenCL + MTP
```powershell
cmake -S D:\jz_work\ggml-hexagon-fork -B D:\jz_work\ggml-hexagon-fork\build-android -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DGGML_OPENCL=ON `
  -DOpenCL_INCLUDE_DIR=C:\Users\videl\AppData\Local\Temp\opencode\opencl-headers `
  -DOpenCL_INCLUDE_DIRS=C:\Users\videl\AppData\Local\Temp\opencode\opencl-headers `
  -DOpenCL_LIBRARY=C:\Users\videl\AppData\Local\Temp\opencode\opencl-lib\libOpenCL.so `
  -DOpenCL_LIBRARIES=C:\Users\videl\AppData\Local\Temp\opencode\opencl-lib\libOpenCL.so `
  -DLLAMA_BUILD_UI=OFF -DLLAMA_BUILD_SERVER=ON `
  -DHOST_CXX_COMPILER=C:\Users\videl\AppData\Local\Temp\opencode\host-cxx.cmd
cmake --build D:\jz_work\ggml-hexagon-fork\build-android --config Release --target llama-server llama-cli llama-bench ggml
```

### C. Déploiement device
```powershell
$adb = "C:\Users\videl\Desktop\geniex_harness\tools\platform-tools\adb.exe"
$bin = "D:\jz_work\ggml-hexagon-fork\build-android\bin"
# libs + skel + binaires
& $adb push "$bin\libggml-hexagon.so" /data/local/tmp/npu/
& $adb push "$bin\libggml-base.so" /data/local/tmp/npu/
& $adb push "$bin\libggml.so" /data/local/tmp/npu/
& $adb push "$bin\llama-server" /data/local/tmp/npu/
& $adb push "C:\Users\videl\AppData\Local\Temp\opencode\libggml-htp-v81-new.so" /data/local/tmp/npu/libggml-htp-v81.so
# libs HAL (issue #27677)
& $adb shell "cp /vendor/lib64/libcdsprpc.so /data/local/tmp/npu/"
& $adb shell "cp /vendor/lib64/libOpenCL.so /data/local/tmp/npu/"
```

### D. Benchmarks clés
```powershell
# D2-A HTP0 pur (meilleur decode 8.90 t/s)
adb shell "cd /data/local/tmp/npu && LD_LIBRARY_PATH=/data/local/tmp/npu GGML_HEXAGON_NDEV=1 ./llama-bench -m /data/local/tmp/Qwen3.5-9B-D2-A.gguf -ngl 99 -p 16 -n 16 -t 8 -dev HTP0"

# MTP (draft acceptance 52.9%, ~16 t/s effectifs)
adb shell "cd /data/local/tmp/npu && nohup sh run_server_mtp.sh &"
adb shell "curl -s http://127.0.0.1:8080/completion -d '{\"prompt\":\"The capital of France is\",\"n_predict\":16,\"temperature\":0}'"

# Q4_K_M GPU-only (9.28 t/s)
adb shell "cd /data/local/tmp/npu && LD_LIBRARY_PATH=/data/local/tmp/npu ./llama-bench -m /data/local/tmp/Qwen3-8B-Q4_K_M.gguf -ngl 99 -p 16 -n 16 -t 8 -dev GPUOpenCL"
```

---

## 7. Résultats clés à revalider

| Test | Config | tg16 | Note |
|------|--------|------|------|
| D2-A | HTP0 pur (froid 41°C) | **8.90** | record |
| D2-A | HTP0 pur (chaud 70°C) | 8.22 | throttling -8% |
| D2-A-MTP | llama-server draft-mtp | **~16 eff.** | acceptance 52.9% |
| Q4_K_M | GPU-only | **9.28** | HTP ne supporte pas Q4_K_M |
| 8B | 3 HTP | 0.96 | effondrement (CPU-bound) |
| lm_head | sur HTP (262144 rows) | 2.06 | régression vs CPU (8.90) |

---

## 8. Protocole thermique (gouverner la bascule)

```
monitor GPU temp (gpuss, exclure *trip*)
GPU > 60°C → basculer vers NPU/HTP (Plan C)
GPU < 50°C → revenir GPU (hystérésis)
```
Scripts : `thermal_governor.sh` (device) + `monitor_hw.sh`.

---

## 9. Notes critiques

1. **Le dossier n'est pas propre** : opt_mm_rows (mon travail) + fix gallocr (autre session) non committés.
2. **Le lm_head HTP régresse sur v81** (2.06 vs 8.90) — garder le défaut 32768.
3. **Le MTP marche via llama-server, PAS llama-cli** (cli boucle).
4. **Issue #27677** : ne pas mettre /vendor/lib64 dans LD_LIBRARY_PATH (casse la session HAL).
5. **Mesurer à froid** (<55°C GPU) sinon résultats biaisés (throttling).
