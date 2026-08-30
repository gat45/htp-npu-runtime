"""Blocs 03+17+21 — Engine v2 : noyau générique branché sur un ProjectAdapter.

La boucle reste : OBSERVE → RETRIEVE → ESTIMATE → RANK (policy) → EXECUTE
→ MEASURE → ATTRIBUTE → COMMIT/ROLLBACK/STOP → MEMORY UPDATE.
"""
import json
import os
import time

from .adapter import D2Adapter
from .causal import CausalMemory
from .capability import gate, pareto_front, split_sets
from .control import control_actions
from .cost_model import CostModel
from .policy import DecisionPolicy
from .provenance import ProvenanceMemory
from .state import State
from .test_selection import BudgetManager, TestSelector
from .uncertainty import Calibrator


class Governor:
    def __init__(self, root=None, config=None, adapter=None):
        self.root = root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        cfg = config or {}
        gdir = os.path.join(self.root, "governor_state")
        pcfg = cfg.get("policy") or {}

        self.adapter = adapter or self._make_adapter(cfg)
        cons = self.adapter.constraints()
        self.policy = DecisionPolicy(
            lam=pcfg.get("lam", 0.5), alpha=pcfg.get("alpha", 1.0),
            beta=pcfg.get("beta", 1.0), kappa=pcfg.get("kappa", 0.25),
            rmax=pcfg.get("rmax", cons.get("rmax", 0.5)))
        self.state = State(
            root=self.root,
            model=cfg.get("model_alias", ""),
            backend=cfg.get("backend", "geniex-multi"),
            device_map=cfg.get("device_map", "hybrid"),
            precision=cfg.get("precision", "Q4_0"),
            ngl=cfg.get("ngl", 60))
        self.cost_model = CostModel(cfg.get(
            "cost_model_path", os.path.join(gdir, "cost_model.json")))
        self.memory = ProvenanceMemory(cfg.get(
            "memory_path", os.path.join(gdir, "provenance.json")))
        self.causal = CausalMemory(cfg.get(
            "causal_path", os.path.join(gdir, "causal.json")))
        self.calibrator = Calibrator(path=cfg.get(
            "calibrator_path", os.path.join(gdir, "calibrator.json")))
        limits = cfg.get("budget_limits") or self.adapter.resources()
        self.budget = BudgetManager(limits)
        pool = cfg.get("task_pool") or self.adapter.test_pool()
        self.selector = TestSelector(pool)
        self.journal_path = os.path.join(gdir, "journal.jsonl")
        self.variants_file = os.path.join(gdir, "variants.json")
        self.weight_gb = cfg.get("weight_gb", 5.066)
        self.orx = None
        try:
            from .orx_bridge import OrxBridge
            self.orx = OrxBridge()
        except Exception:
            pass
        self.stop_rules = dict({"min_marginal_gain": 0.03,
                                "max_iterations": 8},
                               **(cfg.get("stop_rules") or {}))

    def _make_adapter(self, cfg):
        """Adapter sélectionnable via config `adapter`: d2|op15 (extensible)."""
        name = (cfg or {}).get("adapter", "d2")
        if name == "op15":
            try:
                from .op15 import Op15Adapter
                return Op15Adapter(root=self.root, d2root=cfg.get("d2root"))
            except Exception:
                pass
        return D2Adapter(root=self.root, d2root=cfg.get("d2root"))

    # -- persistance ----------------------------------------------------------
    def _journal(self, record):
        os.makedirs(os.path.dirname(self.journal_path), exist_ok=True)
        with open(self.journal_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    def _load_variants(self):
        if os.path.exists(self.variants_file):
            try:
                with open(self.variants_file, encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_variants(self, variants):
        os.makedirs(os.path.dirname(self.variants_file), exist_ok=True)
        with open(self.variants_file, "w", encoding="utf-8") as f:
            json.dump(variants, f, ensure_ascii=False, indent=2)

    # -- blocs 02+04 : percevoir et décider -----------------------------------
    def decide(self):
        snap = self.state.snapshot()
        hw_state = self.adapter.observe_state()
        if hw_state:
            snap["hardware_summary"].update(hw_state)
            if hw_state.get("thermal"):
                self.state.thermal_state = hw_state["thermal"]

        space = list(self.adapter.action_space())
        risk_exposure = self._risk_exposure()
        future_gain = self._expected_future_gain(space)
        space += control_actions(risk_exposure, future_gain)

        total = float(self.budget.limits["compute_min"])
        left = max(0.0, total - self.budget.spent["compute_min"])
        ranked = self.policy.rank(space, total, left)
        thermal_gate = False
        if hw_state and hw_state.get("thermal") == "hot":
            tmax = self.adapter.constraints().get("temp_max", 70.0)
            heavy = [r for r in ranked if r.get("cost_min", 0) > 8]
            if heavy:
                cool = [r for r in ranked if r.get("cost_min", 0) <= 8]
                if cool:
                    ranked = cool
                    thermal_gate = True
        return {"snapshot": snap, "ranked": ranked[:5],
                "budget": self.budget.status(),
                "policy": self.policy.state_dict(),
                "risk_exposure": risk_exposure,
                "thermal_gate": thermal_gate}

    def _risk_exposure(self):
        """Risque courant : variantes acceptées jamais re-validées + dérive."""
        variants = [v for k, v in self._load_variants().items()
                    if not k.startswith("_") and k != "baseline"]
        stale = sum(1 for v in variants if not v.get("gate", {}).get("accept"))
        drift = min(1.0, len(self.calibrator.history) and
                    self.calibrator.std() / 0.5 or 0.0)
        return round(min(1.0, 0.25 * stale + 0.5 * drift), 3)

    def _expected_future_gain(self, space):
        known = [self.policy.ev(a) for a in space if a.kind != "stop"]
        unseen = [a for a in space if a.name not in self.policy.gain_hist]
        base = max(known) if known else 0.0
        bonus = 2.0 * len(unseen) if unseen else 0.0
        return round(max(0.0, base + bonus), 3)

    # -- blocs 05→20 : exécuter un cycle --------------------------------------
    def step(self, dry_run=False):
        decision = self.decide()
        if not decision["ranked"]:
            return {"stopped": True, "reason": "aucune action faisable"}
        top = decision["ranked"][0]

        if top["kind"] == "stop":
            self._journal({"ts": time.time(), "trace_id": self.state.trace_id,
                           "action": "stop", "utility": top["utility"]})
            return {"stopped": True, "reason": "U(stop) ≥ U(action)",
                    "last_utility": top["utility"]}

        spec = next((a for a in self.adapter.action_space()
                     if a.name == top["action"]), None)
        if spec is None:
            if top["kind"] == "rollback":
                rb = self.adapter.rollback_last()
                self._journal({"ts": time.time(), "action": "rollback",
                               **rb})
                return {"stopped": False, "control": "rollback", **rb}
            return {"stopped": False, "control": top["kind"]}

        if not self.budget.can_afford(spec.cost_min):
            return {"stopped": True, "reason": "budget épuisé"}

        run_id = time.strftime("%Y%m%d_%H%M%S")
        ctx = {"run_dir": os.path.join(self.root, "bench_results",
                                       f"gov_{run_id}"),
               "dry_run": dry_run, "cwd": self.root, "ngl": self.state.ngl,
               "d2root": getattr(self.adapter, "d2root", None)}

        std_before = self.calibrator.std()
        raw = self.adapter.execute(spec, ctx)
        measured = self.adapter.measure(raw)
        self.budget.spend(spec.cost_min)

        predicted = self.cost_model.predict_tps(self.weight_gb,
                                                backend=self.state.backend)
        delta_v = info_gain = None
        tps = measured.get("tps")
        if tps and predicted:
            dev = (tps - predicted) / predicted
            self.calibrator.add(predicted, tps)
            std_after = self.calibrator.std()
            info_gain = max(0.0, std_before - std_after)
            baseline_tps = self._baseline_tps()
            if baseline_tps:
                delta_v = round((tps - baseline_tps) / baseline_tps * 100.0, 3)
            self.cost_model.update(tps, self.weight_gb,
                                   backend=self.state.backend,
                                   thermal=self.state.thermal_state)
        self.policy.record_outcome(spec.name, delta_v=delta_v,
                                   info_gain=info_gain)
        if delta_v is not None:
            self.causal.record([spec.name], delta_v,
                               context={"kind": spec.kind,
                                        "backend": self.state.backend})

        entry = {"ts": time.time(), "trace_id": self.state.trace_id,
                 "action": spec.name, "kind": spec.kind,
                 "policy_version": self.policy.VERSION,
                 "utility_chosen": top["utility"],
                 "ranked_top3": [(r["action"], r["utility"])
                                 for r in decision["ranked"][:3]],
                 "predicted_tps": predicted,
                 "measured_tps": tps, "delta_v_pct": delta_v,
                 "info_gain": None if info_gain is None else round(info_gain, 5),
                 "ok": raw.get("ok", False)}
        self._journal(entry)
        self.state.previous_decision = entry
        return {"stopped": False, "result": raw, "entry": entry}

    def _baseline_tps(self):
        hist = self.cost_model.data.get("history", [])
        return hist[0]["measured_tps"] if hist else None

    # -- blocs 11+12+17 : attribution, gate, Pareto ---------------------------
    def attribute_and_gate(self, h1_caps, baseline="baseline"):
        variants = self._load_variants()
        h0 = variants.get(baseline)
        if not h0:
            return {"error": f"baseline '{baseline}' absente"}
        verdict = gate(h0["caps"], h1_caps)
        h1_id = f"variant_{len(variants)}_{time.strftime('%H%M%S')}"
        variants[h1_id] = {"caps": h1_caps, "gate": verdict,
                           "parent": baseline, "trace_id": self.state.trace_id}
        front = [v for v in pareto_front(
            [{"id": k, **v["caps"]} for k, v in variants.items()
             if not k.startswith("_")])]
        variants["_pareto_front"] = [f["id"] for f in front]
        self._save_variants(variants)
        if verdict["accept"]:
            self.memory.write(f"harness:{h1_id}",
                              {"caps": h1_caps, "delta": verdict["delta"]},
                              source=f"governor:{self.state.trace_id}",
                              confidence=self.calibrator.confidence())
            self.causal.record(["variant:" + h1_id], verdict["aggregate_pct"],
                               context={"kind": "modify"})
        else:
            self.adapter.rollback_last() and None

        orx_node = None
        if self.orx and self.orx.available():
            try:
                parent = variants.get("_orx_last")
                r = self.orx.create_experiment(
                    h1_id,
                    description=f"accept={verdict['accept']} "
                                f"delta={verdict['delta']} "
                                f"policy={self.policy.VERSION}",
                    parent=parent)
                if r.get("experiment_id"):
                    variants["_orx_last"] = r["experiment_id"]
                    self._save_variants(variants)
                orx_node = r.get("experiment_id")
            except Exception:
                pass
        return {"accepted": verdict["accept"], "variant_id": h1_id,
                "verdict": verdict,
                "pareto_front": variants["_pareto_front"],
                "memory": verdict["accept"], "orx_node": orx_node}

    def should_stop(self, last_gain_pct=None):
        reasons = []
        if self.budget.exhausted():
            reasons.append("budget compute épuisé")
        if last_gain_pct is not None and \
                abs(last_gain_pct) < self.stop_rules["min_marginal_gain"]:
            reasons.append("gain marginal sous le seuil")
        return {"stop": bool(reasons), "reasons": reasons}

    # -- rapport ---------------------------------------------------------------
    def report(self):
        variants = self._load_variants()
        return {
            "adapter": self.adapter.id,
            "state": self.state.snapshot(),
            "calibration": {"samples": len(self.calibrator.history),
                            "confidence": round(self.calibrator.confidence(), 3)},
            "budget": self.budget.status(),
            "cost_model": self.cost_model.get_state(),
            "meta_rules": self.causal.meta_rules(),
            "variants": {k: v for k, v in variants.items()
                         if not k.startswith("_")},
            "pareto_front": variants.get("_pareto_front", []),
            "next_sets": split_sets([k for k in variants
                                     if not k.startswith("_")] or ["seed"]),
        }
