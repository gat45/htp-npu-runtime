# Unified Reproducible Technical Report
## Qualcomm HTP v81 / GGML Scheduler / Quantization / Memory / Heterogeneous CPU-GPU-HTP / MTP
### Platform: OnePlus 15 — Snapdragon 8 Elite Gen 5 (SM8850)

**Consolidation date:** 2026-08-30  
**Primary device:** OnePlus 15 CPH2747  
**SoC:** Qualcomm Snapdragon 8 Elite Gen 5, SM8850  
**NPU:** Hexagon HTP v81  
**GPU:** Qualcomm Adreno 840 via OpenCL  
**Primary model:** Qwen3.5-9B D2-A family  
**Additional models:** Qwen3-8B Q4_K_M, Qwen3-8B Q4_0, Qwen3-4B Q4_0  
**Runtime family:** llama.cpp / GGML + Hexagon backend + OpenCL  
**Scope:** HTP v81, skel reproduction, scheduler behavior, quantization, memory traffic, heterogeneous execution, thermal behavior, allocator correctness, and MTP/speculative decoding.  
**Excluded:** APK integration/deployment path.

---

# 1. Executive Summary

This campaign moved beyond simple backend benchmarking and produced a coherent experimental model of LLM inference on Qualcomm HTP v81.

The central result is:

> **LLM performance on HTP cannot be predicted from TOPS, model size, quantization bit-width, or percentage of NPU offload alone.**

The observed performance is better described as:

```text
model architecture
        ↓
tensor/layer quantization
        ↓
available backend kernels
        ↓
actual operator support
        ↓
GGML scheduler and graph splits
        ↓
CPU / GPU / HTP placement
        ↓
layout conversion / RPC / synchronization
        ↓
DDR / mappings / cache / VTCM working set
        ↓
thermal state
        ↓
effective PP / TG
        ↓
speculative acceptance if MTP is enabled
```

The strongest experimentally supported findings are:

1. A deterministic HTP v81 hang was reproduced and removed by rebuilding the v81 DSP skel.
2. The rebuilt skel reports **8 HTP threads, 8 HVX units, HMX enabled, and 8 MiB VTCM**.
3. GGML scheduler fragmentation can dominate performance.
4. Q4_K_M and Q4_0/Q8_0 can favor completely different backends on the same SoC.
5. More HTP devices do **not** automatically improve throughput.
6. Forcing the `lm_head` onto HTP can be much slower than leaving it on the previous path.
7. Decode traffic for the studied 9B model is approximately **4.0–4.5 GB/token**, matching an independent 4.53 GB/token measurement.
8. Effective GGML memory throughput was measured at approximately **30.5 GB/s**.
9. MTP evolved through a clear chronology: **blocked → missing `eh_proj` identified → corrected 442-tensor model → functional MTP → 52.9% draft acceptance → ~16.2 effective t/s observed**.
10. The final MTP speedup is promising but still requires a strict repeated A/B validation using committed final tokens per wall-clock second.

---

# 2. Reproducibility State

## 2.1 Validated commits

The main validated code states are:

| Commit | Purpose |
|---|---|
| `859926e7` | pass 4.5 topological sort / HTP-first + compat24o + EINTERRUPTED handling |
| `1248f04f` | rebuilt v81 skel that removed the deterministic ADD-path hang |
| `505354ed` | Qwen3.5-9B GDN fix using `ggml_cont_4d` |
| `5291e12a` | configurable `opt_mm_rows` / lm-head row limit experiment |

## 2.2 Working tree caveat

At the time of consolidation, some work was not cleanly isolated into a single reproducible baseline.

Relevant modified/uncommitted areas included:

```text
ggml/src/ggml-hexagon/ggml-hexagon.cpp
ggml/src/ggml-backend.cpp
ggml/src/ggml-alloc.c
ggml/include/ggml-alloc.h
tests/test-alloc.cpp
tests/test-pass45-determinism.cpp
conversion/qwen.py
```

Therefore, every future benchmark intended as a reference result should store:

```text
git rev-parse HEAD
git status
git diff
model SHA256
skel SHA256
runtime/library hashes
```

The project should not use "same branch" as a substitute for "same binary state."

---

# 3. HTP v81 / DSP Skel — Hang Reproduction and Resolution

## 3.1 Initial failure

The original HTP v81 path repeatedly stalled on a deterministic graph segment.

Observed scheduler state:

```text
split 7/291
backend = HTP0
n_nodes = 3

ADD
RMS_NORM
MUL
```

Instrumentation identified the first HTP-side operation as an `ADD`, followed by `RMS_NORM` and `MUL`.

The host process remained active rather than crashing outright, consuming roughly one CPU core while waiting for DSP progress.

This behavior was therefore consistent with an AP-side wait/spin around the DSP response path.

---

## 3.2 Response-size mismatch

Before the final hang diagnosis, another incompatibility was observed:

```text
bad response size 24
```

This was associated with the `htp_opbatch_rsp` response format.

A compatibility path ("compat24o") was added so that the 24-byte response would no longer abort the execution immediately.

After this compatibility adjustment, execution progressed farther, but the deterministic HTP stall remained.

This distinction matters:

```text
bad response-size problem
        ≠
final ADD-path hang
```

The first issue had to be removed before the second could be observed cleanly.

---

