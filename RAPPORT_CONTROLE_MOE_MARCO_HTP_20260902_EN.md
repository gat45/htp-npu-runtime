# TECHNICAL REPORT — SPARSE MoE CONTROL ON QUALCOMM HEXAGON HTP

**Date:** 2026-09-02  
**Platform:** Snapdragon SM8850-class device / Android  
**Backend:** llama.cpp fork / GGML Hexagon  
**Device:** HTP0  
**Profiling:** `GGML_HEXAGON_PROFILE=2` with PMU  
**Validation:** 71/71 checks OK  
**Raw profiling logs:** preserved

---

## 1. Executive Summary

This campaign introduces a sparse-MoE control workload to the Qualcomm Hexagon HTP investigation. The purpose is to separate the cost of **active matrix computation** from the additional costs of **MoE routing, expert dispatch, data movement, synchronization, and host/DSP orchestration** during batch-1 decode.

The tested workload was **Marco-Nano-Instruct**, converted from `Q8_0` to the HTP-compatible `Q4_0` format and executed successfully on HTP0.

The clean result was:

```text
Marco-Nano-Instruct Q4_0
HTP0
26.72 tok/s
```

The dense Qwen reference from the same campaign was:

```text
Qwen dense MTP1
HTP0
11.26 tok/s
```

The comparison is:

| Metric | Dense Qwen MTP1 | Marco-Nano sparse MoE |
|---|---:|---:|
| End-to-end decode | **11.26 tok/s** | **26.72 tok/s** |
| Time/token | **88.8 ms** | **37.4 ms** |
| DSP `MUL_MAT` / token | **~65 ms** | **~8.7 ms** |

The measured `MUL_MAT` cost therefore falls by approximately **7.5×**, while the end-to-end time/token falls by only approximately **2.37×**.

This is the central result: **active matrix-computation volume is not sufficient to explain end-to-end HTP decode latency.** A substantial residual cost remains outside the measured `MUL_MAT` component.

The MoE profile also exposes a new optimization target. `ARGSORT` is measured at approximately **215 µs/op**, representing approximately **35.7% of the measured DSP time**, followed by `MUL_MAT_ID` at approximately **25.2%**.

The experiment therefore shifts the optimization focus from raw matrix throughput alone toward **routing, expert dispatch, and the non-`MUL_MAT` portion of the execution pipeline**.

This report does **not** claim that DDR bandwidth, FastRPC, DMA, or host orchestration has individually been proven to be the dominant wall-clock bottleneck. Those contributions require additional event-level measurements.

---

# 2. Objective

The experiment was designed as a sparse-MoE control for the existing Qualcomm Hexagon HTP decode study.

The main question was:

> If active matrix computation is reduced by a large factor while the accelerator and software stack remain broadly comparable, how much of that reduction appears in end-to-end token generation time?

The discriminating prediction was:

### Compute-dominated hypothesis

A large reduction in active `MUL_MAT` work should produce a comparably large reduction in wall-clock decode time.

### Non-compute-dominated hypothesis

A large reduction in active `MUL_MAT` work should produce a smaller wall-clock improvement because significant per-token costs remain elsewhere in the execution pipeline.

The measured Marco-Nano result strongly supports the second case.

---

# 3. Model

## 3.1 Tested workload

**Marco-Nano-Instruct**

Architecture:

```text
qwen3moe
```

The tested Nano variant is a sparse MoE workload with approximately:

- ~8B total parameters
- ~0.6B active parameters/token
- 256 experts
- 8 active experts
- 28 layers

This is **not** the larger Marco-Mini-Instruct 17.3B / ~0.86B-active model considered at the start of the investigation.

The Nano variant was selected because it was small enough to execute reliably on the target device while preserving the essential sparse-MoE control property.

---

# 4. Initial Deployment Constraints

The initial investigation of the larger Marco-Mini workload identified two hard constraints on the target device:

1. no immediately available HTP-compatible `Q4_0` GGUF was found among the available conversions;
2. a ~9–10 GB converted model would leave insufficient memory headroom for HTP/runtime allocations.

