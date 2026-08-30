# GUIDE DE REPRODUCTION COMPLET — Runtime NPU Hybride (JZ/GenieX) sur HTP v81

**Date :** 2026-08-29
**Device :** OnePlus 15 CPH2747 (SM8850, HTP v81, CDSP domain 3)
**Objectif :** Reproduire TOUTES les découvertes et leviers SANS scripts personnalisés — uniquement des commandes natives.

---

## TABLE DES MATIÈRES
1. [Prérequis & environnement](#1-prérequis--environnement)
2. [Vérification du device & fingerprint](#2-vérification-du-device--fingerprint)
3. [Rebuild du skel HTP (WSL, sans QEMU)](#3-rebuild-du-skel-htp-wsl-sans-qemu)
4. [Build AP avec OpenCL (GPU Adreno)](#4-build-ap-avec-opencl-gpu-adreno)
5. [Conversion GGUF Q4_K_M → Q4_0](#5-conversion-gguf-q4_k_m--q4_0)
6. [Benchmarks de référence](#6-benchmarks-de-référence)
7. [Découvertes clés & leviers](#7-découvertes-clés--leviers)
8. [Troubleshooting](#8-troubleshooting)
9. [Annexes : logs & preuves](#9-annexes--logs--preuves)

---

## 1. PRÉREQUIS & ENVIRONNEMENT

### 1.1 Outils requis
| Outil | Emplacement | Rôle |
|-------|-------------|------|
| ADB | `C:\Users\videl\Desktop\geniex_harness\tools\platform-tools\adb.exe` | Accès device |
| Hexagon SDK 6.6.0.0 | `C:\Users\videl\Desktop\geniex_harness\tools\_toolchains\Hexagon_SDK\6.6.0.0` | Compiler skel |
| NDK Android | `C:\Users\videl\AppData\Local\Android\Sdk\ndk\27.2.12479018` | Build AP |
| WSL2 Ubuntu | `wsl -d Ubuntu` | Compiler skel (hexagon-clang = ELF Linux) |
| CMake + Ninja | système | Build |
| Git | système | Fork |

### 1.2 Sources (fork)
| Source | Chemin |
|--------|--------|
| Fork ggml-hexagon | `D:\jz_work\ggml-hexagon-fork` |
| Backend dspqueue | `ggml\src\ggml-hexagon\ggml-hexagon.cpp` |
| Backend fastrpc/mempool | `ggml\src\ggml-hexagon\ggml-hexagon-fastrpc.cpp` |
| Skel dspqueue (DSP) | `...\htp\main.c` |
| Skel fastrpc (DSP) | `...\htp\entry.c` |
| Toolchain skel | `...\htp\cmake-toolchain.cmake` |

---

## 2. VÉRIFICATION DU DEVICE & FINGERPRINT

### 2.1 Connexion ADB
```powershell
# Port wifi (variable, vérifier avec adb devices)
adb connect 192.168.1.11:5555
adb devices
```

### 2.2 Fingerprint (à enregistrer à chaque session)
```powershell
adb shell "getprop ro.build.fingerprint"
adb shell "getprop ro.board.platform"
adb shell "getprop ro.soc.model"
adb shell "uname -r"
adb shell "cat /sys/devices/soc0/soc_id"
```
Résultat attendu :
- Fingerprint : `OnePlus/CPH2747/OP611FL1:16/BP2A.250605.015/...`
- Board : `canoe`
- SoC : `SM8850` (soc_id 660)
- Kernel : `6.12.23-android16-5`

### 2.3 Température (avant chaque bench)
```powershell
adb shell "cat /sys/class/thermal/thermal_zone*/temp | head -3"
# Attendu : ~31000-35000 (31-35°C). >70°C = invalide pour benchmark.
```

### 2.4 Modèles présents sur le device
```powershell
adb shell "ls -la /data/local/tmp/*.gguf"
adb shell "find /data/local/tmp -name '*.gguf'"
```

---

## 3. REBUILD DU SKEL HTP (WSL, SANS QEMU)

**Pourquoi :** `hexagon-clang` est un binaire ELF Linux → il faut WSL (pas QEMU).

### 3.1 Vérifier hexagon-clang dans WSL
```bash
wsl -d Ubuntu -e bash -c 'TOOLS="/mnt/c/.../Hexagon_SDK/6.6.0.0/tools/HEXAGON_Tools/19.0.07"; "$TOOLS/Tools/bin/hexagon-clang" --version'
# Attendu : "QuIC LLVM Hexagon Clang version 19.0.07"
```

### 3.2 Variante DSPQUEUE (main.c) — celle qui corrige le hang ADD
```bash
wsl -d Ubuntu -e bash -c '
export HEXAGON_SDK_ROOT="/mnt/c/.../Hexagon_SDK/6.6.0.0"
export HEXAGON_TOOLS_ROOT="$HEXAGON_SDK_ROOT/tools/HEXAGON_Tools/19.0.07"
export HEXAGON_ARCH=v81; export DSP_VERSION=v81
export PREBUILT_LIB_DIR="$HEXAGON_TOOLS_ROOT/Tools/target/hexagon/lib"
SRC="/mnt/d/jz_work/ggml-hexagon-fork/ggml/src/ggml-hexagon/htp"
BUILD="/tmp/skel-dspqueue-v81"
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$SRC/cmake-toolchain.cmake" \
  -DHEXAGON_SDK_ROOT="$HEXAGON_SDK_ROOT" \
  -DHEXAGON_TOOLS_ROOT="$HEXAGON_TOOLS_ROOT" \
  -DHEXAGON_ARCH=v81 -DDSP_VERSION=v81 \
  -DPREBUILT_LIB_DIR="$PREBUILT_LIB_DIR" \
  -DGGML_HEXAGON_USE_MEMPOOL=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD"
find "$BUILD" -name "libggml-htp-*.so"
'
# Sortie : /tmp/skel-dspqueue-v81/libggml-htp-v81.so (~734 920 octets)
```

### 3.3 Variante FASTPRC/mempool (entry.c) — dispatch par graphe
```bash
# MÊME commande, MAIS -DGGML_HEXAGON_USE_MEMPOOL=ON
# Sortie : ~741 840 octets (utilise entry.c + ggml_htp.idl au lieu de main.c)
```

### 3.4 Piège connu (PREBUILT_LIB_DIR)
Sans `PREBUILT_LIB_DIR`, CMake échoue : `hexagon_fun.cmake:99 string FIND requires 3 or 4 parameters`.
**Fix :** le définir manuellement (le sourcing du SDK est court-circuité car `HEXAGON_SDK_ROOT` est déjà exporté).

### 3.5 Copier vers Windows
```bash
wsl -d Ubuntu -e bash -c 'cp /tmp/skel-dspqueue-v81/libggml-htp-v81.so "/mnt/c/Users/videl/AppData/Local/Temp/opencode/libggml-htp-v81-dspqueue.so"'
```

---

## 4. BUILD AP AVEC OPENCL (GPU ADRENO)

**Objectif :** activer le backend OpenCL (GPU) qui donne 11.14 t/s.

### 4.1 Télécharger les headers OpenCL (Khronos)
```powershell
$dest = "C:\Users\videl\AppData\Local\Temp\opencode\opencl-headers\CL"
New-Item -ItemType Directory -Path $dest -Force
# Télécharger depuis https://github.com/KhronosGroup/OpenCL-Headers :
# cl.h, cl_platform.h, opencl.h, cl_version.h, cl_ext.h, cl_gl.h, ...
# IMPORTANT : tous dans le dossier CL\ (sinon "CL/cl.h not found")
```

### 4.2 Récupérer la vraie libOpenCL.so du device (pour le link)
```powershell
adb pull /vendor/lib64/libOpenCL.so "C:\Users\videl\AppData\Local\Temp\opencode\opencl-lib\libOpenCL.so"
# ~87 904 octets — ICD loader qui exporte les symboles cl*
# (un stub vide ne marche PAS : "undefined symbol: clSetKernelArg")
```

### 4.3 Configurer le build avec OpenCL
```powershell
cmake -S "D:\jz_work\ggml-hexagon-fork" -B "D:\jz_work\ggml-hexagon-fork\build-android" -G Ninja `
  "-DCMAKE_BUILD_TYPE=Release" `
  "-DGGML_OPENCL=ON" `
  "-DOpenCL_INCLUDE_DIR=C:/Users/videl/AppData/Local/Temp/opencode/opencl-headers" `
  "-DOpenCL_INCLUDE_DIRS=C:/Users/videl/AppData/Local/Temp/opencode/opencl-headers" `
  "-DOpenCL_LIBRARY=C:/Users/videl/AppData/Local/Temp/opencode/opencl-lib/libOpenCL.so" `
  "-DOpenCL_LIBRARIES=C:/Users/videl/AppData/Local/Temp/opencode/opencl-lib/libOpenCL.so"
```

### 4.4 Build
```powershell
cmake --build "D:\jz_work\ggml-hexagon-fork\build-android" --config Release --target llama-bench ggml
# Sortie : bin\libggml-opencl.so, bin\libggml-hexagon.so, bin\llama-bench
```

### 4.5 Pièges connus
- `OpenCL_INCLUDE_DIRS` (avec S) doit être passé explicitement (le find_package écrase sinon)
- Headers doivent être dans `CL\` (structure correcte pour `#include <CL/cl.h>`)
- La lib de link doit être la VRAIE libOpenCL.so du device (avec symboles cl*)

### 4.6 Déployer sur device
```powershell
adb shell "chmod 755 /data/local/tmp/npu/llama-bench"
adb push "D:\jz_work\ggml-hexagon-fork\build-android\bin\llama-bench" /data/local/tmp/npu/llama-bench
adb push "D:\jz_work\ggml-hexagon-fork\build-android\bin\libggml-opencl.so" /data/local/tmp/npu/libggml-opencl.so
adb push "...\bin\libggml.so" /data/local/tmp/npu/libggml.so
adb push "...\bin\libggml-base.so" /data/local/tmp/npu/libggml-base.so
adb push "...\bin\libggml-cpu.so" /data/local/tmp/npu/libggml-cpu.so
adb push "...\bin\libggml-hexagon.so" /data/local/tmp/npu/libggml-hexagon.so
```

### 4.7 Vérifier les devices
```powershell
adb shell "cd /data/local/tmp/npu && LD_LIBRARY_PATH=/data/local/tmp/npu ./llama-bench --list-devices"
# Attendu :
#   GPUOpenCL: QUALCOMM Adreno(TM) 840 (OpenCL 3.0)
#   HTP0: Hexagon (v81)
```

---

## 5. CONVERSION GGUF Q4_K_M → Q4_0

**Pourquoi :** Q4_0 est supporté par le HTP (MUL_MAT sur NPU) ; Q4_K_M reste sur CPU.

### 5.1 Via llama-quantize (sur device)
```powershell
adb shell "cd /data/local/tmp/npu && LD_LIBRARY_PATH=/data/local/tmp/npu ./llama-quantize --allow-requantize /data/local/tmp/Qwen3-8B-Q4_K_M.gguf /data/local/tmp/Qwen3-8B-Q4_0.gguf Q4_0 8"
# Sortie : quant size = 4547.88 MiB (4.66 BPW), ~20s
```

### 5.2 Piège
- `llama-quantize` nécessite `LD_LIBRARY_PATH=/data/local/tmp/npu` (sinon "libllama-quantize-impl.so not found")

---

## 6. BENCHMARKS DE RÉFÉRENCE

### 6.1 Protocole standard
```powershell
adb shell "cd /data/local/tmp/npu && nohup sh -c 'export LD_LIBRARY_PATH=/data/local/tmp/npu; export ADSP_LIBRARY_PATH=/data/local/tmp/npu; export GGML_HEXAGON_NDEV=1; export GGML_HEXAGON_MBUF=3200; ./llama-bench -m <MODEL> -ngl 99 -p 16 -n 16 -t 8 > /data/local/tmp/bench.log 2>&1' &"
```
**Règles (critiques) :**
- `LD_LIBRARY_PATH` = `/data/local/tmp/npu` (NE PAS ajouter `/vendor/lib64` → casse la session : err 114, v73, 0x72)
- `-p` sans espace (`-p16`) = invalide → utiliser `-p 16`
- `-ngl` sans espace (`-ngl99`) = invalide → utiliser `-ngl 99`
- Température >70°C = invalide

### 6.2 Les benchmarks à faire (TEST 1-5 du verdict)
```powershell
# TEST 1 : Q4_0 + HTP0 + dspqueue (baseline)
adb shell "... ./llama-bench -m Qwen3-8B-Q4_0.gguf -ngl 99 -p 16 -n 16 -t 8"

# TEST 2 : Q4_0 + HTP0 + FastRPC/mempool (à débloquer)

# TEST 3 : Q4_0 + HTP0 + FastRPC + MTP (--spec-type draft-mtp)

# TEST 4 : Q4_0 + HTP0+HTP1 (GGML_HEXAGON_NDEV=2)

# TEST 5 : FastRPC + HTP0+HTP1 + MTP
```

### 6.3 Chemin GPU (le plus rapide actuellement)
```powershell
adb shell "cd /data/local/tmp/npu && nohup sh -c 'export LD_LIBRARY_PATH=/data/local/tmp/npu; export ADSP_LIBRARY_PATH=/data/local/tmp/npu; ./llama-bench -m /data/local/tmp/Qwen3-8B-Q4_K_M.gguf -ngl 99 -p 16 -n 16 -t 8 -dev GPUOpenCL,HTP0 > /data/local/tmp/bench_gpuhtp.log 2>&1' &"
```

---

## 7. DÉCOUVERTES CLÉS & LEVIERS

### 7.1 Résultats mesurés (Qwen3-8B Q4_K_M, ngl99, t8)
| Chemin | tg16 | pp16 |
|--------|------|------|
| **GPUOpenCL (Adreno 840)** | **11.14 ± 0.06** | 55.97 |
| HTP0 (dspqueue) | 6.66 ± 0.28 | 11.27 |
| CPU-only (ngl0, t8) | 5.10 | 12.45 |

### 7.2 Résultats Qwen3-8B Q4_0 (ngl99, t8)
| Chemin | tg16 |
|--------|------|
| HTP0 (dspqueue, MUL_MAT sur NPU) | 6.48 ± 0.54 |

### 7.3 MTP (Qwen3.5-9B)
- HTP baseline : 6.00 t/s
- **+MTP : 8.29 t/s (+38.2%)** — commande `--spec-type draft-mtp` SEUL

### 7.4 Les 4 mécanismes réels à tester (verdict ACCEPT)
1. **FastRPC/ION mempool** (`execute_batch()` unique, mempool par offset) — H1
2. **Multi-HTP** (HTP0+HTP1, 2 flux de poids) — H2
3. **DMA → VTCM** (réutilisation chunks dans 8 MB) — H3
4. **lm_head split** (~0.5-0.8 GB/token) — H5

### 7.5 Point de repère clé
- **6.48 → 8.29 t/s avec MTP** prouve que le débit n'est PAS égal à la BW DDR brute.
- **30.5 GB/s mesuré ≠ plafond LPDDR** (multi-session, mmap/reuse, ION mempool peuvent changer le chemin).

---

## 8. TROUBLESHOOTING

| Symptôme | Cause | Fix |
|----------|-------|-----|
| `0x80000406` (AEE_EUNABLETOLOAD) | skel introuvable | `ADSP_LIBRARY_PATH=/data/local/tmp/npu` |
| `0x80000414` (hwinfo failed) | vieux skel | rebuild skel (main.c) |
| Hang ADD (100% CPU) | vieux skel ne répond pas à l'ADD | rebuild skel |
| `bad response size 24` | mismatch htp_opbatch_rsp | fix compat24o (flush_pending) |
| `/vendor/lib64` → err 114/v73/0x72 | mauvais libcdsprpc | NE PAS ajouter /vendor/lib64 |
| `-ngl99` invalide | espace manquant | `-ngl 99` |
| `CL/cl.h not found` | headers mal placés | mettre dans `CL\` |
| `undefined symbol: clSetKernelArg` | stub OpenCL vide | utiliser vraie libOpenCL.so du device |
| mempool ne charge pas | reg retourne null | déboguer résolution (P1) |
| GDN crash (9B) | arch qwen355 SSM | backport PR #26113 |

---

## 9. ANNEXES : LOGS & PREUVES

### 9.1 Log hwinfo (nouveau skel)
```
ggml-hex: HTP0 hwinfo: threads 8, hvx 8, hmx 1, vtcm 8 MB
```
→ confirme **VTCM 8 MB** sur v81.

### 9.2 Logs benchmark
| Fichier device | Contenu |
|----------------|---------|
| `/data/local/tmp/bench_gpuhtp.log` | GPU+HTP (11.14 t/s) |
| `/data/local/tmp/bench_8b_q40.log` | Q4_0 HTP |
| `/data/local/tmp/bench_htp_t8.log` | HTP t8 |
| `/data/local/tmp/bench_cpu_ref.log` | CPU-only |

### 9.3 Provenance (traçabilité)
`C:\Users\videl\Desktop\geniex_harness\governor_state\provenance.json` (817+ entrées)
- `gpu_opencl_rebuild_20260829` : GPU 11.14 t/s
- `q40_npu_comparison_20260829` : Q4_0 NPU
- `threads_factor_20260829` : -t 1 = artefact
- `essai_mempool_graph_dispatch_20260829` : dispatch par graphe n_splits=1

### 9.4 Archives (état figé)
`C:\Users\videl\Desktop\geniex_harness\archives\HTPv81_20260829\`
- Skel dspqueue (sha256 C74AC462...)
- Host libs + commit 1248f04f + MANIFEST.txt

---

## RÉSUMÉ EXÉCUTIF

1. **Le GPU (Adreno OpenCL) est le chemin le plus rapide** : 11.14 t/s (Q4_K_M), à reproduire via build GGML_OPENCL=ON.
2. **Le skel rebuild corrige le hang ADD** (dspqueue main.c, 734920 octets).
3. **MTP donne +38.2%** (6.00 → 8.29 t/s).
4. **La variante mempool (FastRPC, dispatch par graphe)** existe et donne n_splits=1 mais ne se charge pas dans llama-bench → à débloquer (H1).
5. **Prochaine expérience** : TEST 1-5 (FastRPC, multi-HTP, MTP combinés) avec métriques complètes (tok/s, GB/token, RPC count, VTCM, lm_head).
