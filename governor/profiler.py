"""Bloc 22 — Profiler multi-format par layer (W/A, GGML, runtime, backend).

Le profiler répond à : « pour ce layer, avec ce format W/A, ce packing, ce
kernel, ce runtime et cet état matériel, où est le temps et où est le trafic
mémoire ? ».

Règles :
- On ne mélange JAMAIS les deux nomenclatures dans une même colonne :
  Q4_0 = format de stockage/runtime GGML ; W4A16 = précision poids/activation.
- Le même modèle × même précision est profilé sur plusieurs runtimes
  (GGML/QNN/QAIRT) et backends (CPU/HTP/GPU/hybrides), sinon on confond un
  problème de format avec un problème de kernel/runtime (QAIRT 15,6 vs
  GGML 6,3 t/s = ×2,48 : format ou implémentation ?).
"""
import json
import os
import time

# ---------------------------------------------------------------------------
# Registres de formats — deux nomenclatures distinctes.
# size_mult = octets/paramètre relativement à FP16 (2 octets).
# ---------------------------------------------------------------------------

W_FORMATS = {
    "W16A16": {"Wbits": 16, "Abits": 16, "group_size": None,
               "scale_type": "none", "packing": "dense", "size_mult": 1.00},
    "W8A16": {"Wbits": 8, "Abits": 16, "group_size": None,
              "scale_type": "per-tensor", "packing": "s8", "size_mult": 0.50},
    "W8A8": {"Wbits": 8, "Abits": 8, "group_size": None,
             "scale_type": "per-tensor", "packing": "s8", "size_mult": 0.50},
    "W4A16": {"Wbits": 4, "Abits": 16, "group_size": 128,
              "scale_type": "per-group", "packing": "uint4x2", "size_mult": 0.25},
    "W4A8": {"Wbits": 4, "Abits": 8, "group_size": 128,
             "scale_type": "per-group", "packing": "uint4x2", "size_mult": 0.25},
}

GGML_FORMATS = {
    "F16": {"Wbits": 16, "group_size": None, "scale_type": "none",
            "packing": "dense", "size_mult": 1.00},
    "Q8_0": {"Wbits": 8, "group_size": 32, "scale_type": "block-32",
             "packing": "legacy", "size_mult": 0.50},
    "Q6_K": {"Wbits": 6, "group_size": 32, "scale_type": "block-32",
             "packing": "k-quant", "size_mult": 0.42},
    "Q5_K_M": {"Wbits": 5, "group_size": 32, "scale_type": "block-32",
               "packing": "k-quant", "size_mult": 0.36},
    "Q5_K_S": {"Wbits": 5, "group_size": 32, "scale_type": "block-32",
               "packing": "k-quant", "size_mult": 0.34},
    "Q4_K_M": {"Wbits": 4, "group_size": 32, "scale_type": "block-32",
               "packing": "k-quant", "size_mult": 0.28},
    "Q4_K_S": {"Wbits": 4, "group_size": 32, "scale_type": "block-32",
               "packing": "k-quant", "size_mult": 0.26},
    "Q4_0": {"Wbits": 4, "group_size": 32, "scale_type": "block-32",
             "packing": "legacy", "size_mult": 0.26},
}

RUNTIMES = ("ggml", "qnn", "qairt")
BACKENDS = ("cpu", "htp", "gpu", "cpu+htp", "cpu+gpu", "htp+gpu")

# Perte de qualité estimée par format (relativement à FP16), par layer.
LOSS_EST = {
    "W16A16": 0.0, "W8A16": 0.05, "W8A8": 0.20, "W4A16": 0.50, "W4A8": 0.80,
    "F16": 0.0, "Q8_0": 0.10, "Q6_K": 0.15, "Q5_K_M": 0.30,
    "Q5_K_S": 0.40, "Q4_K_M": 0.60, "Q4_K_S": 0.80, "Q4_0": 1.00,
}

# Plancher de précision par classe de layer (Wbits) — norm = FP16 strict.
CLASS_FLOORS = {"norm": 16, "embed": 8, "lm_head": 8, "attn": 4, "mlp": 4}
# Allocation de référence = précision maximale ; le solveur réduit ensuite
# layer par layer (best bytes-per-loss) jusqu'au budget RAM / perte max.
CLASS_DEFAULT = {"norm": "W16A16", "embed": "W8A16", "lm_head": "W8A16",
                 "attn": "W16A16", "mlp": "W16A16"}


# ---------------------------------------------------------------------------
# Schéma de données (JSON-serialisable).
# ---------------------------------------------------------------------------

