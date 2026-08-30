"""Bloc 09 — Cost model D2 : bandwidth effectif recalibré par les mesures réelles.

Rappel : model size ≠ working-set size ≠ runtime cost.
"""
import json
import os

DEFAULT_CAL = {"gbs": 32.4, "tg_ref_tok_s": 5.95}


class CostModel:
    def __init__(self, path, state_key="default"):
        self.path = path
        self.state_key = state_key
        self.data = {}
        self._load()

    def _load(self):
        if os.path.exists(self.path):
            try:
                with open(self.path, encoding="utf-8") as f:
                    self.data = json.load(f)
            except Exception:
                self.data = {}
        self.data.setdefault("models", {})
        self.data.setdefault("history", [])

    def save(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.data, f, ensure_ascii=False, indent=2)

    def get_state(self, key=None):
        """État de calibration PAR BACKEND (GGML ~31 Go/s ≠ QAIRT ~75 Go/s)."""
        k = key or self.state_key
        st = self.data["models"].setdefault(
            k,
            {"bw_eff_gbs": DEFAULT_CAL["gbs"], "samples": 0,
             "backend": None, "driver": None, "thermal": None},
        )
        return st

    def predict_tps(self, weight_gb, kv_bytes_per_token=0.0, ctx_tokens=4096,
                    backend=None):
        """tps prédit = BW_eff / octets streamés par token (decode memory-bound).
        Rappel : BW_eff en Go/s, octets/token = poids (+ KV si précisé)."""
        st = self.get_state(backend)
        bytes_total_gb = weight_gb + kv_bytes_per_token * ctx_tokens / 1e9
        gbs = st["bw_eff_gbs"]
        return round(gbs / bytes_total_gb if bytes_total_gb else 0.0, 3)

    def update(self, measured_tps, weight_gb, backend=None, driver=None,
               thermal=None, alpha=0.35):
        """EMA sur la bande passante effective implicite PAR BACKEND.
        BW_implicite = tps mesuré × octets/token (pas weight/tps : inversion).
        Chaque backend a sa propre calibration (bloc 19)."""
        key = backend or self.state_key
        st = self.get_state(key)
        context_changed = any(st[k] is not None and v is not None and st[k] != v
                              for k, v in (("driver", driver),
                                           ("thermal", thermal)))
        if context_changed:
            st["samples"] = 0
        implied_bw = measured_tps * weight_gb if measured_tps > 0 \
            else st["bw_eff_gbs"]
        a = 1.0 if st["samples"] == 0 else alpha
        st["bw_eff_gbs"] = round((1 - a) * st["bw_eff_gbs"] + a * implied_bw, 3)
        st["samples"] += 1
        st["backend"], st["driver"], st["thermal"] = backend or st["backend"], \
            driver or st["driver"], thermal or st["thermal"]
        self.data["history"].append({
            "measured_tps": measured_tps, "weight_gb": weight_gb,
            "implied_bw_gbs": round(implied_bw, 3), "backend": backend,
            "thermal": thermal,
        })
        self.save()
        return st["bw_eff_gbs"]

    def needs_recalibration(self, last_measured_tps, weight_gb, tolerance=0.20,
                            backend=None):
        pred = self.predict_tps(weight_gb, backend=backend)
        if not pred:
            return True
        return abs(last_measured_tps - pred) / pred > tolerance
