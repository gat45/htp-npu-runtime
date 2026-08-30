"""Indexe dans le RAG (provenance) les mesures réelles trouvées dans
C:\\Users\\videl\\AppData\\Local\\Temp\\opencode\\ et absentes de la mémoire
(runtime_profile, geniex_run, hwprof_sample, axe2_p*.log, qwen9b_q40_layers).

Usage : py -m governor.index_temp_opencode [--dry-run]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from governor.provenance import ProvenanceMemory

TMP = r"C:\Users\videl\AppData\Local\Temp\opencode"
PM_PATH = os.path.join(ROOT, "governor_state", "provenance.json")


def _load(name):
    with open(os.path.join(TMP, name), encoding="utf-8") as f:
        return json.load(f)


def facts():
    out = []

    # 1. runtime_profile.json — analyse memory-bound Qwen3-8B Q4_K_M
    rp = _load("runtime_profile.json")
    s = rp["summary"]
    per_op = {k: v["MiB"] for k, v in rp.get("per_op", {}).items()}
    out.append({
        "key": "bench:runtime_profile_qwen3_8b_memory_bound",
        "value": {
            "model": s["model"], "n_tensors": s["n_tensors"],
            "n_layers": s["n_layers"],
            "total_params_bytes": s["total_params_bytes"],
            "decode_weight_bytes_per_token": s["decode_weight_bytes_per_token"],
            "bw_eff_gbs": s["bw_eff_gbs"],
            "est_memory_bound_ms_per_token": s["est_memory_bound_ms_per_token"],
            "measured_ms_per_token": s["measured_ms_per_token"],
            "memory_bound_explain_pct": s["memory_bound_explain_pct"],
            "per_op_mib": per_op,
            "note": "le decode est ~expliqué à 116,6 % par la bande passante poids",
        },
        "source": "bench:Temp_opencode_runtime_profile_json",
        "confidence": 0.8, "reproducible": True,
    })

    # 2. geniex_run.json — support speculatif par backend + mesures qairt
    gr = _load("geniex_run.json")
    cell = gr["cells"][0]
    pd = gr["profile_data"]
    out.append({
        "key": "bench:geniex_run_qairt_spec_support",
        "value": {
            "plugin": cell["plugin"], "ngl": cell["ngl"],
            "ttft_ms": cell["ttft_ms"], "prefill_tps": cell["prefill_tps"],
            "decode_tps": cell["decode_tps"], "gen_tokens": cell["gen_tokens"],
            "profile": {k: pd[k] for k in
                        ("ttft_us", "prompt_time_us", "decode_time_us",
                         "prompt_tokens", "generated_tokens",
                         "prefill_speed", "decoding_speed")},
            "spec_support": gr["spec_support"],
            "concl": "llama_cpp = speculative (MTP) CONFIRME ; qairt = no-op "
                     "(--draft-tokens sans effet)",
        },
        "source": "bench:Temp_opencode_geniex_run_json",
        "confidence": 0.9, "reproducible": True,
    })

    # 3. axe2_p*.log — replications llama-bench OpenCL,HTP ngl99
    runs = {}
    for f in ("axe2_p1.log", "axe2_p2.log", "axe2_p4.log", "axe2_p7.log"):
        rows = {}
        with open(os.path.join(TMP, f), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("|") and "---" not in line:
                    parts = [p.strip() for p in line.split("|")]
                    if len(parts) >= 8 and parts[6] in ("pp64", "tg4"):
                        rows[parts[6]] = float(parts[7].split()[0])
        runs[f] = rows
    pp = [r["pp64"] for r in runs.values() if "pp64" in r]
    tg = [r["tg4"] for r in runs.values() if "tg4" in r]
    out.append({
        "key": "bench:axe2_opencl_htp_qwen3_8b_replications",
        "value": {
            "model": "qwen3 8B Q4_K (Medium)", "backend": "OpenCL,HTP",
            "ngl": 99, "runs": runs,
            "moy_pp64": round(sum(pp) / len(pp), 2) if pp else None,
            "moy_tg4": round(sum(tg) / len(tg), 2) if tg else None,
            "n_replications": len(runs),
        },
        "source": "bench:Temp_opencode_axe2_p_logs",
        "confidence": 0.9, "reproducible": True,
    })

    # 4. qwen9b_q40_layers.json — decomposition par rôle (9B Q4_0)
    q9 = _load("qwen9b_q40_layers.json")
    roles = {k: v for k, v in q9.get("roles", {}).items()}
    out.append({
        "key": "bench:qwen9b_q40_layer_roles",
        "value": {
            "model": q9.get("model"), "total_weight_gb": q9.get("total_weight_gb"),
            "bw_eff_calibration": q9.get("bw_eff_calibration"),
            "predicted_tg_from_sum": q9.get("predicted_tg_from_sum"),
            "roles": roles,
            "n_layers": len(q9.get("layers", [])),
        },
        "source": "bench:Temp_opencode_qwen9b_q40_layers_json",
        "confidence": 0.8, "reproducible": True,
    })

    # 5. hwprof_sample.json — snapshot hw SM8850 / CPH2747
    hw = _load("hwprof_sample.json")
    dev = hw.get("device", {})
    cores = hw.get("cpu", {}).get("cores", [])[:4]
    out.append({
        "key": "hw:sm8850_cph2747_snapshot",
        "value": {
            "ts": hw.get("ts"), "soc": dev.get("soc"), "model": dev.get("model"),
            "cpu_usage_pct": hw.get("cpu", {}).get("usage_pct"),
            "cores_sample": cores,
        },
        "source": "bench:Temp_opencode_hwprof_sample_json",
        "confidence": 0.9, "reproducible": True,
    })

    return out


def main():
    dry = "--dry-run" in sys.argv
    pm = ProvenanceMemory(PM_PATH)
    before = len(pm.entries)
    for fact in facts():
        res = pm.write(fact["key"], fact["value"], fact["source"],
                       confidence=fact["confidence"],
                       reproducible=fact["reproducible"])
        if dry:
            print(f"[DRY] {fact['key']} -> {res}")
        else:
            print(f"[OK] {fact['key']} -> stored={res['stored']} "
                  f"quarantined={res.get('quarantined')} "
                  f"superseded={res.get('superseded')}")
    print(f"entries: {before} -> {len(pm.entries)}")


if __name__ == "__main__":
    main()