def model_spec(architecture, parameters, context, tokenizer=None):
    return {"model": {"architecture": architecture, "parameters": parameters,
                      "context": context, "tokenizer": tokenizer}}


def weights_spec(storage_format, size_bytes=None, params=None):
    reg = W_FORMATS.get(storage_format) or GGML_FORMATS.get(storage_format)
    spec = {"storage_format": storage_format,
            "Wbits": reg["Wbits"] if reg else None,
            "Abits": reg.get("Abits") if reg else None,
            "group_size": reg["group_size"] if reg else None,
            "scale_type": reg["scale_type"] if reg else None,
            "packing": reg["packing"] if reg else None}
    if params is not None:
        spec["size_bytes"] = int(params * 2 * reg["size_mult"]) \
            if reg else size_bytes
    else:
        spec["size_bytes"] = size_bytes
    return spec


def runtime_spec(name, version=None, commit=None, configuration=None):
    return {"runtime": {"name": name, "version": version, "commit": commit,
                        "configuration": configuration or {}}}


def execution_spec(backend, kernel, layer, staging_us, compute_us, sync_us,
                   total_us=None):
    return {"execution": {"backend": backend, "kernel": kernel,
                          "layer": layer, "staging_us": staging_us,
                          "compute_us": compute_us, "sync_us": sync_us,
                          "total_us": total_us or (staging_us + compute_us
                                                   + sync_us)}}


def hardware_spec(cpu_freq=None, ddr_freq=None, memory_bw=None, cache=None,
                  htp=None, temperature=None, pmu=None):
    return {"hardware": {"cpu_freq": cpu_freq, "ddr_freq": ddr_freq,
                         "memory_bw": memory_bw, "cache": cache, "htp": htp,
                         "temperature": temperature, "pmu": pmu}}


def layer_profile(layer, weight_format, backend, kernel=None, runtime=None,
                  params=None, size_bytes=None, staging_us=None,
                  compute_us=None, sync_us=None, total_us=None,
                  bw_gbps=None, bottleneck=None, spill_fill_buffer_size=None):
    reg = W_FORMATS.get(weight_format) or GGML_FORMATS.get(weight_format)
    p = {"layer": layer, "weight_format": weight_format,
         "Wbits": reg["Wbits"] if reg else None,
         "Abits": reg.get("Abits") if reg else None,
         "group_size": reg["group_size"] if reg else None,
         "kernel": kernel, "backend": backend, "runtime": runtime,
         "params": params, "size_bytes": size_bytes,
         "staging_us": staging_us, "compute_us": compute_us,
         "sync_us": sync_us, "total_us": total_us,
         "bw_gbps": bw_gbps, "bottleneck": bottleneck,
         "spill_fill_buffer_size": spill_fill_buffer_size}
    return p


def parse_qnn_spill_fill(buffer_or_path):
    """Extrait `spillFillBufferSize` de la métadonnée QNN context binary.

    datavorous (RE libHtpPrepare.so) : le binaire porte un champ
    `spillFillBufferSize` — 0 = weights tiennent on-chip, >0 = spill vers DDR.
    Le format est un flatbuffer : la string apparaît comme CLÉ, la valeur dans
    le blob. Stratégie best-effort : chercher la clé, puis la valeur dans une
    fenêtre après (essayer plusieurs décalages/tailles). Aucune mesure dynamique.
    """
    data = buffer_or_path
    if isinstance(buffer_or_path, str):
        import os
        if os.path.exists(buffer_or_path):
            with open(buffer_or_path, "rb") as f:
                data = f.read()
        else:
            return None
    if not isinstance(data, bytes):
        return None
    keys = (b"spillFillBufferSize", b"spill_fill_buffer_size",
            b"spillFillbufferSize")
    for key in keys:
        idx = data.find(key)
        if idx < 0:
            continue
        # Le flatbuffer stocke la clé puis, dans une table, la valeur.
        # Parsing structuré impossible sans le schéma -> on cherche une valeur
        # 64-bit crédible (taille de spill) dans les 48 octets suivants,
        # en essayant des alignements. Très conservateur : on retourne
        # uniquement une valeur "propre" (>4KB, multiple raisonnable).
        window = data[idx + len(key): idx + len(key) + 48]
        candidates = []
        for off in range(0, len(window) - 8, 2):  # alignements pairs
            v64 = int.from_bytes(window[off:off + 8], "little")
            v32 = int.from_bytes(window[off:off + 4], "little")
            # interprétations endian possibles (flatbuffer uint32/uint64)
            for c in (v64, v32):
                if 0 < c < (1 << 40) and c > 4096 and \
                        c % 4096 in (0, 1, 2, 4, 8, 16, 32, 64, 128, 256,
                                     1024):
                    candidates.append(c)
        if candidates:
            # la taille de spill est la valeur la plus petite crédible
            # (évite de prendre l'offset uoffset ou un padding combiné)
            return min(candidates)
    # clé présente mais aucune valeur crédible -> hypothèse prudente on-chip
    return 0 if any(k in data for k in keys) else None


