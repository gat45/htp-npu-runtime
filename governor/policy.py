"""Noyau décisionnel formalisé (bloc 03) :

    a* = argmax_a [ E[ΔV|a,s] + λ·Î(θ;Y|a,s) − α·C(a) − β·R(a) ]
    s.c. C(a) ≤ B_t,  R(a) ≤ R_max,  G(a) ≥ G_min

Chaque terme est ESTIMÉ empiriquement, pas déclaré :
- E[ΔV]  : moyenne des gains mesurés après exécution de ce type d'action
- Î      : réduction d'incertitude observée (écart-type calibrateur avant/après)
- bonus UCB pour l'exploration : κ·sqrt(ln N / n_a)
"""
import math


class DecisionPolicy:
    VERSION = "2.1-lcb"  # versionné (gouvernance du governor lui-même)

    def __init__(self, lam=0.5, alpha=1.0, beta=1.0, kappa=0.25,
                 rmax=0.5, overhead_min=0.2, q=0.7):
        self.lam = lam
        self.alpha = alpha
        self.beta = beta
        self.kappa = kappa
        self.rmax = rmax
        self.overhead_min = overhead_min
        self.q = q
        self.gain_hist = {}
        self.ig_hist = {}
        self.n_total = 0

    def state_dict(self):
        return {"version": self.VERSION,
                "lam": self.lam, "alpha": self.alpha, "beta": self.beta,
                "kappa": self.kappa, "rmax": self.rmax, "q": self.q,
                "n_total": self.n_total,
                "known_actions": sorted(set(list(self.gain_hist)
                                            + list(self.ig_hist)))}

    # -- estimation empirique -------------------------------------------------
    def record_outcome(self, action_name, delta_v=None, info_gain=None):
        if delta_v is not None:
            self.gain_hist.setdefault(action_name, []).append(delta_v)
        if info_gain is not None:
            self.ig_hist.setdefault(action_name, []).append(max(0.0, info_gain))
        self.n_total += 1

    def set_prior(self, priors, weight=2):
        """Injection de méta-connaissance cross-projet (causal.meta_rules /
        mémoire d'un autre domaine). Chaque prior compte comme `weight`
        observations fictives."""
        for name, mean in (priors or {}).items():
            self.gain_hist[name] = [float(mean)] * int(weight)

    def ev(self, action):
        """LCB prudent sur E[ΔV] : moyenne − z_q·écart-type/√n (bloc 03 :
        une estimation très incertaine n'est jamais un gain acquis).
        Sans données : prior grossier dérivé du gain d'info attendu."""
        h = self.gain_hist.get(action.name)
        if not h:
            return float(action.info_gain) * 30.0
        mean = sum(h) / len(h)
        if len(h) < 2:
            return mean
        std = math.sqrt(sum((x - mean) ** 2 for x in h) / (len(h) - 1))
        z = {0.5: 0.0, 0.7: 0.524, 0.8: 0.842, 0.9: 1.282, 0.95: 1.645}
        return max(min(h), mean - z.get(self.q, 0.524) * std / math.sqrt(len(h)))

    def ig(self, action):
        """Î estimé (réduction d'incertitude observée). Neutre tant que rien
        n'est mesuré : un prior fantaisiste ici n'est que du bruit."""
        h = self.ig_hist.get(action.name)
        return sum(h) / len(h) if h else 0.05

    def _ucb(self, action):
        n_a = len(self.gain_hist.get(action.name, []))
        return self.kappa * math.sqrt(math.log(self.n_total + 2) / (n_a + 1))

    # -- utilité et faisabilité ----------------------------------------------
    def utility(self, action, budget_total_min):
        hint = getattr(action, "utility_hint", None)
        if hint is not None:
            return round(hint, 5)
        c_norm = (float(action.cost_min) + self.overhead_min) / \
            max(budget_total_min, 1e-9)
        u = (self.ev(action) / 50.0
             + self.lam * self.ig(action)
             + self._ucb(action)
             - self.alpha * c_norm
             - self.beta * float(action.risk))
        return round(u, 5)

    def feasible(self, action, budget_left_min):
        """Contraintes dures : budget restant et risque maximal."""
        if action.kind == "stop":
            return True
        if float(action.cost_min) + self.overhead_min > budget_left_min:
            return False
        return float(action.risk) <= self.rmax

    def rank(self, actions, budget_total_min, budget_left_min):
        scored = []
        for a in actions:
            if not self.feasible(a, budget_left_min):
                continue
            scored.append({"action": a.name, "kind": a.kind,
                           "utility": self.utility(a, budget_total_min),
                           "cost_min": a.cost_min, "risk": a.risk,
                           "reversible": getattr(a, "reversible", True)})
        scored.sort(key=lambda s: -s["utility"])
        return scored
