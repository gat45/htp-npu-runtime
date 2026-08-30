# Profiling Android — Kotlin (APK) — profiler les modèles sur le téléphone

Guide des fichiers Kotlin du profiler Android (`apk_native`) + comment profiler
les modèles (GGUF) directement sur le OnePlus 15 (SM8850). 2026-08-30.

---

## 1. Vue d'ensemble

Le profiler Android est un **unified profiler** qui tourne sur le téléphone
(root). Il lit les modèles GGUF locaux, exécute des benchs (HTP/GPU/CPU),
collecte les métriques matérielles, et produit un rapport.

```
apk_native/app/src/main/java/com/claude/local/
├── profiler/
│   ├── GgufReader.kt          ← lit le header GGUF (arch/tensors/types/BPW par layer)
│   ├── ExecutionProvider.kt   ← GGML (q4_0/q8_0) vs QNN/QAIRT (w4a16/w8a16/w8a8/w4a8)
│   ├── ExperimentController.kt← campagne (bench × provider × placement, timeout, Pareto)
│   ├── HardwareProfiler.kt    ← ftrace/SMMU/interconnect + LayerAnalyzer + D2LocalComparer
│   ├── CommonCollector.kt     ← collecteur commun (speed/memory/hardware)
│   ├── LogParser.kt           ← source de vérité des parseurs
│   ├── ScriptGuard.kt         ← intégrité md5 des scripts root
│   └── RooflinePredictor.kt   ← prédicteur roofline calibré (gate avant bench)
├── service/
│   ├── PerLayerProfiler.kt    ← orchestrateur : profile() + runCampaign()
│   └── RootShell.kt           ← su -c, cwd correct, killTree, readFile
└── data/model/PerLayerProfile.kt ← schéma (LayerProfile, BackendPoint, ...)
```

## 2. Fichier par fichier

### 2.1 `GgufReader.kt` — lire un GGUF local
- Lit le header GGUF (RandomAccessFile, sans lib externe) : KV metadata + liste
  des tensors (nom/shape/type/offset).
- `TensorInfo` : nelements(), bytes(), layer(), category().
- `ModelInfo` : arch, blockCount, tensorCount, kv, tensors, totalBytes.
- `layerSummary()` : répartition par layer + catégorie + types.
- **Usage** : profiler un GGUF du device sans charger le fichier entier.

### 2.2 `ExecutionProvider.kt` — les 2 chemins d'exécution
- `GgmlExecutionProvider` : formats GGML (Q4_0/Q8_0/Q4_K_M/F16), backends
  cpu/htp/gpu/cpu+htp.
- `QnnExecutionProvider` : formats QAIRT (FP16/W8A16/W8A8/W4A16/W4A8), backends
  htp/gpu/htp+gpu.
- `Providers` : registre unifié + `point()` (BackendPoint vide, matrice complète).

### 2.3 `ExperimentController.kt` — la campagne
- `runCampaign()` : discover → bench (provider×format×placement) → MTP →
  analyse (Pareto, croisement, D2LocalComparer) → artefacts
  (`/sdcard/op15_campaign/` : experiment.json, metrics.json, raw/, report.md).
- Timeout global 30 min + onProgress (callback).

### 2.4 `HardwareProfiler.kt` — matériel + analyse
- `ftraceCounts()` : fastrpc/SMMU/interconnect.
- `bottleneck()` : memory-bandwidth / compute / unknown.
- `perfCounters()`, `graphSplitCount()`, `topOps()`.
- `LayerAnalyzer` : profils par layer (budget réel + poids du modèle).
- `D2LocalComparer` : conformité GGUF local vs allocation D2 (sans référence externe).

### 2.5 `CommonCollector.kt` — collecteur commun
- `collect()` : speed (PP/TG) + memory (RAM/VRAM/VMEM) + hardware
  (smmu/interconnect/fastrpc/cpuFallback/graphSplit/temp) — mêmes catégories
  pour GGML et QAIRT → résultats comparables.

### 2.6 `LogParser.kt` — source de vérité des parseurs
- `parseTps/parsePrefill/parseResultJson/parseMatrixVal/parseFtraceCounts/
  parseVmem/parseMemFreeMb/parseNpuProfilerJson`.

### 2.7 `RooflinePredictor.kt` — prédicteur calibré (gate avant bench)
- Implémente l'équation roofline (Hextimate) : `t = bytes/token / BW_eff`.
- Calibré : BW_GGML ~30.5 GB/s, BW_QAIRT ~74 GB/s.
- Prédit le decode t/s AVANT de lancer un bench → gate.

## 3. Utilisation (depuis l'UI)

1. Profiling screen → bouton "Profil layer" : lance le profilage GGUF local.
2. Bouton "Campagne" : lance la campagne complète (7 moteurs).
3. Root requis : les scripts tools/ + lecture sysfs.

## 4. Types de fichiers profilables en local

| Type | Profilable | Fichier Kotlin |
|---|---|---|
| **GGUF** | ✅ OUI | GgufReader.kt (arch/tensors/types/BPW) |
| Logs bench (*.log) | ✅ OUI | LogParser.kt |
| Traces kernel (ftrace) | ✅ OUI | HardwareProfiler.kt |
| JSON (npu_profile.json) | ✅ OUI | LogParser.kt |
| **Safetensors** | ❌ NON (PC/HF) | — |
| Bundle QAIRT (.bin) | ⚠️ partiel (metadata) | — |

## 5. Référence (reverse compilateur QAIRT)

Confirmé dans `libQnnHtpPrepare.so` (geniex-android 0.4.0) :
- HiGHS (MILP) : 139 strings · Hextimate : 25 · VTCM : 404 ·
  relaxed_precision : 13 · spillFill : 27 · `_lifetime_ddr_spillfill.csv`.
- Voir `docs_onesplus/CHECKLIST_NPU_QUALCOMM_20260830.md`.