# 4. Pass 4.5 — Scheduler Reordering Was Not the Root Cause

A custom **pass 4.5** topological ordering had been introduced to prefer HTP-friendly execution order.

Because it changed graph ordering, it was a reasonable suspect.

The key comparison was:

```text
pass 4.5 enabled  → hang
pass 4.5 disabled → same hang
```

Therefore:

> **Pass 4.5 is not required to reproduce the HTP v81 hang.**

It may still alter graph placement and performance, but the hang itself cannot be explained solely by that scheduler transformation.

---

# 5. Rebuilding the v81 Skel

The DSPQueue skel was rebuilt specifically for v81 using:

```text
Qualcomm Hexagon SDK 6.6.0.0
Hexagon clang 19.0.07
HEXAGON_ARCH=v81
DSP_VERSION=v81
GGML_HEXAGON_USE_MEMPOOL=OFF
```

The generated library was approximately:

```text
libggml-htp-v81.so
~734,920 bytes
```

A critical build detail was the manual definition of:

```text
PREBUILT_LIB_DIR
```

Without it, CMake could fail inside `hexagon_fun.cmake`.

A FastRPC/mempool variant was also buildable using:

```text
GGML_HEXAGON_USE_MEMPOOL=ON
```

with a slightly larger skel.

---

# 6. A/B Evidence for the Skel Fix

## 6.1 Old skel

```text
CPU MUL_MAT
    ↓
HTP ADD
    ↓
split 7/291
    ↓
DSP response path stalls
    ↓
host waits
    ↓
HANG
```

## 6.2 Rebuilt v81 skel

```text
CPU MUL_MAT
    ↓
HTP ADD
    ↓
RMS_NORM
    ↓
MUL
    ↓
remaining graph
    ↓
291/291 splits complete
```

This is one of the strongest causal results in the entire project:

> **Changing the skel changes the outcome from a deterministic hang to successful graph traversal.**

What is **not** yet proven:

- the exact DSP instruction responsible;
- the exact kernel responsible;
- the minimal source or binary delta that causes the fix;
- whether every SM8850 firmware build behaves identically;
- whether every HTP v81 SoC benefits from the same rebuild.

The correct scientific statement is therefore:

> The rebuilt v81 skel removed the deterministic hang on the tested OnePlus 15 / SM8850 platform.

---

# 7. HTP v81 Hardware Characterization

The rebuilt skel exposed:

```text
HTP0 hwinfo:
threads 8
hvx 8
hmx 1
vtcm 8 MB
```

Therefore the tested SM8850 HTP v81 configuration exposes:

- **8 hardware threads**
- **8 HVX**
- **HMX present**
- **8 MiB VTCM**

This is a direct device-side runtime observation and should be considered one of the highest-confidence hardware findings in the campaign.

---

# 8. GGML Scheduler — Why Placement Matters

GGML does not simply "run the model on the NPU."

It builds and partitions a graph:

```text
GGML graph
   ↓
scheduler
   ↓
split 0 → backend A
split 1 → backend B
split 2 → backend C
...
```

Every backend transition may introduce:

```text
synchronization
buffer management
layout conversion
copy or mapping operations
RPC/control overhead
device reconfiguration
```

Therefore:

```text
high NPU offload %
```

does not imply:

```text
high NPU time share
```

and does not imply:

```text
high end-to-end throughput
```

---

# 9. Direct Operation Distribution — D2-A HTP0

For D2-A on HTP0, scheduler logging showed:

| Backend | MUL_MAT | GDN | SSM | FLASH_ATTN |
|---|---:|---:|---:|---:|
| HTP0 | **41,416** | 4,008 | 4,008 | 1,336 |
| CPU | 167 | 0 | 0 | 0 |
| GPU | 0 after prefill | 0 | 0 | 0 |

This is important because it proves that the D2-A HTP result is not simply a requested `-ngl 99` configuration.

The graph logs show that the HTP actually performs the overwhelming majority of the heavy supported operations.

Therefore:

> The measured HTP performance is linked to real HTP execution, not just scheduler intent.

---

# 10. Qwen3.5-9B Source Anatomy

The source model inspection found:

```text
774 tensors
17.92 GiB BF16
32 layers
```

Architecture:

- 8 full-attention layers:
  - 3
  - 7
  - 11
  - 15
  - 19
  - 23
  - 27
  - 31
- 24 linear-attention / SSM layers
- `blk.0` is special and contains both branches
- `attn_output_gate=true`
- `tie_word_embeddings=false`
- separate embedding and `lm_head`
- MTP metadata/source support present

Approximate parameter distribution:

```text
FFN                  54.6%
attention            23.8%
lm_head + embedding  21.2%
```

The BF16 `lm_head` alone is approximately:

```text
1.89 GiB
```

and the embedding is another approximately:

```text
1.89 GiB
```

---

# 11. The blk.0 Hotspot

`blk.0` differs from a standard block because it contains:

```text
linear_attn branch
+
self_attn branch
```

Approximate BF16 size:

```text
blk.0 ≈ 0.80 GiB
```

This is roughly twice the size of many ordinary blocks.

Projected Q4_0 traffic:

```text
blk.0 ≈ 212 MB/token
```

versus roughly:

```text
standard linear block ≈ 108 MB/token
```

This makes `blk.0` a natural target for:

