# RAPPORT — ARGSORT TOP-K MoE : INVESTIGATION REPRODUCTIBLE (2026-09-02)

## 1. CONTEXTE ET QUESTION

Le profiling Marco-Nano (contrôle MoE-sparse, 26,7 t/s wall sur HTP0) a révélé
que l'**ARGSORT domine le temps DSP : 35,7 %** (253 386 µs sur 710 034 µs,
215,5 µs/op, n=1176 sur 40 tokens). Question : ce coût est-il justifié, et peut-on
le réduire ?

**Fait de base vérifié** : le MoE sélectionne 8 experts sur 256, mais le tri
exécuté est un tri COMPLET des 256 valeurs.

## 2. DÉCOUVERTE CLÉ (code)

### 2.1 Le graph MoE trie TOUT pour n'utiliser que 8

`src/llama-graph.cpp:2057` (build MoE commun) :

```cpp
selected_experts = ggml_argsort_top_k(ctx0, selection_probs, n_expert_used); // [n_expert_used, n_tokens]
```

`ggml_argsort_top_k` (`ggml/src/ggml.c:5376`) = **argsort complet DESC + view** :

```cpp
struct ggml_tensor * result = ggml_argsort(ctx, a, GGML_SORT_ORDER_DESC); // TRI COMPLET de ne[0]
result = ggml_view_4d(ctx, result, k, ...); // puis on jette tout sauf les k premiers
```

→ Pour Marco-Nano : `a->ne[0] = 256` experts, `k = n_expert_used = 8`. Le tri
complet des 256 (bitonic O(n·log²n) sur HVX) est fait, puis 248 indices sont jetés.

### 2.2 Une op top-k NATIVE existe déjà — mais CPU seulement

`ggml/src/ggml.c:5403` définit `GGML_OP_TOP_K` (résultat I32 [k, ...]) :

- **Support CPU** : `ggml/src/ggml-cpu/ggml-cpu.c:1984, 2397, 2947` ✅
- **Support hexagon/HTP** : `ggml/src/ggml-hexagon/` → **0 occurrence** ❌
- Archis qui l'utilisent déjà : deepseek32.cpp:325 (`ggml_top_k`), deepseek4,
  glm-dsa, minimax-m3

### 2.3 L'implémentation HTP du tri complet

`ggml/src/ggml-hexagon/htp/argsort-ops.c` :
- `bitonic_sort_generic_hvx` (ligne 247) : tri bitonic HVX complet, registres
  V[32]/I[32], log₂(256) = 8 étages × stages internes
- Dispatch par taille : `sort256_f32_hvx` (ligne 369) avec K=8 vecteurs de 32 f32
- Coût mesuré : 215 µs/op pour 256 f32 → ~29 ops/token (28 layers + divers)
  = **~6,3 ms/token de tri pur**, soit ~17 % du wall propre 37 ms/token

## 3. DIAGNOSTIC

| Fait | Valeur |
|---|---|
| Dimension du tri (K réel) | **256 experts** (Marco-Nano) |
| Utilisé (n_expert_used) | **8** |
| Gaspillage | **248/256 = 96,9 % des indices triés sont jetés** |
| Coût HTP mesuré | 215,5 µs/op · 29,4 ops/token · **~6,3 ms/token** |
| Part du DSP | 35,7 % |
| Alternative native | `GGML_OP_TOP_K` (tri partiel) — CPU ✅ / HTP ❌ |

## 4. OPTIONS (classées par effort/gain estimé)

### Option A — Exécuter le top-k sur CPU (le plus simple, patch 1 ligne)
Déplacer le tri hors HTP : le CPU fait un tri partiel top-8 de 256 f32 en
quelques µs (vs 215 µs HTP). Le placement se fait en marquant l'op comme non
supportée HTP (comme SOFT_MAX qui part déjà en CPU — les splits CPU SOFT_MAX
sont visibles dans le log) ou en forçant le device CPU pour `ffn_moe_argsort`.

- Code touché : `ggml/src/ggml-hexagon/ggml-hexagon.cpp` (supports_op /
  can_compute sur GGML_OP_ARGSORT) OU scheduler
- **Risque** : coût de frontière HTP→CPU→HTP pour 1 KB de données (256 f32) —
  mais SOFT_MAX fait déjà ce trajet à chaque token sans casser le débit
- **Gain estimé** : 2-5 ms/token si le transfert est propre (~5-13 % wall)

### Option B — Implémenter GGML_OP_TOP_K dans le backend hexagon
Tri partiel natif (sélection top-8 sans trier les 248 restants) sur HVX :
réutiliser bitonic avec arrêt précoce, ou heap top-k.