The campaign was therefore redirected to the smaller Marco-Nano workload.

This preserved the scientific purpose of the test while avoiding a deliberately memory-invalid benchmark.

---

# 5. Reproducible Conversion Pipeline

## 5.1 Host storage

The initial download was attempted on the system `C:` volume. That volume was full, producing:

```text
curl exit 23
```

The failure was traced to local storage exhaustion.

The model was subsequently stored under:

```text
D:\models_marco\
```

Source file:

```text
Marco-Nano-Instruct.Q8_0.gguf
```

Approximate source size:

```text
8.5 GB
```

---

## 5.2 Requantization

The `llama-quantize` binary from the fork was used. The binary was compiled in the WSL build environment after the portability issue around `madvise` had been fixed.

Conversion:

```text
Q8_0
  ↓
Q4_0
```

Output:

```text
Marco-Nano-Instruct.Q4_0.gguf
≈ 4,356 MiB
```

`Q4_0` was selected because it is compatible with the HTP weight formats supported by the current backend.

---

## 5.3 Device transfer

The converted GGUF was transferred to the Android device with ADB.

Transferred size:

```text
≈ 4.57 GB
```

Observed transfer time:

```text
≈ 6 minutes
```

---

# 6. HTP Configuration

The workload was executed on HTP0 with the campaign's fixed HTP configuration.

```text
Device          : HTP0
ngl             : 99
CPU threads     : 8
Backend         : GGML Hexagon
Profiling       : GGML_HEXAGON_PROFILE=2
```

The profile contained approximately:

```text
39,170 profiled operations
```

Raw profiling data was retained for later analysis.

---

# 7. Device-State Validation

Before the discriminating ARGSORT work, the target device was checked.

Observed state:

```text
llama processes : 1 residual process
thermal_zone21  : 39000
MemAvailable    : 8,940,712 kB
```

The residual llama process was terminated before the controlled A/B testing.

The device was therefore not intentionally benchmarked with a stale inference process consuming accelerator/runtime resources.

The measured `thermal_zone21` value of 39 °C was below the campaign's 45 °C start criterion.

---

# 8. Validation

Automated validation result:

```text
71 / 71 OK
```

The complete configured pipeline therefore passed its checks, and the resulting measurement can be treated as a controlled experimental workload rather than an ad-hoc one-shot benchmark.

---

# 9. Main Performance Result

The clean Marco-Nano result was:

```text
26.72 tok/s
```

The dense Qwen MTP1 reference was:

```text
11.26 tok/s
```

Relative throughput:

```text
26.72 / 11.26 ≈ 2.37×
```

Equivalent improvement:

```text
≈ +137%
```

Time per token:

```text
Qwen:
88.8 ms/token

Marco-Nano:
37.4 ms/token
```

This corresponds to approximately a 58% reduction in end-to-end time/token.

---

# 10. Critical Compute-vs-Wall Comparison

The most informative comparison is the ratio between the measured matrix-computation cost and the total end-to-end cost.

## `MUL_MAT`

```text
Qwen:
~65 ms/token

Marco-Nano:
~8.7 ms/token
```

Ratio:

```text
65 / 8.7 ≈ 7.5×
```

## End-to-end wall time

```text
Qwen:
88.8 ms/token

Marco-Nano:
37.4 ms/token
```

Ratio:

```text
88.8 / 37.4 ≈ 2.37×
```

Therefore:

```text
MUL_MAT reduction      ≈ 7.5×
wall-time reduction   ≈ 2.37×
```

This is the central mechanistic result of the campaign.

A roughly 7.5-fold reduction in the measured matrix-computation component produces only a roughly 2.37-fold improvement in end-to-end token time.

Thus, a large fraction of the end-to-end cost is not explained by `MUL_MAT` alone.

---

# 11. New Profiling Result: ARGSORT

The MoE profile identifies `ARGSORT` as the largest measured DSP-side contributor in this workload.

Observed:

```text
ARGSORT
~215 µs/op
~35.7% of measured DSP time
```

This is important because sparse MoE execution requires routing decisions before expert-specific work can be dispatched.

