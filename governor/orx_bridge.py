"""Pont réel governor ↔ OpenResearch CLI (`orx`).

Sans lui, l'intégration orx est cosmétique : ici chaque variante acceptée
devient un nœud de l'arbre d'expériences orx, et la littérature passe par
alphaXiv/OpenAlex. Tout dégrade gracieusement si le binaire est absent.
"""
import json
import os
import subprocess

DEFAULT_ORX = r"D:\openresearch-cli\target\debug\orx.exe"
PROJECT_NAME = "geniex_harness"


class OrxBridge:
    def __init__(self, binary=None, project_name=PROJECT_NAME):
        self.binary = binary or os.environ.get("ORX_BIN", DEFAULT_ORX)
        self.project_name = project_name
        self._pid = None

    def available(self):
        return os.path.exists(self.binary)

    def _run(self, args, timeout=60):
        proc = subprocess.run([self.binary, *args], capture_output=True,
                              text=True, timeout=timeout,
                              encoding="utf-8", errors="replace")
        out = (proc.stdout or "") + (proc.stderr or "")
        return proc.returncode, out.strip()

    # -- projets ---------------------------------------------------------------
    def find_project(self):
        if not self.available():
            return None
        rc, out = self._run(["projects"])
        if rc != 0:
            return None
        for line in out.splitlines():
            if self.project_name in line:
                self._pid = line.split()[0]
                return self._pid
        return None

    def project(self):
        pid = self._pid or self.find_project()
        if not pid:
            return {"error": f"projet '{self.project_name}' introuvable "
                             "(lancer `orx up` dans le repo)"}
        rc, out = self._run(["project", "view", pid])
        return {"ok": rc == 0, "output": out}

    # -- arbre d'expériences ----------------------------------------------------
    def create_experiment(self, title, description="", parent=None):
        """Nœud d'expérimentation tracé : commit archivé, lineage parent."""
        pid = self._pid or self.find_project()
        if not pid:
            return {"ok": False, "error": "orx indisponible ou projet absent"}
        args = ["create-experiment", pid, "--title", title]
        if description:
            args += ["--description", description]
        if parent:
            args += ["--parent", parent]
        rc, out = self._run(args)
        exp_id = None
        for line in out.splitlines():
            s = line.strip()
            if s.startswith("id:") and len(s) > 3:
                exp_id = s.split()[1]
                break
        return {"ok": rc == 0, "experiment_id": exp_id, "output": out[-500:]}

    def status(self, exp_id):
        return self._run(["exp", "status", exp_id])[1]

    def runs(self):
        pid = self._pid or self.find_project()
        if not pid:
            return {"error": "projet absent"}
        rc, out = self._run(["runs", pid])
        return {"ok": rc == 0, "output": out}

    # -- littérature --------------------------------------------------------------
    def discover_keyword(self, query, limit=5):
        rc, out = self._run(["discover", "keyword", "--limit", str(limit),
                             query], timeout=90)
        return {"ok": rc == 0, "results": out}

    def paper(self, paper_id):
        rc, out = self._run(["paper", paper_id], timeout=90)
        return {"ok": rc == 0, "output": out[:4000]}
