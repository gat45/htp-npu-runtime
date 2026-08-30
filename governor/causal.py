"""Bloc 11+cross-project — Mémoire causale : les interactions deviennent des
actifs décisionnels réutilisables entre projets.

    A: +4  B: +2  A+B: +9  ⇒ synergie(A,B)=+3 ⇒ P(recommander A+B|contexte~)↑
"""
import json
import os
import time


class CausalMemory:
    def __init__(self, path):
        self.path = path
        self.records = []
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as f:
                    self.records = json.load(f)
            except Exception:
                self.records = []

    def save(self):
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.records, f, ensure_ascii=False, indent=2)

    def record(self, changes, effect_pct, context=None):
        entry = {"changes": sorted(changes), "effect": round(effect_pct, 3),
                 "context": context or {}, "ts": time.time()}
        self.records.append(entry)
        self.save()
        return entry

    def record_cast_suspect(self, changes, effect_pct, quality_drop_pct,
                            backend="qairt"):
        """Enregistre un cas où la qualité chute SANS changement de quant.

        Context `cast_silencieux=True` (datavorous : relaxed_precision_cast
        pendant le placement QAIRT). Si la qualité régresse alors que le
        format/backend n'a pas changé, l'hypothèse causale n°1 est un
        downgrade de précision par le compilateur.
        """
        ctx = {"kind": "quality-regression",
               "cast_silencieux": True,
               "backend": backend,
               "quality_drop_pct": round(quality_drop_pct, 3)}
        return self.record(changes, effect_pct, context=ctx)

    def _find(self, changes):
        want = sorted(changes)
        return [r for r in self.records if r["changes"] == want]

    def effect(self, changes, default=0.0):
        rs = self._find(changes)
        if not rs:
            return None
        return sum(r["effect"] for r in rs) / len(rs)

    def synergy(self, a, b):
        """Interaction A×B : ce que le combo apporte AU-DELÀ de la somme.
        C'est la causalité comme actif : stockée, requérable, transférable."""
        e_a = self.effect((a,))
        e_b = self.effect((b,))
        e_ab = self.effect((a, b))
        if None in (e_a, e_b, e_ab):
            return None
        return round(e_ab - (e_a + e_b), 3)

    def recommend(self, context=None, k=5):
        """Méta-règles inter-projets : classe les changements connus par
         effet moyen, pondéré par la similarité de contexte."""
        ctx = context or {}
        scored = {}
        for r in self.records:
            overlap = sum(1 for k_, v in ctx.items()
                          if r["context"].get(k_) == v)
            max_overlap = max(1, len(ctx))
            w = (1 + overlap / max_overlap) * (1 + abs(r["effect"]) / 100.0)
            key = tuple(r["changes"])
            prev = scored.get(key)
            cur = {"changes": list(key), "effect": r["effect"],
                   "weight": round(w, 4)}
            if prev is None or abs(cur["effect"]) * cur["weight"] > \
                    abs(prev["effect"]) * prev["weight"]:
                scored[key] = cur
        ranked = sorted(scored.values(),
                        key=lambda c: -c["effect"] * c["weight"])
        return ranked[:k]

    def meta_rules(self):
        """Règles de gouvernance transférables (cross-project memory)."""
        by_kind = {}
        for r in self.records:
            kind = r.get("context", {}).get("kind", "?")
            by_kind.setdefault(kind, []).append(r["effect"])
        out = []
        for kind, effs in sorted(by_kind.items()):
            out.append({"kind": kind, "n": len(effs),
                        "mean_effect": round(sum(effs) / len(effs), 3)})
        return sorted(out, key=lambda m: -m["mean_effect"])
