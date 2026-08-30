"""Bloc 02 — Memory / RAG / Provenance : WRITE → VALIDATE → STORE, FORGET/ROLLBACK.

Journal append-only : on ne réécrit jamais l'historique, on supersede.
Protection contre memory poisoning / stale knowledge.
"""
import hashlib
import json
import os
import time

TRUSTED_PREFIXES = ("bench:", "governor:", "crossref:", "orx:", "T")


def _trusted_source(source):
    return isinstance(source, str) and source.startswith(TRUSTED_PREFIXES)


class ProvenanceMemory:
    def __init__(self, path):
        self.path = path
        self.entries = []
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as f:
                    self.entries = json.load(f)
            except Exception:
                self.entries = []

    def _save(self):
        tmp = self.path + ".tmp"
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.entries, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.path)

    @staticmethod
    def _digest(payload):
        return hashlib.sha256(json.dumps(payload, sort_keys=True,
                                         ensure_ascii=False).encode()).hexdigest()[:16]

    def validate(self, fact):
        """Un fait n'entre en mémoire QUE s'il est complet et sourcé (bloc 22 :
        update seulement si quality/cost/risk/provenance OK)."""
        required = ("key", "value", "source")
        missing = [k for k in required if not fact.get(k)]
        if missing:
            return False, f"champs manquants: {missing}"
        if fact.get("confidence", 1.0) < 0.3:
            return False, "confiance trop faible"
        if fact.get("reproducible") is False:
            return False, "non reproductible"
        return True, ""

    def write(self, key, value, source, confidence=1.0, trace_id=None,
              reproducible=True):
        fact = {"key": key, "value": value, "source": source,
                "confidence": confidence, "ts": time.time(),
                "trace_id": trace_id, "reproducible": reproducible}
        ok, why = self.validate(fact)
        if not ok:
            return {"stored": False, "reason": why}
        prior = self.get(key)
        entry = dict(fact)
        entry["quarantine"] = confidence < 0.7 or not _trusted_source(source)
        entry["supersedes"] = prior["digest"] if prior else None
        entry["digest"] = self._digest(entry)
        self.entries.append(entry)
        self._save()
        return {"stored": True, "digest": entry["digest"],
                "quarantined": entry["quarantine"],
                "superseded": bool(prior)}

    def promote(self, digest):
        """Sort une entrée de quarantaine après vérification humaine/validée."""
        for e in self.entries:
            if isinstance(e, dict) and e.get("digest") == digest \
                    and e.get("quarantine"):
                e2 = dict(e)
                e2["quarantine"] = False
                e2["promoted_from"] = digest
                e2["ts"] = time.time()
                del e2["digest"]
                e2["digest"] = self._digest(e2)
                self.entries.append(e2)
                self._save()
                return {"promoted": True, "new_digest": e2["digest"]}
        return {"promoted": False}

    def get(self, key):
        live = [e for e in self.entries
                if isinstance(e, dict) and e.get("key") == key
                and e.get("value") is not None
                and not e.get("quarantine")
                and not self._is_superseded(e)]
        return max(live, key=lambda e: e["ts"], default=None)

    def get_including_quarantine(self, key):
        live = [e for e in self.entries
                if isinstance(e, dict) and e.get("key") == key
                and e.get("value") is not None
                and not self._is_superseded(e)]
        return max(live, key=lambda e: e["ts"], default=None)

    def _is_superseded(self, entry):
        if not isinstance(entry, dict) or "digest" not in entry:
            return False
        return any(isinstance(o, dict) and o.get("supersedes") == entry["digest"]
                   for o in self.entries)

    def forget(self, key):
        """Bloc 02 — FORGET : marqué, jamais supprimé (rollback possible)."""
        target = self.get(key)
        if not target:
            return {"forgotten": False}
        tomb = {"key": key, "value": None, "source": "governor.forget",
                "confidence": 1.0, "ts": time.time(),
                "supersedes": target["digest"]}
        tomb["digest"] = self._digest(tomb)
        self.entries.append(tomb)
        self._save()
        return {"forgotten": True, "digest": tomb["digest"]}

    def rollback(self, digest):
        """Bloc 20 — ROLLBACK mémoire : restaure une version antérieure."""
        target = next((e for e in self.entries if e["digest"] == digest), None)
        if not target:
            return {"rolled_back": False, "reason": "digest inconnu"}
        current = self.get(target["key"])
        rest = {k: v for k, v in target.items()
                if k not in ("digest", "supersedes", "ts")}
        rest["source"] = "governor.rollback"
        rest["ts"] = time.time()
        rest["supersedes"] = current["digest"] if current else None
        rest["digest"] = self._digest(rest)
        self.entries.append(rest)
        self._save()
        return {"rolled_back": True, "key": target["key"],
                "restored_digest": digest}

    def query(self, keywords):
        kws = [k.lower() for k in keywords.split()] if isinstance(keywords, str) \
            else [str(k).lower() for k in keywords]
        out = []
        for e in self.entries:
            if not isinstance(e, dict) or "key" not in e:
                continue
            if e.get("quarantine") or self._is_superseded(e) \
                    or e["value"] is None:
                continue
            blob = json.dumps(e, ensure_ascii=False).lower()
            score = sum(1 for k in kws if k in blob)
            if score:
                out.append((score, e))
        out.sort(key=lambda p: (-p[0], -p[1]["ts"]))
        return [e for _, e in out[:5]]