def parse_qnn_context_spill_fill(path, verbose=False):
    """Wrapper : lit un fichier QnnContext.bin et retourne {spill_fill_buffer_size, goulot}."""
    import os
    if not os.path.exists(path):
        return {"ok": False, "error": f"fichier absent: {path}", "spill_fill_buffer_size": None}
    v = parse_qnn_spill_fill(path)
    if v is None:
        return {"ok": False, "error": "pattern spillFillBufferSize introuvable", "spill_fill_buffer_size": None}
    return {"ok": True, "spill_fill_buffer_size": v,
            "fit": v == 0, "spill": v > 0,
            "verdict": "on-chip (compute-bound)" if v == 0 else
                       "spill -> DDR (memory-bandwidth)"}
    return {"result": {"pp_tps": pp_tps, "tg_tps": tg_tps,
                       "latency_ms": latency_ms, "energy_j": energy_j,
                       "bottleneck": bottleneck, "ram_peak_mb": ram_peak_mb}}


def result_spec(pp_tps, tg_tps, latency_ms, energy_j=None,
                bottleneck=None, ram_peak_mb=None):
    return {"result": {"pp_tps": pp_tps, "tg_tps": tg_tps,
                       "latency_ms": latency_ms, "energy_j": energy_j,
                       "bottleneck": bottleneck, "ram_peak_mb": ram_peak_mb}}


# ---------------------------------------------------------------------------
# Détection de goulot par layer (où est le temps / le trafic ?).
# ---------------------------------------------------------------------------

def classify_bottleneck(staging_us, compute_us, sync_us, bw_gbps=None,
                        bw_cap_gbps=None, spill_fill_buffer_size=None):
    """compute / memory-bandwidth / sync-overhead, avec preuve BW.

    ORACLE (datavorous, RE QAIRT) : `spillFillBufferSize` (métadonnée QNN)
    est un prédicteur statique fit/spill :
      - > 0  → des tensors spillent vers DDR → goulot memory-bandwidth
      - == 0 → les weights tiennent on-chip → compute-bound (ou sync)
    Si l'oracle est fourni, il PRIME sur les ratios (preuve statique, pas
    une inférence à partir du timing).
    """
    if spill_fill_buffer_size is not None and spill_fill_buffer_size > 0:
        return "memory-bandwidth"
    if spill_fill_buffer_size == 0:
        # on-chip : compute ou sync, jamais bandwidth — affiner par ratios
        total = staging_us + compute_us + sync_us
        if total > 0 and sync_us / total > 0.3:
            return "sync-overhead"
        return "compute"
    total = staging_us + compute_us + sync_us
    if total <= 0:
        return "unknown"
    if compute_us / total > 0.6:
        return "compute"
    if sync_us / total > 0.3:
        return "sync-overhead"
    if bw_gbps is not None and bw_cap_gbps is not None \
            and bw_cap_gbps > 0 and bw_gbps / bw_cap_gbps > 0.9:
        return "memory-bandwidth"
    if staging_us / total > 0.45:
        return "memory-bandwidth"
    return "mixed"


# ---------------------------------------------------------------------------
# Sélection par layer : quelle quantification pour quelle précision /
# goulot débit RAM / taille sur RAM ?
# ---------------------------------------------------------------------------

def _fmt_size(params, name):
    reg = W_FORMATS.get(name) or GGML_FORMATS.get(name)
    return int(params * 2 * reg["size_mult"]) if reg else None


def _fmt_loss(name):
    return LOSS_EST.get(name, 1.0)


def allocation_bytes(allocation, layers):
    return sum(_fmt_size(l["params"], a["format"]) or 0
               for l, a in zip(layers, allocation))