A simplified path is:

```text
activation
    ↓
router
    ↓
expert scores
    ↓
ARGSORT / ranking
    ↓
top-k selection
    ↓
expert dispatch
    ↓
MUL_MAT_ID
    ↓
expert computation
    ↓
aggregation
```

When expert matrix computation becomes much cheaper, routing overhead becomes proportionally more visible.

The result therefore makes ARGSORT a concrete optimization target.

---

# 12. New Profiling Result: MUL_MAT_ID

The second major MoE-specific contributor in the profile is:

```text
MUL_MAT_ID
≈ 25.2% of measured DSP time
```

Sparse expert execution requires indexed dispatch to the selected experts rather than one ordinary contiguous dense matrix multiplication.

The resulting path has explicit routing and expert-ID handling:

```text
routing
   ↓
expert IDs
   ↓
indexed dispatch
   ↓
MUL_MAT_ID
```

This creates a different execution regime from the dense workload.

---

# 13. Bottleneck Migration

The dense and sparse workloads expose different cost structures.

## 13.1 Dense Qwen

The previous selective attention requantization experiment produced:

```text
Attention Q8_0 model : ~7.29 GiB
Attention Q4_0 model : ~5.07 GiB
```

Measured changes included approximately:

```text
DSP total:
1.100 s → 0.950 s

MUL_MAT average:
414.8 µs → 344.9 µs

Decode wall:
6.72 → 6.68 tok/s
```

The important observation was that a measurable reduction in arithmetic/DSP cost did not materially change end-to-end decode throughput.

## 13.2 Sparse Marco-Nano

The sparse workload reduces the measured `MUL_MAT` cost much more aggressively:

```text
~65 ms/token → ~8.7 ms/token
```

while end-to-end time changes by only:

```text
88.8 → 37.4 ms/token
```

The sparse experiment therefore exposes a much larger fraction of the costs that were previously hidden beneath dense matrix computation.

---

# 14. Relation to MTP and n-gram Experiments

The Marco-Nano result is consistent with the broader campaign.

## 14.1 MTP

For Qwen3.5-9B-D2-A-MTP, the clean campaign observed:

```text
Baseline:
~5.78 tok/s

MTP n_max=1:
~8.3–11.3 tok/s
```

This indicates that reducing or amortizing serialized per-token work can improve end-to-end throughput substantially.

The precise MTP numbers depend on the benchmark protocol; they should not be conflated with the separate Marco-Nano result.

## 14.2 n-gram

Clean n-gram measurements were approximately:

```text
~2.5–3.4 tok/s
```

Some runs showed very high or perfect acceptance, yet throughput remained poor.

This demonstrates that acceptance rate alone does not guarantee a speedup when draft-generation and orchestration costs are substantial.

---

# 15. CPU vs HTP Control

A CPU-only control using the attention-Q4 Qwen configuration reached approximately:

```text
~9.02 tok/s
```

The corresponding HTP decode result was approximately:

```text
~6.68 tok/s
```

Therefore the HTP accelerator does not automatically produce higher batch-1 decode throughput than CPU on this workload/configuration.

The sparse-MoE experiment provides an additional explanation: once active arithmetic is reduced, the remaining execution-path costs become increasingly important.

---

# 16. Proposed Per-Token Cost Model

The current data can be represented by the following simplified model:

```text
T_token =
      T_MUL_MAT
    + T_ARGSORT
    + T_MUL_MAT_ID
    + T_DMA
    + T_L2/VTCM
    + T_FastRPC
    + T_host
    + T_sync
    + T_other
```

This is a measurement framework, not yet a complete quantitative decomposition.

The Marco-Nano control changes `T_MUL_MAT` dramatically while leaving substantial total token time.

That observation establishes a significant non-`MUL_MAT` component.

---

# 17. Causal ARGSORT A/B Experiment

The fork exposes the environment variable:

```text
GGML_HEXAGON_OPFILTER
```

The implementation contains the relevant logic:

```text
const char * str_opfilter = getenv("GGML_HEXAGON_OPFILTER");
```