- gate analysis;
- differential quantization;
- layer-specific placement;
- branch pruning investigation;
- memory-traffic profiling.

---

# 12. Layer-Wise Precision Planning

The precision planner does not use uniform quantization.

The proposed allocation is approximately:

```text
MLP / experts        → W4A16
SSM / linear attn    → W4A16
sensitive attention  → W8A16
QKV / gates          → W8A16
norms                → BF16
lm_head              → W8A16
```

Representative per-layer reductions:

```text
root      4750 → 1247 MB
blk.0      817 →  272 MB
linear     417 →  128 MB
full attn  400 →  144 MB
```

The planner total is:

```text
18,348 MB
    ↓
5,619 MB

theoretical reduction ≈ 69.4%
```

This is a theoretical traffic/precision allocation result.

The associated `ΣΔPPL = 223.20` must **not** be interpreted as a measured final model perplexity.

A proper validation still requires:

- full-model PPL;
- task benchmarks;
- generation comparison;
- layer-wise ablations;
- output divergence analysis.

---

# 13. Multi-Backend Precision Planner

A second traffic-aware planner compared backend-specific precision policies.

Approximate planner outputs:

| Backend | BF16 traffic | Planned traffic | Reduction | ΣPPL proxy |
|---|---:|---:|---:|---:|
| GGML | 16,408 MB/token | 6,825 | 58.4% | 50.25 |
| QAIRT | 16,408 MB/token | 8,680 | 47.1% | 22.65 |
| GPU | 16,408 MB/token | 7,117 | 56.6% | 56.20 |

The planner therefore suggested that QAIRT could preserve more precision while still reducing traffic significantly.

However:

> These are planner outputs, not measured end-to-end final-model quality scores.

---

# 14. Quantization Determines Backend Suitability

One of the strongest empirical findings is that quantization format changes backend suitability.

## 14.1 Q4_K_M

For the tested Qwen3-8B Q4_K_M path:

```text
Q4_K_M MUL_MAT
    ↓
heavy HTP path not executed
    ↓
CPU fallback
    ↓
fragmentation
    ↓
poor heterogeneous performance
```

GPU OpenCL performs much better.

## 14.2 Q4_0 / Q8_0

For D2-A:

```text
MLP / SSM = Q4_0
attention = Q8_0
norms = F16
```

the HTP path is much more effective.

The correct conclusion is **not**:

> Q4_0 is universally faster than Q4_K_M.

The correct conclusion is:

> Quantization changes operator/kernel compatibility, which changes scheduler placement, which changes the optimal backend.

---

# 15. Qwen3-8B Q4_K_M — Backend Results

Measured decode results:

| Configuration | TG16 |
|---|---:|
| default automatic | 6.72 t/s |
| GPU-only | **9.28 t/s** |
| 100% HTP | ~4.35–4.55 t/s |
| 3 HTP | **0.96 t/s** |

GPU-only is approximately:

```text
9.28 / 6.72 - 1 ≈ +38%
```

better than the default automatic configuration.

---

# 16. The 3-HTP Collapse

The 3-HTP experiment initially looked like a simple capacity/spill failure.

Detailed scheduler logging provided a stronger explanation.

Observed split distribution:

| Backend | Splits |
|---|---:|
| CPU | 10,962 |
| HTP0 | 3,828 |
| HTP1 | 3,828 |
| HTP2 | 3,219 |
| OpenCL | 87 |

Approximately:

```text
10,875 CPU MUL_MAT
```

were observed, while:

```text
HTP MUL_MAT = 0
```

for the problematic Q4_K_M path.

This gives a much stronger causal chain:

```text
Q4_K_M
    ↓
heavy MUL_MAT unsupported on HTP path
    ↓
CPU fallback
    ↓
~10,875 CPU MUL_MAT fragments
    ↓
HTP devices execute smaller fragments
    ↓
CPU ↔ HTP/OpenCL synchronization
    ↓
massive heterogeneous fragmentation
    ↓
0.96 t/s
```

Therefore:

> The 0.96 t/s result should not be explained only as "the model does not fit HTP memory."

Scheduler fragmentation is directly visible in the logs.

---

# 17. Large OpenCL Blocks vs Small HTP Blocks

A notable 3-HTP trace contained a large OpenCL region:

```text
split 1
backend = OpenCL
n_nodes = 155
```

containing operations such as:

```text
RMS_NORM
MUL_MAT
gate/up/down
GLU
ROPE
FLASH_ATTN_EXT
```

By contrast, HTP often received much smaller regions.

This matters because:

```text
large contiguous block
```

typically pays fewer boundary costs than:

```text
many tiny alternating backend blocks
```

---

# 18. Qwen3-4B — Positive Multi-HTP Scaling

A smaller Qwen3-4B Q4_0 model showed the opposite behavior:

| HTP configuration | TG16 |
|---|---:|
| 1 HTP | 13.71 |
| 2 HTP | 14.59 |
| 3 HTP | **18.86** |

Therefore:

> Multi-HTP is not intrinsically bad.

The correct conclusion is workload-dependent:

```text
small model + supported quantization + useful partition
    ↓
positive HTP scaling

larger model + unsupported heavy path + fragmentation
    ↓
negative HTP scaling
```

---

# 19. D2-A — HTP-Favorable Configuration

D2-A uses approximately:

```text
MLP / SSM   Q4_0
attention   Q8_0
norms       F16
```