def select_layer_formats(layers, budget_bytes=None, formats=None,
                         class_floors=None, class_default=None,
                         max_loss_pct=1.5, bandwidth_bound=True):
    """Choisit le format par layer sous contraintes précision + budget RAM.

    layers       : [{"id", "params", "class"}] (class in CLASS_FLOORS)
    budget_bytes : plafond RAM poids (None = pas de contrainte) — contrainte dure
    formats      : noms candidats (WnAm ou GGML), None = W_FORMATS
    max_loss_pct : perte de qualité MAX PAR LAYER (plafond, pas une somme)
    bandwidth_bound : si True, TG ≈ 1/octets → minimiser les octets ;
                      si False (compute-bound), la taille n'apporte pas de TG.

    Stratégie : allocation de référence = précision max par layer (sous les
    planchers), puis réduction layer par layer par ordre de
    « octets gagnés par point de perte » jusqu'à tenir dans le budget.
    Retourne {layers: [...], total_bytes, total_loss_pct, est_tg_ratio,
              feasible, constraint_violations}.
    """
    formats = formats or list(W_FORMATS)
    floors = dict(class_floors or CLASS_FLOORS)
    defaults = dict(class_default or CLASS_DEFAULT)
    reg = {n: W_FORMATS.get(n) or GGML_FORMATS.get(n) for n in formats}

    def allowed(layer):
        cls = layer.get("class", "mlp")
        floor = floors.get(cls, 4)
        return [f for f in formats
                if reg[f]["Wbits"] >= floor and _fmt_loss(f) <= max_loss_pct]

    # Allocation de référence : précision maximale parmi les candidats autorisés.
    alloc = []
    total = 0
    for l in layers:
        cands = allowed(l)
        if not cands:
            return {"layers": [], "total_bytes": 0, "total_loss_pct": 0.0,
                    "est_tg_ratio": 1.0, "feasible": False,
                    "constraint_violations":
                        [{"layer": l["id"], "violation": "aucun_format_permis",
                          "floor": floors.get(l.get("class", "mlp"), 4),
                          "max_loss_pct": max_loss_pct}]}
        f = max(cands, key=lambda n: reg[n]["Wbits"])
        cls = l.get("class", "mlp")
        if f not in reg and cls in defaults and defaults[cls] in reg:
            f = defaults[cls]
        size = _fmt_size(l["params"], f)
        alloc.append({"layer": l["id"], "class": cls, "format": f,
                      "Wbits": reg[f]["Wbits"], "size_bytes": size,
                      "loss_pct": _fmt_loss(f)})
        total += size or 0
    ref_bytes = total  # allocation de référence (précision max)

    # Contraintes : plancher par classe.
    viol = []
    for a, l in zip(alloc, layers):
        floor = floors.get(a["class"], 4)
        if a["Wbits"] < floor:
            viol.append({"layer": a["layer"], "violation": "precision_floor",
                         "got": a["Wbits"], "min": floor})

    # Réduction layer par layer : meilleur octets-per-loss d'abord.
    if budget_bytes is not None and total > budget_bytes:
        improvable = []
        for idx, (a, l) in enumerate(zip(alloc, layers)):
            cur_size = a["size_bytes"] or 0
            for cand in allowed(l):
                if cand == a["format"]:
                    continue
                new_size = _fmt_size(l["params"], cand)
                saved = cur_size - (new_size or 0)
                added = max(_fmt_loss(cand) - a["loss_pct"], 1e-6)
                if saved > 0:
                    improvable.append((idx, cand, saved / added))
        improvable.sort(key=lambda t: -t[2])
        for idx, cand, _ in improvable:
            if total <= budget_bytes:
                break
            a = alloc[idx]
            l = layers[idx]
            old_size = a["size_bytes"] or 0
            new_size = _fmt_size(l["params"], cand) or 0
            if new_size >= old_size:
                continue
            total += new_size - old_size
            a.update(format=cand, Wbits=reg[cand]["Wbits"],
                     size_bytes=new_size, loss_pct=_fmt_loss(cand))
    if total > (budget_bytes or float("inf")):
        viol.append({"violation": "ram_budget", "total_bytes": total,
                     "budget_bytes": budget_bytes})

    base = ref_bytes or 1
    est = base / total if bandwidth_bound else 1.0
    return {"layers": alloc, "total_bytes": total,
            "total_loss_pct": round(sum(a["loss_pct"] for a in alloc), 3),
            "est_tg_ratio": round(est, 3), "feasible": not viol,
            "constraint_violations": viol}


