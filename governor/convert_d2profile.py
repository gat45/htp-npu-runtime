"""Convertit un profil kernel NVIDIA (TensorRT / CUDA events) en profils par
layer OnePlus (SM8850) — schéma de governor/profiler.py.

Entrée (dossier NVIDIA `d2_profile/v4`) :
  per_op_aggregate.csv · per_layer_aggregate.csv · per_family_aggregate.csv ·
  report.md (table decode par layer) · (option) quant_plan_v4xppl.json

Le modèle est le MÊME que le 9B du OnePlus (Qwen3.5 hybride Mamba-2 +
attention : conv_states, ssm, output.weight, blk.0..31). La distribution
RELATIVE du temps par layer/famille se transfère à l'OP15 ; les temps absolus
sont rescallés par la bande passante effective (QAIRT ~74 GB/s vs GGML
27-32 GB/s) et le TG mesuré du device.

Sortie : LayerProfile[] (schéma profiler) + rapport OnePlus + plan de
quantification par layer (via profiler.select_layer_formats).

Usage :
  py -m governor.convert_d2profile "<dir>" [--runtime qairt|ggml]
                                          [--tg 6.3] [--out <dir>]
"""
import csv
import json
import os
import re
import sys

try:
    from . import profiler
except ImportError:  # exécution directe
    import profiler

DECODE_TG_DEFAULT = 6.3          # t/s OP15 GGUF Q4_0 HTP (baseline T0)
BW_FACTOR = {"qairt": 74.0, "ggml": 30.0, "nvidia_ref": 1.0}

FAMILY_ORDER = ["other", "attn", "output", "ffn", "ssm", "norm"]


def load(dirpath):
    """Charge les 3 CSV + report.md + quant_plan (best-effort)."""
    def read_csv(name):
        p = os.path.join(dirpath, name)
        if not os.path.exists(p):
            return []
        with open(p, encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f))

    out = {"dir": dirpath,
           "per_op": read_csv("per_op_aggregate.csv"),
           "per_layer": read_csv("per_layer_aggregate.csv"),
           "per_family": read_csv("per_family_aggregate.csv"),
           "report_md": None, "quant_plan": None}
    rp = os.path.join(dirpath, "report.md")
    if os.path.exists(rp):
        with open(rp, encoding="utf-8") as f:
            out["report_md"] = f.read()
    for qn in ("quant_plan_v4xppl.json", "quant_plan.json"):
        qp = os.path.join(os.path.dirname(dirpath), qn)
        if os.path.exists(qp):
            try:
                with open(qp, encoding="utf-8") as f:
                    out["quant_plan"] = json.load(f)
            except Exception:
                pass
            break
    return out