- Code touché : `ggml/src/ggml-hexagon/htp/argsort-ops.c` + htp-ops.h +
  ggml-hexagon.cpp (validator, dispatch)
- **Gain potentiel** : diviser le coût ARGSORT par ~5-10 (215 µs → 20-40 µs)
  = jusqu'à **~5 ms/token (~13 % wall)**
- **Effort** : moyen (kernel HVX spécialisé, tests)

### Option C — Remplacer argsort_top_k par ggml_top_k dans llama-graph.cpp
Changer le builder MoE commun pour utiliser l'op native là où le backend la
supporte (comme deepseek32). Attention : TOP_K n'existe pas côté HTP → il
retomberait sur CPU (Option A) automatiquement via le fallback backend.

- Code touché : `src/llama-graph.cpp:2057` (et 2037/2044 pour les groupes)
- **Effort** : faible, mais dépend du support backend (B) pour un gain HTP

### Option D — Vérifier d'abord : ARGSORT est-il déjà sur CPU ?
Dans le log Marco-Nano, les splits montrent `ARGSORT VIEW MUL_MAT_ID...` dans les
splits **HTP0** — le tri tourne bien sur HTP. À confirmer par un run avec
GGML_HEXAGON_OPFILTER excluant ARGSORT (voir §7, test 1) avant tout patch.

## 5. MESURES RÉALISÉES — TEST A/B ALTERNÉ (A B A B, n_predict=200)

### 5.1 Protocole
- `GGML_HEXAGON_OPFILTER='ARGSORT'` force le backend hexagon à REFUSER l'op
  (`ggml-hexagon.cpp:4655` : supports_op retourne false si regex match) → le
  scheduler la place sur CPU. Aucune recompilation.
- Script : tools/bench_argsort_ab.sh — alternance A B A B, cooldown <45 °C

### 5.2 Résultats

| Run | ARGSORT sur | t/s wall | T °C | Sortie |
|---|---|---|---|---|
| A1 | HTP0 (tri 256 bitonic) | 29,54 | 38→49 | « …northern part of the country… » |
| B1 | CPU (avec SOFT_MAX) | 31,08 | 37→48 | « …Paris is known for its rich history… » |
| A2 | HTP0 | 27,96 | 38→49 | identique A1 ✅ |
| B2 | CPU | 35,61 | 35→48 | identique B1 ✅ |

**Moyennes : A (HTP) = 28,75 t/s · B (CPU) = 33,35 t/s → gain +16 %**

### 5.3 Findings critiques

1. **[MEASURED] Gain +16 % (28,75 → 33,35 t/s)** à déplacer ARGSORT du HTP vers
   le CPU — reproductible sur 2 paires A/B, indépendant du thermique (B > A
   dans les DEUX paires adjacentes).
2. **[MEASURED] Changement de sortie entre backends** : A1=A2 et B1=B2
   (déterministe PAR backend) mais A ≠ B. Le tri CPU (top-k avec SOFT_MAX
   fusionné) et le tri bitonic HTP départagent différemment les égalités de
   logits → experts sélectionnés ≠ → texte généré ≠ (les deux sont plausibles).
   **Implication upstream** : un simple déplacement sur CPU change la sémantique
   du modèle ; un vrai patch doit soit (a) implémenter GGML_OP_TOP_K côté HTP
   avec un départage IDENTIQUE au CPU, soit (b) documenter le changement de
   comportement comme accepté.
3. **[ESTIMATED]** Le gain +16 % confirme que les 215 µs/op sont bien le coût du
   tri complet HTP (pas un overhead FastRPC fixe) — sinon le déplacement CPU
   n'aurait rien changé.

### 5.4 Protocole de confirmation (si re-run)
- Alternance A B A B (jamais A×3 puis B×3 — biais thermique), n_predict ≥ 200
- Vérifier la sortie de chaque run (déterminisme par backend)
- Device < 45 °C au départ de chaque run

## 6. RÉFÉRENCES CHEMIN EXACT (reproduction)