def profile_compare(profiles):
    """Compare les mêmes layers/formats sur plusieurs runtimes/backends.

    profiles : liste de layer_profile (même modèle, même précision).
    Retourne le facteur runtime-to-runtime par layer, pour distinguer
    format (constant) vs implémentation (varie selon runtime).
    """
    by_key = {}
    for p in profiles:
        by_key.setdefault(p["layer"], []).append(p)
    out = []
    for layer, rows in sorted(by_key.items()):
        base = None
        for r in rows:
            if r["runtime"] == "ggml" and base is None:
                base = r["total_us"]
        for r in rows:
            factor = (base / r["total_us"]) if base and r.get("total_us") \
                else None
            out.append({**r, "factor_vs_ggml": round(factor, 3)
                        if factor else None})
    return out


# ---------------------------------------------------------------------------
# Challenger : confronter le code, les résultats et la littérature.
# ---------------------------------------------------------------------------

def challenge_measurement(measured, prior, threshold=0.20):
    """mesuré vs littérature (prior). Verdict + diagnostic.

    prior : {"source", "claim_tps", "note"} (ex. papier alphaXiv).
    Le but : ne PAS conclure « Q4_0 est meilleur que W4A16 » si l'écart
    vient du runtime ou du backend, pas du format.

    Diagnostic "compiler-precision-cast" (datavorous) : QAIRT peut downgrader
    silencieusement FP32->FP16/BF16 pendant le placement (relaxed_precision_
    cast) sans prévenir. Si le mesuré diverge du claim SANS changement de
    quant ni de backend, c'est l'hypothèse n°1.
    """
    claim = prior.get("claim_tps")
    if not claim or not measured:
        return {"verdict": "no_data", "measured": measured, "prior": prior}
    factor = measured / claim
    ok = abs(factor - 1.0) <= threshold
    diag = None
    if not ok:
        if abs(1 - factor) <= threshold * 2:
            diag = "format"
        else:
            # écart important sans cause explicite -> cast silencieux possible
            # (surtout si le prior est QAIRT et le format identique)
            src = str(prior.get("source", "")).lower()
            diag = "compiler-precision-cast" if "qairt" in src or "qnn" in src \
                else "runtime/implémentation"
    return {"verdict": "ok" if ok else "discrepancy",
            "factor": round(factor, 3), "measured_tps": measured,
            "claim_tps": claim, "source": prior.get("source"),
            "diagnosis": diag,
            "note": prior.get("note")}


def challenge_layer(profile, ref_profile, threshold=0.20):
    """Même layer, même format : runtime A vs runtime B (ex. QAIRT vs GGML).
    Isole le facteur d'implémentation, indépendant du format."""
    if not ref_profile.get("total_us") or not profile.get("total_us"):
        return None
    factor = ref_profile["total_us"] / profile["total_us"]
    return {"layer": profile["layer"], "format": profile["weight_format"],
            "runtime_a": ref_profile["runtime"], "runtime_b": profile["runtime"],
            "factor_b_vs_a": round(factor, 3),
            "consistent": abs(factor - 1.0) <= threshold}


def challenge_report(measured_tps, prior, profiles=None, ref_profile=None):
    """Rapport complet de challenge : littérature + runtime + par layer."""
    out = {"ts": time.time(),
           "literature": challenge_measurement(measured_tps, prior),
           "runtime": challenge_layer(profiles and profiles[0], ref_profile)
           if profiles and ref_profile else None,
           "layers": profile_compare(profiles) if profiles else []}
    out["verdict"] = ("ok" if out["literature"]["verdict"] == "ok"
                      else "challenge_failed")
    return out


# ---------------------------------------------------------------------------
# CLI démo : sélection par layer sur un modèle synthétique (~Qwen3-8B).
# ---------------------------------------------------------------------------

def demo_layers(n_attn=28, params_attn=1.2e8, params_mlp=1.5e8,
                params_embed=1.5e8):
    """Modèle synthétique ~Qwen3-8B (≈7.9 G params au total)."""
    layers = []
    for i in range(n_attn):
        layers.append({"id": f"layer.{i}", "params": params_attn,
                       "class": "attn"})
        layers.append({"id": f"layer.{i}.mlp", "params": params_mlp,
                       "class": "mlp"})
    layers.append({"id": "norm.0", "params": 4096, "class": "norm"})
    layers.append({"id": "norm.final", "params": 4096, "class": "norm"})
    layers.append({"id": "embed", "params": params_embed, "class": "embed"})
    layers.append({"id": "lm_head", "params": params_embed, "class": "lm_head"})
    return layers


if __name__ == "__main__":
    layers = demo_layers()
    for budget in (None, 5_000_000_000, 3_000_000_000):
        r = select_layer_formats(layers, budget_bytes=budget)
        print(json.dumps({"budget": budget, **r}, ensure_ascii=False, indent=2))