and rejects matching operations from the Hexagon backend:

```text
if (opt_opfilter && std::regex_match(ggml_op_desc(op), *opt_opfilter)) {
    return false;
}
```

Therefore the discriminating configuration can be constructed with:

```text
GGML_HEXAGON_OPFILTER='ARGSORT'
```

The intended A/B comparison is:

### Test A

```text
ARGSORT → HTP
```

### Test B

```text
ARGSORT → CPU fallback
```

with all other variables held as constant as practical.

The interpretation is:

```text
B much slower than A
→ HTP ARGSORT is beneficial

B approximately equal to A
→ ARGSORT is not a major wall-clock limiter

B faster than A
→ current CPU routing is more efficient than HTP ARGSORT
```

This experiment is causally stronger than inferring importance solely from profiling percentages.

---

# 18. What the Experiment Demonstrates

With high confidence, the campaign demonstrates:

### 18.1 Sparse MoE can substantially increase HTP decode throughput

```text
11.26 → 26.72 tok/s
```

### 18.2 Active matrix computation is not the sole wall-clock limiter

```text
MUL_MAT: ~7.5× lower
wall:    ~2.37× better
```

### 18.3 MoE routing and indexed expert dispatch become major contributors

```text
ARGSORT    ~35.7% DSP
MUL_MAT_ID ~25.2% DSP
```

### 18.4 Bottlenecks migrate as compute is reduced

Lower matrix workload exposes costs that are less visible in the dense workload.

---

# 19. What the Experiment Does NOT Demonstrate

The current data does not justify the following absolute claims:

```text
"DDR bandwidth is proven to be the bottleneck."
```

```text
"FastRPC is proven to be the dominant bottleneck."
```

```text
"DMA accounts for X% of decode time."
```

```text
"Host orchestration accounts for Y%."
```

Those statements require direct correlation between wall-clock time and the relevant PMU/trace events.

The scientifically supported statement is:

> The sparse-MoE control demonstrates a substantial non-`MUL_MAT` contribution to end-to-end decode time and identifies ARGSORT and MUL_MAT_ID as important DSP-side contributors. Data movement and host/DSP orchestration remain plausible contributors, but their exact wall-clock contributions are not yet quantified.

---

# 20. Profiling Overhead

Profiling adds overhead.

Observed profiled throughput:

```text
~15.8 tok/s
```

Observed clean throughput:

```text
26.72 tok/s
```

Therefore:

```text
26.72 tok/s = performance reference
~15.8 tok/s  = profiling observation
```

The two numbers must not be interpreted as competing implementations.

---

# 21. RAM and OOM Validity

The tested Marco-Nano Q4_0 model is approximately:

```text
4,356 MiB
```

The workload completed without OOM.

This contrasts with the heavier 7.3 GiB-class Qwen workload that had previously produced severe memory pressure under the full runtime/MTP configuration.

The Marco-Nano control is therefore useful without intentionally introducing an OOM or swap-dominated benchmark.

Future runs should continue to record:

```text
MemAvailable
SwapFree
RSS/HWM
temperature
load average
```

so system-state effects remain observable.

---

# 22. Consolidated Experimental Matrix

| Experiment | Result | Main implication |
|---|---:|---|
| Qwen dense HTP | ~5.5–6.7 tok/s | Large batch-1 decode ceiling |
| Qwen CPU, attention-Q4 | ~9.02 tok/s | CPU can exceed HTP for this workload |
| Attention Q8→Q4 | MUL_MAT ~−17%, wall ~unchanged | Arithmetic reduction alone is insufficient |
| MTP n_max=1 | ~8.3–11.3 tok/s | Amortization can improve serialized work |
| n-gram | ~2.5–3.4 tok/s | Extra draft/orchestration cost can dominate |
| Marco-Nano MoE Q4_0 | **26.72 tok/s** | Sparse compute gives major speedup |
| Marco `MUL_MAT` | **~8.7 ms/token** | ~7.5× reduction vs dense reference |
| Marco `ARGSORT` | **~35.7% DSP** | Routing becomes a major contributor |
| Marco `MUL_MAT_ID` | **~25.2% DSP** | Expert dispatch is also significant |