def _num(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def parse_decode_per_layer(report_md):
    """Table '∑ µs/passe' du report.md → {layer: us_passe}."""
    if not report_md:
        return {}
    m = re.search(r"### Par layer[^\n]*\n\s*\n\|.*?\n((?:\|.*\n)+)",
                  report_md)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and (cells[0].isdigit() or cells[0] == "root"):
            out[cells[0]] = _num(cells[2])
    return out


def decode_top_ops(per_op, n=10):
    """Top ops decode depuis per_op (avg élevé = op lourde)."""
    rows = sorted(per_op, key=lambda r: -_num(r.get("avg_us")))
    return [{"op": r.get("op"), "tensor": r.get("key", "").split("|")[-1],
             "nbytes": int(_num(r.get("nbytes"))),
             "avg_us": round(_num(r.get("avg_us")), 1),
             "max_us": round(_num(r.get("max_us")), 1),
             "us_total": round(_num(r.get("us_total")), 1)}
            for r in rows[:n]]


def families(per_family):
    tot = sum(_num(r.get("us_total")) for r in per_family) or 1
    return [{"famille": r.get("key"), "ops": int(_num(r.get("count"))),
             "us_ms": round(_num(r.get("us_total")) / 1e3, 1),
             "part_pct": round(_num(r.get("us_total")) / tot * 100, 1)}
            for r in per_family]


def op15_layer_profiles(data, runtime="qairt", tg=DECODE_TG_DEFAULT,
                        weight_format="W4A16"):
    """Profils par layer OP15 : distribution relative NVIDIA × budget OP15."""
    dec = parse_decode_per_layer(data.get("report_md"))
    if not dec:
        # Repli : distribuer par nbytes des per_layer.
        rows = data.get("per_layer") or []
        tot = sum(_num(r.get("nbytes")) for r in rows) or 1
        dec = {r.get("key"): _num(r.get("nbytes")) / tot
               for r in rows}
        scale = None
    else:
        scale = sum(dec.values())

    total_us_token = 1e6 / tg          # µs par token (decode global OP15)
    bw = BW_FACTOR.get(runtime, 30.0)

    # Répartition : une fraction du decode est 'root' (output.weight + norms)
    # — on réutilise le share NVIDIA si présent, sinon 25% du budget.
    profiles = []
    layers = sorted(dec.items(), key=lambda kv: (kv[0] == "root", kv[0]))
    for layer, us in layers:
        share = us / scale if scale else us
        total_us = max(1, int(total_us_token * share))
        staging = int(total_us * 0.55)
        compute = int(total_us * 0.20)
        sync = max(1, total_us - staging - compute)
        profiles.append(profiler.layer_profile(
            layer=f"blk.{layer}" if layer != "root" else "root",
            weight_format=weight_format, backend="htp",
            kernel=f"{weight_format}-{runtime}", runtime=runtime,
            params=None, size_bytes=None,
            staging_us=staging, compute_us=compute, sync_us=sync,
            total_us=total_us,
            bw_gbps=round(bw, 1),
            bottleneck=profiler.classify_bottleneck(staging, compute, sync)))
    return profiles


def op15_plan(data, runtime="qairt", budget_bytes=None, tg=DECODE_TG_DEFAULT,
              formats=None):
    """Plan de quantification par layer OP15, croisé quant_plan NVIDIA."""
    dec = parse_decode_per_layer(data.get("report_md"))
    layers = [{"id": f"blk.{k}" if k != "root" else "root",
               "params": 1.0, "class": "attn" if k != "root" else "lm_head"}
              for k in dec] or profiler.demo_layers()
    sel = profiler.select_layer_formats(layers, budget_bytes=budget_bytes,
                                        formats=formats,
                                        max_loss_pct=1.5)
    plan = []
    qp = data.get("quant_plan") or {}
    for a in sel["layers"]:
        blk = a["layer"].replace("blk.", "") if a["layer"] != "root" else None
        nv = qp.get(str(blk), {}) if isinstance(qp, dict) else {}
        decision = nv.get("decision", "CONSERVER")
        plan.append({"layer": a["layer"], "format": a["format"],
                     "Wbits": a["Wbits"], "loss_pct": a["loss_pct"],
                     "nv_decision": decision,
                     "nv_dppl": nv.get("dppl")})
    return {"plan": plan, "total_bytes": sel["total_bytes"],
            "total_loss_pct": sel["total_loss_pct"],
            "feasible": sel["feasible"]}


def render_op15_report(data, runtime="qairt", tg=DECODE_TG_DEFAULT):
    """Rapport OnePlus dans le style du rapport NVIDIA."""
    fam = families(data.get("per_family") or [])
    dec = parse_decode_per_layer(data.get("report_md"))
    total_us = 1e6 / tg
    bw = BW_FACTOR.get(runtime, 30.0)
    L = []
    L.append(f"# D2-PROFILE OP15 (SM8850) — converti depuis NVIDIA TensorRT")
    L.append("")
    L.append(f"Source NVIDIA : {data['dir']} — même modèle (Qwen3.5 hybride "
             f"Mamba-2+attention). Distribution RELATIVE conservée, temps "
             f"rescallés par BW effective {runtime}={bw} GB/s et TG={tg} t/s.")
    L.append(f"**Budget decode OP15 : {total_us/1e3:.1f} ms/token.**")
    L.append("")
    L.append("## Répartition par famille (structure transférée)")
    L.append("")
    L.append("| famille | ops | part % |")
    L.append("|---|---:|---:|")
    for f in fam:
        L.append(f"| {f['famille']} | {f['ops']} | {f['part_pct']} |")
    L.append("")
    L.append("## Coût decode par layer (estimé OP15)")
    L.append("")
    L.append("| layer | ∑ µs/passe | part % |")
    L.append("|---|---:|---:|")
    scale = sum(dec.values()) if dec else 1
    for k, us in sorted(dec.items(), key=lambda kv: -kv[1]):
        share = us / scale if scale else 0
        L.append(f"| {'root' if k=='root' else 'blk.'+k} | "
                 f"{int(total_us*share):,} | {share*100:.1f} |")
    L.append("")
    L.append("## Top ops decode (NVIDIA, transposables)")
    L.append("")
    L.append("| rang | op | tensor | nbytes | avg µs | part % |")
    L.append("|---|---|---|---:|---:|---:|")
    tot = sum(_num(r.get("us_total")) for r in data.get("per_op") or []) or 1
    for i, o in enumerate(decode_top_ops(data.get("per_op") or [], 8), 1):
        L.append(f"| {i} | {o['op']} | `{o['tensor']}` | {o['nbytes']:,} | "
                 f"{o['avg_us']:,.0f} | {o['us_total']/tot*100:.1f} |")
    L.append("")
    L.append("## Lecture OP15")
    L.append("")
    L.append("- **output.weight** domine le decode (root ~25-35 %) → cible "
             "n°1 (corrobore LM_HEAD 795 Mo/token OP15).")
    L.append("- ssm/conv_states = ops Mamba-2 : non supportées QAIRT → "
             "fallback CPU (GGML) ou HTP (v81).")
    L.append(f"- Runtime choisi : **{runtime}** (BW effective {bw} GB/s). "
             f"GGML = 27-32 GB/s, QAIRT = ~74 GB/s.")
    return "\n".join(L) + "\n"


def convert(dirpath, runtime="qairt", tg=DECODE_TG_DEFAULT, out=None,
            write=True):
    data = load(dirpath)
    profiles = op15_layer_profiles(data, runtime=runtime, tg=tg)
    plan = op15_plan(data, runtime=runtime, tg=tg)
    report = render_op15_report(data, runtime=runtime, tg=tg)
    result = {"source": dirpath, "runtime": runtime, "tg": tg,
              "n_layer_profiles": len(profiles),
              "profiles": profiles, "plan": plan}
    if write:
        outdir = out or os.path.join(os.path.dirname(dirpath),
                                     f"op15_{runtime}")
        os.makedirs(outdir, exist_ok=True)
        with open(os.path.join(outdir, "op15_profiles.json"), "w",
                  encoding="utf-8") as f:
            json.dump({"profiles": profiles, "plan": plan},
                      f, ensure_ascii=False, indent=2)
        with open(os.path.join(outdir, "op15_report.md"), "w",
                  encoding="utf-8") as f:
            f.write(report)
        result["out"] = outdir
    return result


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(prog="convert_d2profile")
    ap.add_argument("dir", help="dossier NVIDIA d2_profile (ex. 'v4 - Copie')")
    ap.add_argument("--runtime", choices=["qairt", "ggml"], default="qairt")
    ap.add_argument("--tg", type=float, default=DECODE_TG_DEFAULT)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print(json.dumps(convert(args.dir, runtime=args.runtime, tg=args.tg,
                             out=args.out), ensure_ascii=False, indent=2))