Measured decode:

| Configuration | TG16 |
|---|---:|
| HTP0 cold (~41°C) | **8.90** |
| HTP0 warm | 8.22–8.37 |
| HTP-front layer split | 8.14–8.58 |
| default automatic | 7.02 |
| GPU | ~6.5 |

Cold HTP0 therefore beats the automatic scheduler by approximately:

```text
8.90 / 7.02 - 1 ≈ +26.8%
```

This is the inverse of the Q4_K_M result.

Thus:

```text
Q4_K_M → GPU favored
Q4_0/Q8_0 D2-A → HTP favored
```

is not a contradiction.

It is direct evidence that:

> **Backend optimality depends on model structure, quantization, and real operator support.**

---

# 20. Layer-Split Experiments

The HTP/GPU split ratio alone did not predict performance.

Cold D2-A sweep:

| HTP/GPU split | HTP-side result / overall observation |
|---|---:|
| 0.1 / 0.9 | ~8.3 |
| 0.2 / 0.8 | 8.46–8.58 |
| 0.5 / 0.5 | 7.35–7.90 |
| 0.8 / 0.2 | 8.01–8.38 |
| 0.9 / 0.1 | ~8.3 |

Default:

```text
7.02 t/s
```

The strongest stable split in this sweep was around:

```text
20% HTP / 80% GPU
≈ 8.5 t/s
```

but the important result is not the ratio.

The key result is:

> **Boundary location matters at least as much as aggregate backend percentage.**

A 50/50 split can be worse than both more HTP-heavy and more GPU-heavy placements.

---

# 21. Boundary Cost Model

A useful latency model is:

```text
Total latency =
Σ compute_cost(layer, backend)
+ Σ transfer_cost(boundary)
+ Σ synchronization_cost(boundary)
+ spill_penalty
```

Therefore, a placement optimizer should not minimize:

```text
HTP percentage
```

or maximize:

```text
NPU percentage
```

It should optimize:

```text
layer placement
+ backend compute cost
+ boundary cost
+ memory pressure
+ spill risk
+ thermal state
```

---

# 22. Large Contiguous Regions Are Preferable

Preferred:

```text
HTP ███████████████
          │
          │ one boundary
          ▼
GPU ███████████████████
```

Avoid:

```text
HTP → GPU → HTP → GPU → HTP → GPU
```

because each transition can add:

- synchronization;
- buffer management;
- memory/layout movement;
- scheduler overhead;
- cache effects.

This principle is important for both performance optimization and thermal scheduling.

---

# 23. Memory Traffic — 9B Decode

The safetensors-based model plus device measurements converge on:

```text
~4.0–4.5 GB/token
```

An independent measured value was:

```text
4.53 GB/token
```

This is strong agreement between:

- model anatomy;
- quantization assumptions;
- runtime measurement.

This supports using:

```text
bytes/token × tokens/s
```

as a useful effective-memory-throughput metric.

---

# 24. Effective GGML Bandwidth

Measured values:

```text
TG = 6.74 t/s
traffic = 4.53 GB/token
```

Therefore:

```text
6.74 × 4.53 ≈ 30.5 GB/s
```

So:

> **Effective GGML bandwidth ≈ 30.5 GB/s**

This value is marked as measured in the planner.

---

# 25. QAIRT Bandwidth — Evidence Level

The planner also used:

```text
QAIRT ≈ 74 GB/s
```

but explicitly labeled it:

```text
estimated from RAG / not re-measured
```

Therefore:

### Measured

```text
GGML ≈ 30.5 GB/s
```

### Not yet revalidated experimentally

```text
QAIRT ≈ 74 GB/s
```

The approximate 2.4× ratio must therefore **not** be presented as a definitive measured A/B result.

---

# 26. lm_head Traffic

The model source contains a separate BF16:

```text
lm_head ≈ 1.89 GiB
```

A Q4_0 projection gives approximately:

```text
~504 MB/token
```

while runtime packing measurements suggested approximately:

```text
~795 MB/token
```

depending on representation/path.

This makes the `lm_head` one of the largest individual decode traffic contributors.

---

# 27. lm_head HTP Offload Regression

An experiment increased the row limit to allow much more of the `lm_head` onto HTP.

Result:

```text
normal D2-A HTP0 path → 8.90 t/s
lm_head forced HTP     → 2.06 t/s
```

This is a major counterexample to simplistic offload logic.

It demonstrates:

> **Removing a CPU-side operation or increasing NPU offload can make the full system dramatically slower.**

Possible causes include:

- kernel shape suitability;
- large-vocabulary output projection characteristics;
- transfer/repacking;
- working-set pressure;
- scheduler disruption.

The measurement demonstrates the regression; it does not yet isolate one single root cause.

---

# 28. VTCM — What 8 MiB Means and Does Not Mean

The HTP reports:

```text
8 MiB VTCM
```

This does not imply that multi-gigabyte model weights reside in VTCM.

The relevant model is:

```text
DDR
 ↓
tile / working set
 ↓
VTCM
 ↓
HVX / HMX compute
```

Performance depends on:

- tiling;
- reuse;
- tensor lifetime;
- spill/fill;
- bus topology;
- multicast;
- scheduling order.

The VTCM size is therefore only one variable.

Two SoCs with the same nominal VTCM size can still show different spill behavior because their interconnect and cost model differ.

