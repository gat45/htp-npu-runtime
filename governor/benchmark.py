"""Test décisif : à BUDGET ÉGAL, la politique gain+info−coût−risque
bat-elle random/greedy/UCB1 ? Métriques : perf/compute et VoI.

Test cross-projet : après exploration du domaine A, les meta-règles
accélèrent-elles la convergence sur un domaine B corrélé mais nouveau ?
Métrique : nb d'évaluations avant de toucher l'action quasi-optimale.

Environnement simulé à vérité cachée ; mesures bruitées ; budgets identiques.
Aucun device requis — c'est le noyau décisionnel qu'on évalue.
"""
import argparse
import json
import random


class SimEnv:
    """Vérité cachée : effets réels par action, mesures bruitées."""

    def __init__(self, actions, truth, noise_pct=2.5):
        self.noise = noise_pct
        self.actions = actions
        self.truth = truth

    def measure(self, name):
        return self.truth[name] + random.gauss(0, self.noise)

    def best_true(self, tried):
        return max((self.truth[n] for n in tried), default=-100.0)


def _make_space(n_mods=6):
    acts = []
    for i in range(n_mods):
        acts.append({"name": f"mod_{chr(65 + i)}",
                     "cost_min": random.Random(1000 + i).choice([4, 6, 8, 12]),
                     "risk": round(random.Random(2000 + i).uniform(.05, .3), 2),
                     "info_gain": round(random.Random(3000 + i).uniform(.1, .5), 2),
                     "lo": -4.0, "hi": 16.0})
    return acts


def run_policy(policy_name, space, env, budget_min, governor_cls=None,
               warm_prior=None, warm_weight=6, patience=3):
    from .adapter import ActionSpec
    from .policy import DecisionPolicy

    spent, tried, means, order = 0.0, {}, {}, []
    stale, best_so_far = 0, -1e18
    pol = DecisionPolicy() if policy_name == "governor" else None
    if pol is not None and warm_prior:
        pol.set_prior(warm_prior, weight=warm_weight)
    ucb_stats = {}

    def _ucb1_pick(cand):
        import math
        n_tot = sum(n for n, _ in ucb_stats.values()) + 1
        best, best_idx = None, -1e18
        for a in cand:
            n_a, m = ucb_stats.get(a["name"], (0, 0.0))
            idx = float("inf") if n_a == 0 else \
                m + 0.5 * math.sqrt(math.log(n_tot) / n_a)
            if idx > best_idx:
                best, best_idx = a, idx
        return best

    while True:
        cand = [a for a in space if spent + a["cost_min"] <= budget_min]
        choice = None
        if not cand:
            pass
        elif policy_name == "random":
            choice = random.choice(cand)
        elif policy_name == "greedy":
            prior = lambda a: means.get(a["name"],
                                        a["hi"] * (1 - a["risk"]))
            choice = max(cand, key=prior)
        elif policy_name == "ucb1":
            choice = _ucb1_pick(cand)
        else:
            specs = [ActionSpec(a["name"], "modify", a["cost_min"],
                                a["risk"], a["info_gain"]) for a in space]
            ranked = pol.rank(specs, budget_min, budget_min - spent)
            if ranked:
                nm = ranked[0]["action"]
                choice = next(a for a in space if a["name"] == nm)

        if choice is None:
            break

        obs = env.measure(choice["name"])
        spent += choice["cost_min"]
        order.append(choice["name"])
        tried.setdefault(choice["name"], []).append(obs)
        means[choice["name"]] = sum(tried[choice["name"]]) / len(tried[choice["name"]])
        n_a, s_old = ucb_stats.get(choice["name"], (0, 0.0))
        ucb_stats[choice["name"]] = (n_a + 1,
                                     (s_old * n_a + obs) / (n_a + 1))
        if pol is not None:
            pol.record_outcome(choice["name"], delta_v=means[choice["name"]])

        best_now = max(means.values())
        if best_now > best_so_far + 1e-9:
            best_so_far, stale = best_now, 0
        else:
            stale += 1
            if stale >= patience:
                break

    return {"best_true": round(env.best_true(tried), 2),
            "spent": round(spent, 1),
            "n_evals": len(order),
            "order": order,
            "policy": pol,
            "tried": {k: len(v) for k, v in tried.items()}}


def _evals_before_hit(res, truth):
    """Nb d'évaluations avant la première mesure de l'action optimale."""
    best_name = max(truth, key=lambda k: truth[k])
    return res["order"].index(best_name) if best_name in res["order"] else None