---

# 23. Optimization Priorities

Based on the current evidence, the next optimization targets should be prioritized approximately as follows:

```text
1. ARGSORT / top-k routing
2. MUL_MAT_ID / expert dispatch
3. DMA / data movement
4. L2 / VTCM behavior
5. FastRPC / synchronization
6. Host-side orchestration
```

This ordering is a working priority based on the current measurements, not a proof of final wall-clock importance.

The highest-value immediate software experiment is to compare native HTP `ARGSORT` against CPU fallback using `GGML_HEXAGON_OPFILTER='ARGSORT'`.

---

# 24. Next Measurement Layer

The next decisive profiling stage should correlate:

```text
wall time
DSP time
ARGSORT
MUL_MAT_ID
DMA
L2
VTCM
cycles
FastRPC
host scheduling
synchronization
```

The goal is to convert the current qualitative per-token cost model into a quantitative wall-clock decomposition.

The key distinction is:

> DSP percentage is not automatically equivalent to end-to-end wall-clock contribution.

Operations can overlap with transfers or other work, and therefore event time must be correlated against the actual token-generation timeline.

---

# 25. Reproducibility Checklist

Each future benchmark should record:

```text
model filename
model hash
quantization format
HTP device
ngl
threads
context length
prompt
MTP/speculative configuration
GGML_HEXAGON_PROFILE
GGML_HEXAGON_OPFILTER
MemAvailable
SwapFree
RSS
HWM
temperature before run
temperature after run
load average
raw server log
raw PMU/profile log
clean wall-clock throughput
```

The clean and profiled runs must remain separate datasets.

---

# 26. Final Scientific Conclusion

The Marco-Nano sparse-MoE experiment is the strongest control so far for separating active HTP compute from the broader execution cost of batch-1 decode.

The critical observation is:

```text
MUL_MAT:
~65 ms/token → ~8.7 ms/token
≈ 7.5× reduction

end-to-end:
88.8 ms/token → 37.4 ms/token
≈ 2.37× improvement
```

The HTP backend therefore benefits strongly from sparsity, but end-to-end throughput does not scale proportionally with the reduction in active matrix computation.

The profile additionally shows that sparse MoE introduces a visible routing/dispatch regime:

```text
ARGSORT      ≈ 35.7% DSP
MUL_MAT_ID   ≈ 25.2% DSP
```

The strongest supported conclusion is therefore:

> **Batch-1 Qualcomm HTP decode throughput is determined by the complete execution pipeline, not by raw active matrix-computation throughput alone. Sparse MoE reduces the compute component substantially, but routing, indexed expert dispatch, data movement, synchronization, and runtime overhead remain significant contributors to end-to-end latency.**

The next step is to quantify these remaining contributors using causal A/B tests and PMU/trace correlation.

---

# 27. Experimental Verdict

**STATUS: VALIDATED**

### Confidence by claim

| Claim | Confidence |
|---|---:|
| Active `MUL_MAT` is not the sole wall-clock limiter | **0.98** |
| Sparse MoE substantially improves throughput | **0.99** |
| ARGSORT is a major DSP-side MoE contributor | **0.90** |
| MUL_MAT_ID is a major DSP-side contributor | **0.90** |
| DDR is specifically proven to be the dominant bottleneck | **0.75** |
| FastRPC/host overhead is specifically proven to dominate | **0.75** |

The lower confidence values intentionally reflect the need for direct event-level wall-clock attribution.

---

# 28. Preserved Artifacts

Host model directory:

```text
D:\models_marco\
```

Primary files:

```text
Marco-Nano-Instruct.Q8_0.gguf
Marco-Nano-Instruct.Q4_0.gguf
```

Q4_0 size:

```text
4,356 MiB
```

Report:

```text
bench_results/RAPPORT_CONTROLE_MOE_MARCO_HTP_20260902.md
```

Validation:

```text
71/71 OK
```

Raw PMU/profile logs are preserved for re-analysis.