---

# 29. Qualcomm HTP Compiler Reverse-Engineering Context

The reverse-engineering notes attribute several important mechanisms to the Qualcomm HTP preparation/compiler stack.

These include:

## 29.1 VTCM placement optimization

The compiler was described as using a MILP formulation solved with HiGHS to minimize transferred bytes:

```text
spill to DDR
+
fill from DDR
+
inter-core transfers
```

## 29.2 Scheduling / lifetime optimization

The compiler analysis describes:

- priority BFS;
- topological ordering;
- producer/consumer proximity;
- lifetime-aware tensor ordering;
- fragmentation minimization.

## 29.3 Hextimate

A hidden analytical performance model was described as evaluating best/worst overlap scenarios using a roofline-like memory model:

```text
time = bytes / (channels × width × efficiency × frequency)
```

with additional cost tables for:

- integer vs floating-point compute;
- multicast;
- fast DDR;
- KV cache;
- weights;
- FlashAttention;
- MoE;
- RoPE.

These compiler findings are useful explanatory context, but they should remain clearly distinguished from direct device measurements.

---

# 30. FastRPC / Mempool vs DSPQueue

The project experimented with both:

```text
DSPQueue
```

and:

```text
FastRPC / mempool
```

A mempool/graph-dispatch path reached:

```text
n_splits = 1
```

in an experiment, showing the potential value of more consolidated dispatch.

However, at that stage it was not yet loading cleanly in the normal `llama-bench` path.

Therefore it should be classified as:

```text
architecturally promising
but not yet a stable production baseline
```

The wider JZ multi-model data also showed that FastRPC did not win universally.

Across an 8-model comparison, it won TG on 5 models and lost on 3.

This reinforces:

> RPC/memory architecture matters, but there is no universal backend winner.

---

# 31. 4 GiB / Mapping Interpretation

The campaign must avoid reducing memory behavior to a single statement such as:

```text
HTP is 32-bit, therefore max model = 4 GiB
```

These are distinct concepts:

- pointer width;
- DSP virtual address space;
- individual mapping size;
- total mapped memory;
- IOVA;
- scatter-gather;
- FastRPC mapping;
- mempool design;
- per-session memory;
- multiple buffers;
- model file size;
- effective weight residency.

The observed >4 GiB behavior in FastRPC/JZ must therefore be interpreted as a mapping/design/runtime issue unless the underlying architectural limit is independently proven.

---

# 32. Thermal State — Methodology Correction

Earlier benchmark sweeps did not always control thermal state adequately.

Observed states included:

```text
GPU ≈ 68–70°C
DDR ≈ 72°C
GPU utilization ≈ 93%
```

These runs cannot be treated as clean A/B comparisons against cold runs.

The project therefore introduced a strict distinction:

```text
COLD
WARM
THERMALLY CONTAMINATED
```

---

# 33. Correct Thermal Signal

A thermal-trip threshold such as:

```text
cpu-hw-trip = 95°C
```

is not an operating-temperature reading.

For GPU thermal control, the relevant signal was:

```text
gpuss
```

The benchmark methodology should therefore use real thermal-zone measurements rather than trip-point metadata.

---

# 34. Cold-Start Benchmark Protocol

A comparable benchmark should:

1. stop the previous workload;
2. allow cooling;
3. verify the relevant thermal zone;
4. start only when GPU temperature is below ~55°C;
5. perform controlled warm-up if required;
6. record temperature before the run;
7. run the benchmark;
8. record temperature during and after the run;
9. record throughput;
10. cool before the next candidate.

Any run without this control should be labeled explicitly:

```text
WARM
```

or:

```text
THERMALLY CONTAMINATED
```

---

# 35. Thermal Effect on D2-A

Measured HTP0 performance:

```text
~41°C → 8.90 t/s
warm  → 8.22–8.37 t/s
```

Approximate degradation:

```text
-6% to -8%
```

Therefore:

> Thermal state is a performance variable, not merely a power-management variable.

---

# 36. Thermal Governor Concept

A practical hysteresis rule was developed:

```text
GPU ≥ 60°C → move toward HTP-heavy mode
GPU ≤ 50°C → GPU may become preferred again
50–60°C    → keep previous state
```

This avoids:

```text
GPU → HTP → GPU → HTP
```

oscillation near a single threshold.

A more robust implementation should also include:

- minimum dwell time;
- N consecutive threshold samples;
- transition logging;
- switching-cost estimation;
- safe graph boundaries.

---

# 37. Thermal-Aware Layer Placement

The longer-term policy is not simply:

```text
GPU forever
```

or:

```text
HTP forever
```

A better strategy may be:

```text
GPU cool
   ↓
GPU-heavy placement
   ↓
GPU warms
   ↓
move contiguous boundary toward HTP
   ↓
GPU cools
   ↓
slowly move boundary back
```

The key is to move **large contiguous execution regions**, not rapidly alternate individual operators.

---

# 38. Allocator Correctness Bug

A separate GGML investigation identified a real allocator correctness problem.

An adversarial test constructed:

```text
graph A → reservation
graph B → allocation
```

with:

- same number of nodes;
- same number of leaves;
- same tensor sizes;

but different:

- topology;
- tensor lifetimes.

The old allocator could accept the stale memory plan.

Observed corruption included:

```text
m0.data == m1.data
```