def run_comparison(budget_min=150, n_mods=12, noise_pct=1.5, seeds=(1, 2, 3, 4, 5)):
    rows = {}
    for seed in seeds:
        space = _make_space(n_mods)
        rng_truth = random.Random(seed)
        truth = {a["name"]: rng_truth.uniform(a["lo"], a["hi"]) for a in space}
        env = SimEnv(space, truth, noise_pct)
        random.seed(seed)
        for pname in ("random", "greedy", "ucb1", "governor"):
            res = run_policy(pname, space, env, budget_min)
            res.pop("policy", None)
            rows.setdefault(pname, []).append(res)

    summary = {}
    for pname, rs in rows.items():
        summary[pname] = {
            "mean_best": round(sum(r["best_true"] for r in rs) / len(rs), 2),
            "mean_spent": round(sum(r["spent"] for r in rs) / len(rs), 1),
            "mean_evals": round(sum(r["n_evals"] for r in rs) / len(rs), 1),
        }
    g = summary["governor"]["mean_best"]
    base = max(summary["random"]["mean_best"], summary["greedy"]["mean_best"],
               summary["ucb1"]["mean_best"])
    eff = {p: round(summary[p]["mean_best"] /
                    max(summary[p]["mean_spent"], 1e-9), 4)
           for p in summary}
    eff_base = max(eff["random"], eff["greedy"], eff["ucb1"])
    if g > base + 0.5:
        verdict = "governor gagne (qualite ET efficacite)"
    elif eff["governor"] > eff_base * 1.02:
        verdict = ("gouverneur equivalent en qualite mais superieur en "
                   "perf/compute — s'arrete plus tot")
    else:
        verdict = "egalite/baseline — noyau non valide"
    voi = {
        "delta_perf_vs_best_baseline": round(g - base, 2),
        "perf_per_compute": eff,
        "voi_per_compute_unit": round((g - base) /
                                      max(summary["governor"]["mean_spent"],
                                          1e-9), 4),
        "verdict": verdict,
    }
    return {"per_seed": rows, "summary": summary, "voi": voi}


def run_transfer(budget_min=150, n_mods=12, noise_pct=1.5, seeds=(11, 12, 13, 14, 15)):
    """Phase A : le governor explore le domaine A → méta-connaissance.
    Phase B (budget réduit) : governor à froid vs « chaud » (priors de A).
    Vérité de B corrélée à A : les mêmes actions tendent à être meilleures.
    Métrique principale : évaluations avant de toucher l'action optimale.
    """
    cold_hits, warm_hits = [], []
    for seed in seeds:
        space = _make_space(n_mods)
        rng = random.Random(seed)
        truth_a = {a["name"]: rng.uniform(a["lo"], a["hi"]) for a in space}
        truth_b = {k: v * 0.85 + rng.uniform(-1.5, 2.5)
                   for k, v in truth_a.items()}

        random.seed(seed)
        res_a = run_policy("governor", space,
                           SimEnv(space, truth_a, noise_pct), budget_min)
        pol_a = res_a.pop("policy")
        priors = {n: sum(v) / len(v)
                  for n, v in pol_a.gain_hist.items() if v}

        b_budget = budget_min * 0.6
        cold = run_policy("governor", space,
                          SimEnv(space, truth_b, noise_pct), b_budget)
        warm = run_policy("governor", space,
                          SimEnv(space, truth_b, noise_pct), b_budget,
                          warm_prior=priors)
        cold.pop("policy"); warm.pop("policy")
        c_hit, w_hit = (_evals_before_hit(cold, truth_b),
                        _evals_before_hit(warm, truth_b))
        if c_hit is not None and w_hit is not None:
            cold_hits.append(c_hit)
            warm_hits.append(w_hit)

    def med(xs):
        xs = sorted(xs)
        return xs[len(xs) // 2] if xs else None

    mc, mw = med(cold_hits), med(warm_hits)
    return {
        "seeds": list(seeds),
        "median_evals_to_best_action_cold": mc,
        "median_evals_to_best_action_warm": mw,
        "verdict": ("transfert validé" if mw < mc else
                    "transfert neutre" if mw == mc else
                    "pas de transfert"),
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser(prog="governor-bench")
    ap.add_argument("--budget", type=float, default=60)
    ap.add_argument("--mods", type=int, default=6)
    ap.add_argument("--noise", type=float, default=2.5)
    ap.add_argument("--transfer", action="store_true")
    args = ap.parse_args()
    out = {"comparison": run_comparison(budget_min=args.budget,
                                        n_mods=args.mods, noise_pct=args.noise)}
    if args.transfer:
        out["transfer"] = run_transfer(budget_min=args.budget,
                                       n_mods=args.mods, noise_pct=args.noise)
    print(json.dumps(out, indent=2))