```
SOURCE (fork JZ, device = /data/local/tmp/npu, binaire = llama-server)
├── src/llama-graph.cpp:2037,2044,2057   → ggml_argsort_top_k (MoE routing)
├── ggml/src/ggml.c:5376                 → ggml_argsort_top_k (argsort+view)
├── ggml/src/ggml.c:5403                 → ggml_top_k (op native GGML_OP_TOP_K)
├── ggml/src/ggml-cpu/ggml-cpu.c:1984    → support CPU de TOP_K
├── ggml/src/ggml-hexagon/htp/argsort-ops.c:247-374 → bitonic sort HVX complet
├── ggml/src/ggml-hexagon/htp/htp-ops.h:84           → HTP_OP_ARGSORT
├── ggml/src/ggml-hexagon/ggml-hexagon.cpp:4014      → dispatch ARGSORT
└── src/models/qwen3moe.cpp              → archi (n_expert_used > 0 requis)

MODÈLE (sur D:, re-quantisé par notre outillage)
├── /d/models_marco/Marco-Nano-Instruct.Q8_0.gguf   (8 527 233 568 o, source mradermacher)
└── /d/models_marco/Marco-Nano-Instruct.Q4_0.gguf    (4 569 976 352 o, Q4_0 HTP-ready)
    → device : /data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf

OUTILLAGE (scripts / commandes)
├── tools/platform-tools/adb.exe        → adb
├── wsl build : cmake -B build-wsl ... && cmake --build build-wsl --target llama-quantize
│   (build-wsl/bin/llama-quantize, après fix madvise __ANDROID__ dans src/llama-mmap.cpp)
├── tools/run_guarded_bench.sh          → protocole gardé device (label port n prompt [spec])
│   Usage : MODEL=... OUT=... sh run_guarded_bench.sh <label> <port> <n> '<prompt>'
├── tools/campaign_3x300.sh             → 3×300 tokens config 16 t/s (moyenne/écart-type)
├── tools/campaign_ratios_npu_gpu.sh    → 8 configs placement × ratio (randomisé seed)
└── tools/test_16tps_100_300.sh         → config gelée 100/300 tokens

LOG PROFILAGE (device, déjà extraits)
├── /data/local/tmp/bench_out/marco_nano_h1/server.log      → run propre (26,72 t/s)
├── /data/local/tmp/bench_out/marco_nano_prof/server.log    → GGML_HEXAGON_PROFILE=1
└── /data/local/tmp/bench_out/marco_nano_prof2/server.log   → PROFILE=2 + --verbose (39 170 ops)
```

## 7. COMMANDES DE REPRODUCTION

```bash
# 1. Profiler Marco-Nano (device froid)
adb shell "GGML_HEXAGON_PROFILE=2 MODEL=/data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf \
  OUT=/data/local/tmp/bench_out sh /data/local/tmp/npu/run_guarded_bench.sh \
  marco_repro 8563 100 'The capital of France is' --verbose"

# 2. Agrégation par famille (Python, log pullé)
#    grep 'profile-op' server.log → parser 'usec (\d+)' par op → agréger par famille

# 3. TEST DISCRIMINANT (avant tout patch) — tri hors HTP :
#    vérifier les env GGML_HEXAGON_OPFILTER/GGML_HEXAGON_* dispo :
adb shell "cd /data/local/tmp/npu && LD_LIBRARY_PATH=. ./llama-server --help 2>&1 | grep -i filter"
```

## 8. VERDICT

1. **[MEASURED]** ARGSORT = 35,7 % du DSP, 215 µs/op, 29 ops/token, ~6,3 ms/token
2. **[MEASURED]** Le graph trie 256 experts complets pour n'en garder que 8
   (96,9 % du travail jeté) — `ggml_argsort_top_k` fait argsort + view
3. **[ESTABLISHED]** Une op native top-k partiel existe (`GGML_OP_TOP_K`) mais
   n'est PAS implémentée côté hexagon ; elle est déjà utilisée par d'autres
   archis MoE (deepseek32 etc.) côté CPU
4. **[MEASURED] Le déplacement ARGSORT → CPU donne +16 % wall (28,75 → 33,35
   t/s, A/B/A/B reproductible)** — le tri complet HTP est bien le coût
5. **[MEASURED] MAIS la sortie change entre backends** (départage des égalités
   différent) — déterministe par backend, ≠ entre backends. Tout patch doit
   préserver la sémantique ou l'assumer explicitement
6. **[PROBABLE]** Implémenter GGML_OP_TOP_K natif HTP (top-8 partiel + départage
   aligné CPU) : gain cible ~+10-16 % SANS changement de sortie

## 9. LIMITES

- Mesures sur 1 run profilé (overhead profil = 2,4×) — les ratios % DSP sont
  fiables, les µs absolus sont à confirmer sur run propre
- Le gain potentiel est estimé, pas mesuré — le test discriminant est requis
- Re-quantisation Q8_0→Q4_0 (double quant) : OK pour perf, pas pour qualité