while both tensors were simultaneously live.

This demonstrates:

> **Equal tensor sizes do not imply equal valid memory plans.**

This finding is directly relevant to dynamic heterogeneous scheduling because changing backend placement changes graph topology and lifetime structure.

---

# 39. Allocator Fingerprint Diagnostic

A debug signature based on FNV-1a was added.

The signature included properties such as:

- operation;
- tensor dimensions;
- view source;
- buffer ID;
- source tensors.

It was generated during reservation and checked during later allocation.

On mismatch, the system logs an error.

Important:

```text
fingerprint mismatch
```

is only a detector.

It does **not** prove that a new memory plan has been generated or is valid.

---

# 40. Regression Tests for Allocator / Pass 4.5

Two regression-test directions were created.

## 40.1 Adversarial topology-change test

Validates:

```text
stale graph plan → corruption detected
```

and checks a mismatch counter for the adversarial graph.

It also checks:

```text
identical graph → mismatch_count == 0
```

## 40.2 Pass-4.5 determinism test

The test compares old vs new pass-4.5 behavior over approximately:

```text
450 graphs
```

and checks:

- topological validity;
- deterministic reservation ordering;
- deterministic compute ordering.

This matters because scheduler transforms and allocator reuse are coupled.

---

# 41. Why Allocator Correctness Matters to Heterogeneous Scheduling

When backend placement changes:

```text
same model
```

does not necessarily mean:

```text
same graph
```

because:

- backend boundaries move;
- views/buffers may change;
- lifetimes change;
- reservations change;
- MTP draft/verify paths differ.

Therefore stale memory plans are especially dangerous for:

- MTP;
- HTP/GPU layer splitting;
- dynamic scheduling;
- thermal switching;
- speculative draft/verify execution.

---

# 42. MTP — Chronology Must Be Preserved

The MTP history is one of the most important examples of why old conclusions must not be overwritten by new ones.

---

# 43. MTP Phase M0 — Source Support Exists

The source model inspection identified MTP-related metadata/support:

```text
mtp_num_hidden_layers = 1
model-mtp-restored.safetensors
```

Therefore MTP existed conceptually/source-side.

This did not yet imply that the converted runtime model was valid.

---

# 44. MTP Phase M1 — Blocked

At an earlier stage:

```text
D2-A-MTP.gguf
    ↓
some nextn-related tensors present
    ↓
eh_proj.weight missing
    ↓
model cannot load correctly
```

The model was therefore considered unusable.

That conclusion was correct for that exact artifact.

It must remain in the history.

---

# 45. MTP Phase M2 — Corrected Model

A later correction produced:

```text
D2-A-MTP
442 tensors
eh_proj included
```

The chronology becomes:

```text
MTP source support
    ↓
incomplete conversion
    ↓
missing eh_proj
    ↓
MTP blocked
    ↓
conversion/restoration corrected
    ↓
442 tensors + eh_proj
    ↓
model loads
```

---

# 46. MTP Phase M3 — First Functional Speedup

An earlier working MTP campaign produced approximately:

```text
baseline = 6.00 t/s
MTP      = 8.29 t/s
```

Approximate gain:

```text
+38.2%
```

This should remain documented as an intermediate validated stage.

---

# 47. MTP Phase M4 — Successful llama-server Path

The final functional path used:

```text
llama-server --spec-type draft-mtp
```

rather than:

```text
llama-cli
```

The CLI path could loop and produce extremely large logs, while the server path successfully executed MTP.

Therefore the current valid reproduction path is:

```text
llama-server + draft-mtp
```

---

# 48. MTP Phase M5 — Acceptance Measurements

Observed:

```text
draft acceptance = 52.9%
accepted draft tokens = 9 / 17
mean draft length = 2.50 tokens
verification latency = 154 ms/token
verification throughput = 6.48 t/s
```

These values demonstrate that speculative decoding is genuinely active.

The draft is not merely loading; it is proposing tokens that are being accepted.

---

# 49. Effective MTP Throughput

A current effective-throughput estimate is:

```text
6.48 × 2.50 ≈ 16.2 effective tokens/s
```

This is substantially above the non-MTP D2-A HTP0 baseline:

```text
8.90 t/s
```

The current record is therefore approximately:

```text
~16.2 effective t/s
```

However, this value must be labeled:

> **effective speculative throughput estimate/measurement**

and not confused with:

```text
raw target-model verification throughput
```

---

# 50. MTP — What Still Needs Strict Validation

The final MTP speedup must be validated with repeated matched A/B runs.

Each run should record:

```text
final committed tokens
drafted tokens
accepted tokens
acceptance ratio
mean accepted draft length
wall-clock duration
final committed tokens / wall-clock second
temperature start
temperature end
temperature peak
backend configuration
model hash
code commit
skel hash
```

Compare:

```text
MTP OFF
vs
MTP ON
```

with:

- same model;
- same prompt;
- same generated token count;
- same backend;
- same thread count;
- same thermal window;
- same code state;
- at least 5 repeated runs.

The primary metric should be:

```text
final committed tokens / wall-clock second
```

---

# 51. MTP and Long Context

The MTP draft path may pay a significant KV-cache cost.

For hybrid/linear-attention models, a full-attention draft can become increasingly expensive with context length.

A future optimization candidate is:

```text
windowed draft attention
+
full target verification
```

