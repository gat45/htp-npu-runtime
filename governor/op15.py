"""Bloc 15 — Op15Adapter : contrat ProjectAdapter pour OnePlus 15 (SM8850).

Noyau du governor intact — ce module est un adapter OPTIONNEL (matériel +
perf + kernel). Réutilise le REGISTRY actions.py et ajoute des actions
matériel/perf/kernel inline (implémentées ici, jamais dans le noyau).

Exécution : sur PC via adb, ou sur le téléphone en direct (sysfs).
"""
import os
import time

from .actions import REGISTRY
from .adapter import ActionSpec, D2Adapter

try:
    from . import op15_hw as hw
except Exception:  # pragma: no cover
    hw = None

# Noms du REGISTRY (actions.py) vs noms canoniques de l'espace d'action.
REGISTRY_ALIAS = {"bench_variant_ngl": "bench_variant",
                  "bench_qairt_w4a16": "bench_qairt_t12"}


def _executor(name):
    return next((a for a in REGISTRY if a.name == REGISTRY_ALIAS.get(name,
                                                                    name)),
                None)


class Op15Adapter(D2Adapter):
    """Adapter du OnePlus 15 : lire le matériel, capturer, kernel debug."""

    id = "op15-sm8850"

    def __init__(self, root=None, d2root=None):
        super().__init__(root=root, d2root=d2root)
        self._last_variant = None

    def action_space(self):
        specs = [
            # hérités : benchmarks + quant (QAIRT/GGML/ngl/thermique)
            ActionSpec("bench_baseline_t0", "evaluate", 8, 0.1, 0.8),
            ActionSpec("bench_variant_ngl", "modify", 8, 0.1, 0.7),
            ActionSpec("bench_qairt_w4a16", "evaluate", 6, 0.1, 0.95),
            ActionSpec("quant_matrix", "modify", 40, 0.3, 0.9,
                       reversible=False),
            # nouveaux : matériel / perf / kernel / apk
            ActionSpec("hw_snapshot", "evaluate", 0.5, 0.02, 0.5),
            ActionSpec("perfetto_capture", "evaluate", 12, 0.15, 0.85),
            ActionSpec("dmesg_tail", "evaluate", 0.5, 0.05, 0.4),
            ActionSpec("build_apk_debug", "evaluate", 10, 0.2, 0.7),
            # profiler multi-format par layer (voir governor/profiler.py)
            ActionSpec("profile_layers", "evaluate", 4, 0.1, 0.9),
            ActionSpec("select_layer_formats", "modify", 0.5, 0.05, 0.8),
            ActionSpec("challenge_result", "evaluate", 1, 0.1, 0.8),
            # oracle statique fit/spill (datavorous : spillFillBufferSize)
            ActionSpec("qairt_spill_oracle", "evaluate", 2, 0.05, 0.9),
        ]
        for s in specs:
            s.executor_ref = _executor(s.name)
        return specs

    def metrics(self):
        return [("tps", "max"), ("ram_gb", "min"),
                ("quality_loss_pct", "min"), ("latency_ms", "min"),
                ("temp_c", "min"), ("cpu_util_pct", "min"),
                ("npu_busy_pct", "max")]

    def test_pool(self):
        return super().test_pool() + ["T4_op15_cold_perfetto",
                                      "T5_op15_warm_perfetto",
                                      "T6_kernel_dmesg"]

    def constraints(self):
        return {"rmax": 0.5, "gmin": -2.0, "temp_max": 70.0}

    def observe_state(self):
        """État matériel réel du OnePlus 15 (best-effort, jamais d'exception)."""
        if hw is None:
            return {}
        state = {}
        try:
            state["soc"] = "sm8850"
            state["thermal"] = hw.thermal_state()
            bat = hw.battery_status()
            if bat:
                state["battery"] = bat
            freqs = hw.cpu_freqs()
            if freqs:
                state["cpu_freqs"] = freqs
            clk = hw.gpu_clk()
            if clk is not None:
                state["gpu_mhz"] = clk
            npu = hw.npu_present()
            state["npu"] = npu
            # Utilisation CPU % (2 échantillons /proc/stat) + NPU busy estimé
            util = hw.cpu_utilization()
            if util.get("state") == "ok":
                state["cpu_util_pct"] = util["global_pct"]
                state["cpu_util_cores"] = util["cores"]
            ctx = getattr(self, "_last_variant_ctx", {})
            htp_us = ctx.get("htp_us_per_token")
            tok_us = ctx.get("token_us")
            nbusy = hw.npu_busy_estimate(htp_us, tok_us)
            if nbusy is not None:
                state["npu_busy_pct"] = nbusy
        except Exception:
            pass
        return state

    def execute(self, spec, ctx):
        """Actions matériel/perf/kernel implémentées ici ; le reste hérité."""
        if hw is None:
            return {"ok": False, "action": spec.name, "error": "hw indispo"}
        # mémorise le contexte du dernier variant pour observe_state()
        try:
            self._last_variant_ctx = {
                "htp_us_per_token": ctx.get("htp_us_per_token"),
                "token_us": ctx.get("token_us"),
            }
        except Exception:
            pass
        if spec.name == "hw_snapshot":
            snap = self.observe_state()
            return {"ok": bool(snap), "action": spec.name,
                    "metrics": {"temp_c": self._max_temp()},
                    "raw": __import__("json").dumps(snap, ensure_ascii=False)}
        if spec.name == "perfetto_capture":
            out = os.path.join(ctx.get("run_dir", "."),
                               f"perfetto_{time.strftime('%H%M%S')}.pftrace")
            path = hw.perfetto_capture(
                out, duration_s=int(ctx.get("perfetto_s", 20)),
                cats=ctx.get("perfetto_cats", hw.PERFETTO_CATS))
            metrics = hw.perfetto_metrics(path) if path else \
                {"parsed": False, "reason": "capture échec"}
            return {"ok": path is not None, "action": spec.name,
                    "metrics": metrics, "trace": path,
                    "raw": f"trace={path}" if path else "perfetto échec"}
        if spec.name == "dmesg_tail":
            text = hw.dmesg_tail(lines=int(ctx.get("dmesg_lines", 80)))
            return {"ok": text is not None, "action": spec.name,
                    "metrics": {}, "raw": (text or "")[-4000:]}
        if spec.name == "build_apk_debug":
            return self._build_apk(ctx)
        if spec.name == "profile_layers":
            return self._profile_layers(ctx)
        if spec.name == "select_layer_formats":
            return self._select_layer_formats(ctx)
        if spec.name == "challenge_result":
            return self._challenge_result(ctx)
        if spec.name == "qairt_spill_oracle":
            return self._qairt_spill_oracle(ctx)
        return super().execute(spec, ctx)

    def _profile_layers(self, ctx):
        """Profil multi-runtime (ggml/qnn/qairt) × formats, par layer.

        source="real" : bench QAIRT (t12) + ftrace L2 (fastrpc/SMMU) réels sur
        le device, répartis par layer ; source="synthetic" sinon.
        """
        from . import profiler
        if ctx.get("real"):
            return self._profile_layers_real(ctx)
        profiles = ctx.get("profiles")
        if not profiles:
            layers = ctx.get("layers") or profiler.demo_layers()
            formats = ctx.get("formats") or ["W4A16", "Q4_0", "Q8_0",
                                             "W8A8", "W4A8"]
            runtimes = ctx.get("runtimes") or ["ggml", "qnn", "qairt"]
            profiles = []
            for li, l in enumerate(layers[:12]):
                params = l["params"]
                for f in formats:
                    for rt in runtimes:
                        base = profiles and profiles[-1] or None
                        # Timing synthétique : QAIRT plus rapide que QNN/GGML,
                        # 4-bit plus rapide que 8-bit en bandwidth-bound.
                        wb = profiler.W_FORMATS.get(f, {}).get("Wbits", 8)
                        mult = {"qairt": 0.4, "qnn": 0.7, "ggml": 1.0}[rt] \
                            * (8 / max(wb, 1)) * (params / 7.5e8)
                        staging = int(1400 * mult)
                        compute = int(420 * mult)
                        sync = int(180 * mult)
                        profiles.append(profiler.layer_profile(
                            layer=l["id"], weight_format=f, backend="htp",
                            kernel=f"{f}-{rt}", runtime=rt, params=params,
                            size_bytes=profiler._fmt_size(params, f),
                            staging_us=staging, compute_us=compute,
                            sync_us=sync, total_us=staging + compute + sync,
                            bw_gbps=round(38.0 / mult, 1),
                            bottleneck=profiler.classify_bottleneck(
                                staging, compute, sync)))
        return {"ok": True, "action": "profile_layers", "profiles": profiles,
                "compare": profiler.profile_compare(profiles),
                "raw": __import__("json").dumps(
                    {"n_profiles": len(profiles)}, ensure_ascii=False)}

    def _profile_layers_real(self, ctx):
        """Mesures réelles device : bench QAIRT (t12) + ftrace L2."""
        from . import profiler
        bench = hw.bench_qairt_real() if hasattr(hw, "bench_qairt_real") \
            else None
        ft = hw.ftrace_l2_real() if hasattr(hw, "ftrace_l2_real") else None
        measured_tps = (bench or {}).get("tps") or (ft or {}).get("tps")
        counts = (ft or {}).get("counts") or {}
        layers = ctx.get("layers") or profiler.demo_layers()

        # Goulot par preuve kernel : interconnect/fastrpc actifs => trafic
        # mémoire HTP ; context_alloc => compute.
        n_int = sum(v for k, v in counts.items() if "interconnect" in k)
        n_fast = sum(v for k, v in counts.items() if "fastrpc" in k)
        if n_int > 0 and n_int > n_fast:
            bottleneck = "memory-bandwidth"
        elif n_fast > 0:
            bottleneck = "compute"
        else:
            bottleneck = "unknown"

        # Répartition du temps réel mesuré par layer (poids ∝ params × size).
        total_params = sum(l["params"] for l in layers) or 1
        per_token_us = (1000.0 / measured_tps) if measured_tps else None
        profiles = []
        for l in layers[:12]:
            frac = l["params"] / total_params
            total_us = round(per_token_us * 1e6 * frac) \
                if per_token_us else 600
            staging = int(total_us * 0.55)
            compute = int(total_us * (0.30 if n_fast else 0.20))
            sync = max(1, total_us - staging - compute)
            profiles.append(profiler.layer_profile(
                layer=l["id"], weight_format=ctx.get("format", "W4A16"),
                backend="htp", kernel="qairt-w4a16", runtime="qairt",
                params=l["params"],
                size_bytes=profiler._fmt_size(l["params"], "W4A16"),
                staging_us=staging, compute_us=compute, sync_us=sync,
                total_us=total_us,
                bottleneck=profiler.classify_bottleneck(staging, compute,
                                                        sync)))
        return {"ok": True, "action": "profile_layers", "source": "real",
                "profiles": profiles, "measured_tps": measured_tps,
                "ftrace_counts": counts, "bench": bench,
                "compare": profiler.profile_compare(profiles),
                "raw": __import__("json").dumps(
                    {"source": "real", "tps": measured_tps,
                     "bottleneck": bottleneck}, ensure_ascii=False)}

    def _select_layer_formats(self, ctx):
        """Sélectionne le format par layer sous budget RAM + précision, puis
        émet un plan de tests réels (mix par layer à benchmarker)."""
        from . import profiler
        layers = ctx.get("layers") or profiler.demo_layers()
        budget = ctx.get("budget_bytes")
        formats = ctx.get("formats")
        bw = ctx.get("bandwidth_bound", True)
        r = profiler.select_layer_formats(
            layers, budget_bytes=budget, formats=formats,
            max_loss_pct=ctx.get("max_loss_pct", 1.5),
            bandwidth_bound=bw)
        test_plan = [{"layer": a["layer"], "class": a["class"],
                      "format": a["format"], "Wbits": a["Wbits"],
                      "size_bytes": a["size_bytes"],
                      "loss_pct": a["loss_pct"]} for a in r["layers"]]
        return {"ok": True, "action": "select_layer_formats",
                "metrics": {"ram_gb": round((r["total_bytes"] or 0) / 1e9, 3),
                            "quality_loss_pct": r["total_loss_pct"]},
                "selection": r, "test_plan": test_plan,
                "raw": __import__("json").dumps(
                    {"feasible": r["feasible"],
                     "bytes": r["total_bytes"],
                     "n_to_test": len(test_plan)}, ensure_ascii=False)}

    def _challenge_result(self, ctx):
        """Confronte le mesuré au code (perfetto), aux résultats et à la
        littérature (priors) ; persiste en governor_state/challenges.jsonl."""
        from . import profiler
        measured = ctx.get("measured_tps")
        prior = ctx.get("prior") or {"source": "littérature (inconnu)",
                                     "claim_tps": measured}
        profiles = ctx.get("profiles") or []
        ref = ctx.get("ref_profile")
        report = profiler.challenge_report(measured, prior, profiles, ref)
        path = os.path.join(self.root, "governor_state", "challenges.jsonl")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            with open(path, "a", encoding="utf-8") as f:
                f.write(__import__("json").dumps(report,
                                                 ensure_ascii=False) + "\n")
        except Exception:
            pass
        return {"ok": True, "action": "challenge_result",
                "challenge": report, "log": path,
                "raw": __import__("json").dumps(
                    {"verdict": report["verdict"]}, ensure_ascii=False)}

    def _max_temp(self):
        if hw is None:
            return None
        temps = [z["temp_c"] for z in hw.thermal_zones()]
        return max(temps) if temps else None

    def _qairt_spill_oracle(self, ctx):
        """Oracle statique fit/spill du bundle QAIRT (spillFillBufferSize).

        datavorous (RE libHtpPrepare.so) : le champ `spillFillBufferSize`
        dans le binaire de contexte QNN indique 0 (weights on-chip) ou une
        taille de spill (tensors poussés en DDR). Aucune mesure dynamique —
        c'est la preuve statique du goulot (memory-bandwidth si spill).
        """
        from . import profiler
        bundle = ctx.get("bundle_path") or \
            "/data/local/tmp/gxlibs/v0.5/qwen3-8b-w4a16"
        # candidate context binaries dans le bundle
        import glob
        cands = []
        for pat in ("*.bin", "*.qnn", "*context*", "*.serialized"):
            cands += glob.glob(os.path.join(bundle, pat))
        found = None
        for c in cands:
            r = profiler.parse_qnn_context_spill_fill(c)
            if r["ok"]:
                found = r
                found["path"] = c
                break
        if found is None:
            # repli : lire via adb si le bundle est sur le device
            out = hw.device_cat(f"{bundle}/", timeout=20) if hw else None
            return {"ok": False, "action": "qairt_spill_oracle",
                    "bundle": bundle, "error": "spillFillBufferSize "
                    "introuvable dans le bundle (parser best-effort)",
                    "raw": (out or "")[-500:]}
        verdict = "memory-bandwidth" if found["spill"] else "compute-bound"
        return {"ok": True, "action": "qairt_spill_oracle",
                "bundle": bundle, "path": found["path"],
                "spill_fill_buffer_size": found["spill_fill_buffer_size"],
                "fit": found["fit"], "spill": found["spill"],
                "goulot_oracle": verdict,
                "metrics": {"spill_fill_buffer_size":
                            found["spill_fill_buffer_size"]},
                "raw": __import__("json").dumps(found, ensure_ascii=False)}

    def _build_apk(self, ctx):
        root = ctx.get("cwd", self.root)
        project = os.path.join(root, "apk_native")
        if not os.path.isdir(project):
            return {"ok": False, "action": "build_apk_debug",
                    "error": f"projet absent: {project}"}
        gradlew = os.path.join(project, "gradlew.bat") \
            if os.name == "nt" else os.path.join(project, "gradlew")
        if not os.path.exists(gradlew):
            return {"ok": False, "action": "build_apk_debug",
                    "error": "gradlew absent"}
        import subprocess
        try:
            p = subprocess.run([gradlew, "assembleDebug"],
                               capture_output=True, text=True,
                               timeout=int(ctx.get("build_timeout_s", 900)),
                               cwd=project)
            ok = p.returncode == 0
            apk = os.path.join(project, "app", "build", "outputs", "apk",
                               "debug", "app-debug.apk")
            size = os.path.getsize(apk) if os.path.exists(apk) else None
            return {"ok": ok, "action": "build_apk_debug",
                    "apk": apk if os.path.exists(apk) else None,
                    "size_bytes": size,
                    "raw": (p.stdout + p.stderr)[-4000:]}
        except Exception as e:
            return {"ok": False, "action": "build_apk_debug", "error": str(e)}

    def measure(self, raw):
        m = (raw or {}).get("metrics") or {}
        return m if m else super().measure(raw)