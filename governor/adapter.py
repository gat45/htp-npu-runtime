"""Bloc 15 — Project Adapter : contrat abstrait entre le noyau du Governor
et n'importe quel projet. Le noyau ne connaît NI GPU NI LLM NI GGUF.

Contrat : ACTIONS / RESOURCES / METRICS / TESTS / CONSTRAINTS / EXECUTOR.
D2/SNN/quantification = adapters OPTIONNELS, jamais le noyau.
"""
from .actions import REGISTRY

KINDS = ("modify", "evaluate", "ablate", "search", "allocate",
         "rollback", "stop")


class ActionSpec:
    def __init__(self, name, kind, cost_min, risk, info_gain, reversible=True,
                 executor_ref=None):
        if kind not in KINDS:
            raise ValueError(f"kind '{kind}' hors taxonomie {KINDS}")
        self.name = name
        self.kind = kind
        self.cost_min = cost_min
        self.risk = risk
        self.info_gain = info_gain
        self.reversible = reversible
        self.executor_ref = executor_ref


class ProjectAdapter:
    """Toute intégration projet implémente ce contrat — rien d'autre."""

    id = "base"

    def action_space(self):
        raise NotImplementedError

    def resources(self):
        return {"compute_min": 120, "tool_calls": 20, "test_runs": 10}

    def metrics(self):
        return [("quality", "max")]

    def test_pool(self):
        return []

    def constraints(self):
        return {"rmax": 0.5, "gmin": 0.0}

    def observe_state(self):
        return {}

    def execute(self, spec, ctx):
        raise NotImplementedError

    def measure(self, raw):
        return {}

    def rollback_last(self):
        return {"rolled_back": False}


class D2Adapter(ProjectAdapter):
    """Adapter du projet geniex_harness : hardware D2, benchs adb, quant."""

    id = "d2-harness"

    def __init__(self, root=None, d2root=None):
        import os
        self.root = root or os.path.dirname(os.path.dirname(
            os.path.abspath(__file__)))
        self.d2root = d2root
        self._last_variant = None

    def action_space(self):
        specs = [
            ActionSpec("predict_d2", "evaluate", 0.5, 0.05, 0.4),
            ActionSpec("bench_baseline_t0", "evaluate", 8, 0.1, 0.8),
            ActionSpec("bench_variant_ngl", "modify", 8, 0.1, 0.7),
            ActionSpec("prof_stream_thermique", "evaluate", 12, 0.15, 0.6),
            ActionSpec("quant_matrix", "modify", 40, 0.3, 0.9,
                       reversible=False),
            ActionSpec("kv_int8_ablation", "ablate", 15, 0.2, 0.75),
            ActionSpec("search_literature", "search", 1, 0.02, 0.07),
        ]
        for s in specs:
            s.executor_ref = next((a for a in REGISTRY if a.name == s.name), None)
        return specs

    def resources(self):
        return {"compute_min": 120, "tool_calls": 20, "test_runs": 10}

    def metrics(self):
        return [("tps", "max"), ("ram_gb", "min"),
                ("quality_loss_pct", "min"), ("latency_ms", "min")]

    def test_pool(self):
        return ["T0_baseline_cold", "T0_baseline_warm", "T1_qairt_cpu",
                "T2_npu_hybrid_ngl60", "T3_quant_q4_vs_int8",
                "T_adv_thermal_hot"]

    def constraints(self):
        return {"rmax": 0.5, "gmin": -2.0}

    def observe_state(self):
        try:
            import harness_hw
            hw = harness_hw.collect(use_su=False)
            zones = [z for z in hw.get("thermal", [])
                     if isinstance(z, dict)
                     and "trip" not in str(z.get("type", "")).lower()]
            temps = [z["temp_c"] for z in zones
                     if isinstance(z.get("temp_c"), (int, float))]
            thermal = "hot" if temps and max(temps) > 70 else \
                "warm" if temps and max(temps) > 55 else \
                "cool" if temps else "unknown"
            return {"soc": hw.get("soc"), "thermal": thermal,
                    "selinux": hw.get("selinux")}
        except Exception:
            return {}

    def execute(self, spec, ctx):
        if spec.name == "search_literature":
            try:
                from .web_research import research
                q = ctx.get("query") or "on-device LLM NPU inference quantization"
                r = research(q)
                import json as _json
                return {"ok": bool(r["results"]), "action": spec.name,
                        "metrics": {}, "raw": _json.dumps(
                            r["results"][:10], ensure_ascii=False)[:2500]}
            except Exception as e:
                return {"ok": False, "action": spec.name, "error": str(e)}
        ref = spec.executor_ref
        if ref is None or spec.name == "kv_int8_ablation":
            return {"ok": True, "action": spec.name,
                    "simulated": True}
        return ref.execute(ctx, timeout_s=int(spec.cost_min * 120))

    def measure(self, raw):
        m = (raw or {}).get("metrics") or {}
        return {"tps": m.get("tps")} if m else {}

    def rollback_last(self):
        v = self._last_variant
        self._last_variant = None
        return {"rolled_back": v is not None, "variant": v}