This is currently an optimization hypothesis, not yet a proven device result.

---

# 52. Current Empirical Performance Map

| Model / Configuration | Preferred path | Best observed |
|---|---|---:|
| Qwen3-4B Q4_0 | multi-HTP | **18.86 t/s** |
| Qwen3-8B Q4_K_M | GPU OpenCL | **9.28 t/s** |
| Qwen3.5-9B D2-A Q4_0/Q8_0 | HTP0 cold | **8.90 t/s** |
| D2-A + MTP | HTP + speculative | **~16.2 effective t/s** |

These are not directly comparable as one universal benchmark because the models differ.

They should be treated as workload-specific optima.

---

# 53. Results That Must Not Be Mixed

Do not combine:

```text
cold
```

with:

```text
warm
```

Do not combine:

```text
single-run peak
```

with:

```text
multi-run mean
```

Do not combine:

```text
raw verification t/s
```

with:

```text
MTP effective t/s
```

Do not compare two model families as if they were an A/B backend benchmark.

Do not compare:

```text
same filename / different hash
```

as if the model were identical.

---

# 54. Current Evidence Levels

## Strong / directly reproduced

- deterministic old-skel hang on the tested v81 platform;
- rebuilt skel removes the hang;
- HTP v81 hwinfo: 8 threads, HVX 8, HMX 1, VTCM 8 MiB;
- D2-A HTP0 actually executes large numbers of HTP operations;
- Q4_K_M 3-HTP path produces massive CPU MUL_MAT fallback;
- 3 HTP can collapse to 0.96 t/s on that workload;
- Qwen3-4B can positively scale to 3 HTP;
- D2-A HTP0 can reach 8.90 t/s cold;
- GPU-only Q4_K_M can reach 9.28 t/s;
- lm_head HTP experiment regresses to ~2.06 t/s;
- decode traffic is consistent with ~4.0–4.5 GB/token;
- GGML effective bandwidth ~30.5 GB/s;
- MTP functional path exists;
- draft acceptance 52.9%;
- allocator stale-plan corruption can be detected with topology-changing graphs.

## Strong but platform/runtime specific

- Q4_K_M → GPU preferred;
- Q4_0/Q8_0 D2-A → HTP preferred;
- layer-boundary placement matters;
- large contiguous backend blocks outperform fragmented alternation;
- thermal state changes throughput by ~6–8%.

## Promising but still requiring stronger validation

- ~16.2 effective t/s as a stable repeated MTP result;
- ~1.8× MTP gain versus 8.90 t/s baseline;
- QAIRT ~74 GB/s effective bandwidth;
- QAIRT / GGML ~2.4× effective bandwidth gap;
- final layer-wise PPL/quality impact;
- exact cause of v81 old-skel hang;
- universal benefit of the skel rebuild across all v81 systems;
- general FastRPC superiority over DSPQueue;
- long-context Windowed-MTP benefit on this exact model.

---

# 55. Key Counterexamples Established by the Campaign

The campaign produced several valuable counterexamples to common optimization assumptions.

## Counterexample 1

```text
more HTP devices ≠ more throughput
```

Evidence:

```text
Qwen3-8B Q4_K_M
3 HTP → 0.96 t/s
```

while:

```text
Qwen3-4B Q4_0
3 HTP → 18.86 t/s
```

## Counterexample 2

```text
more NPU offload ≠ faster
```

Evidence:

```text
lm_head forced HTP → 2.06 t/s
normal path         → 8.90 t/s
```

## Counterexample 3

```text
lower-bit quantization ≠ automatically faster
```

because backend support and repacking/fallback behavior dominate.

## Counterexample 4

```text
same model size ≠ same optimal backend
```

because quantization and operator compatibility can completely change placement.

## Counterexample 5

```text
same tensor sizes ≠ same valid allocator plan
```

because graph topology and tensor lifetimes matter.

---

# 56. Unified Performance Model

A better conceptual model is:

\[
Perf =
f(
architecture,
quantization,
kernel\ support,
scheduler,
graph\ topology,
placement,
boundary\ cost,
RPC,
layout,
memory\ traffic,
VTCM,
thermal\ state,
speculative\ acceptance
)
\]

rather than:

\[
Perf \propto TOPS
\]

or:

\[
Perf \propto NPU\ offload\ percentage
\]

or:

\[
Perf \propto 1 / bitwidth
\]

---

# 57. Recommended Benchmark Record

Every future benchmark should store:

```text
timestamp
device model
SoC
firmware fingerprint
kernel version
model filename
model SHA256
quantization
model size
runtime version
git commit
git diff status
skel SHA256
backend
HTP device count
GPU backend
CPU thread count
layer assignment
graph split counts
operator distribution
prompt tokens
generated tokens
PP t/s
TG t/s
temperature start
temperature end
temperature peak
GPU utilization
DDR temperature
warmup policy
cooldown policy
backend transitions
spill state
memory traffic estimate
```

For MTP additionally:

```text
draft acceptance
drafted tokens
accepted tokens
mean accepted length
verification latency
verification throughput
effective committed tokens/s
```

---

# 58. Priority Roadmap

## P0 — Freeze reproducibility

- commit all validated changes;
- separate experimental branches;
- hash every model;
- hash every skel;
- save exact command lines;
- repeat cold baselines.

## P1 — Final MTP A/B

Repeat:

```text
MTP OFF vs MTP ON
```

under matched thermal and runtime conditions.

Goal:

```text
stable final committed tokens/s
```

## P2 — Layer cost model

Measure:

```text
HTP latency per layer
GPU latency per layer
CPU fallback latency
boundary transfer cost
synchronization cost
thermal sensitivity
spill risk
```

## P3 — Contiguous dynamic boundary

Optimize:

```text
layers 0..N → HTP
layers N+1..L → GPU
```

instead of arbitrary per-layer assignments.

## P4 — Thermal-aware placement

Use:

```text
quantization
+
layer cost
+
thermal state
+
memory pressure
+
switch cost
```

to move the boundary only when expected gains exceed switching overhead.

## P5 — Quality validation

Measure:

- PPL;
- task accuracy;
- generation similarity;
- quantization-induced degradation;
- any `relaxed_precision_cast` effects.

## P6 — Memory path

Re-measure:

```text
GGML effective bandwidth
QAIRT effective bandwidth
lm_head traffic
KV traffic
mappings
spill/fill
```

with identical device conditions.

---

# 59. Master Chronology

```text
Initial HTP v81 runtime
│
├─ old skel
│   └─ deterministic ADD-path hang at split 7/291
│
├─ 24-byte response mismatch identified
│   └─ compat24o added
│
├─ EINTERRUPTED / queue behavior investigated
│
├─ pass 4.5 tested
│   └─ hang remains with pass 4.5 disabled
│
├─ v81 skel rebuilt
│   └─ graph completes 291/291 splits
│
├─ hwinfo confirmed
│   ├─ 8 threads
│   ├─ HVX 8
│   ├─ HMX 1
│   └─ VTCM 8 MiB
│
├─ scheduler profiling
│   ├─ D2-A mostly real HTP execution
│   └─ Q4_K_M 3-HTP dominated by CPU MUL_MAT fallback
│
├─ heterogeneous experiments
│   ├─ Qwen3-4B scales positively to 3 HTP
│   ├─ Qwen3-8B Q4_K_M GPU wins
│   ├─ Qwen3-8B 3 HTP collapses
│   └─ D2-A Q4_0/Q8_0 HTP wins
│
├─ layer split experiments
│   └─ boundary position shown to matter
│
├─ lm_head experiment
│   └─ forcing HTP causes major regression
│
├─ model anatomy
│   ├─ 774 tensors
│   ├─ 17.92 GiB BF16
│   ├─ 32 layers
│   ├─ blk.0 dual branch
│   └─ separate 1.89 GiB lm_head
│
├─ memory model
│   ├─ ~4.0–4.5 GB/token
│   ├─ independent 4.53 GB/token match
│   └─ ~30.5 GB/s GGML effective BW
│
├─ layer-wise precision planner
│   └─ theoretical 18,348 → 5,619 MB traffic reduction
│
├─ allocator investigation
│   ├─ stale graph reservation reproduced
│   ├─ overlapping live tensors observed
│   ├─ graph fingerprint diagnostic added
│   └─ regression tests created
│
└─ MTP
    ├─ source MTP metadata present
    ├─ converted model incomplete
    ├─ eh_proj missing
    ├─ MTP blocked
    ├─ corrected model
    ├─ 442 tensors + eh_proj
    ├─ MTP loads
    ├─ first working result 6.00 → 8.29 t/s
    ├─ llama-server path validated
    ├─ 52.9% draft acceptance
    ├─ mean draft length 2.50
    ├─ verification 6.48 t/s
    └─ ~16.2 effective t/s observed
         ↓
      strict repeated final A/B still required
```

---

# 60. Final Conclusions

The campaign establishes that inference on Qualcomm HTP v81 is fundamentally a **heterogeneous systems problem**, not simply an accelerator benchmark.

The most important experimentally supported conclusions are:

1. **The v81 skel matters at the binary/runtime level.** A deterministic hang was removed by a rebuild.
2. **Quantization determines kernel/backend suitability.**
3. **The scheduler determines whether theoretical NPU offload becomes useful execution or fragmented fallback.**
4. **CPU fallback can dominate an apparently NPU-heavy configuration.**
5. **More HTP is workload-dependent, not universally beneficial.**
6. **Large contiguous backend regions are preferable to rapid backend alternation.**
7. **Memory traffic per token is a first-order decode variable.**
8. **The lm_head is a major traffic contributor, but moving it to HTP can be counterproductive.**
9. **Thermal state changes throughput enough to invalidate uncontrolled comparisons.**
10. **Dynamic thermal scheduling must include hysteresis and switching cost.**
11. **Allocator plans depend on graph topology and lifetimes, not only tensor sizes.**
12. **MTP changes the optimization target from raw verification throughput to effective committed tokens/s.**
13. **The MTP chronology itself is evidence: blocked → corrected → functional → accepted drafts → effective speedup.**
14. **The current ~16.2 effective t/s result is the strongest throughput result in the campaign, but its final speedup still needs a strict repeated A/B confirmation.**

The optimization problem is therefore no longer:

> "Which backend is fastest?"

It is:

> **Which backend should execute which large graph region, for which quantization and model structure, under which memory and thermal state, with which synchronization cost, while maximizing effective committed tokens per second?**

That is the unified technical conclusion of the project as of 2026-08-30.
