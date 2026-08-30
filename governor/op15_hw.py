"""Bloc 15 — OnePlus 15 : lecture matériel + perfetto + kernel (outils).

Exécution via adb (device branché) ou sysfs direct sur le téléphone.
Best-effort : chaque lecture échoue proprement (jamais d'exception).
Règles harnais : thermique >70 °C = hot (throttle) ; cold/warm séparés.
"""
import os
import re
import subprocess

ADB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "tools", "platform-tools", "adb.exe")

PERFETTO_CATS = ("sched freq idle am wm gfx view binder_driver hal dalvik "
                 "input res memory")


def _run(cmd, timeout=20, cwd=None):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout, cwd=cwd,
                           shell=isinstance(cmd, str))
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        return -1, str(e)


def adb_shell(cmd, su=False, timeout=25):
    if not os.path.exists(ADB):
        return None
    base = [ADB, "shell"]
    if su:
        base += ["su", "-c", cmd]
    else:
        base += [cmd]
    rc, out = _run(base, timeout=timeout)
    return out if rc == 0 else None


def thermal_zones():
    """Températures par zone (sysfs direct ou via adb). Listes de dicts."""
    zones = []
    if os.path.isdir("/sys/class/thermal"):
        try:
            for d in sorted(os.listdir("/sys/class/thermal")):
                if not d.startswith("thermal_zone"):
                    continue
                base = os.path.join("/sys/class/thermal", d)
                try:
                    with open(os.path.join(base, "temp"), encoding="utf-8") as f:
                        raw = f.read().strip()
                    with open(os.path.join(base, "type"), encoding="utf-8") as f:
                        ztype = f.read().strip()
                except Exception:
                    continue
                val = int(raw) / 1000.0 if raw.lstrip("-").isdigit() else None
                if val is not None:
                    zones.append({"zone": d, "type": ztype,
                                  "temp_c": round(val, 1)})
        except Exception:
            pass
        return zones
    # Repli : lecture via adb (device branché au PC).
    out = adb_shell("for f in /sys/class/thermal/thermal_zone*/type; do "
                    "t=$(cat $f); v=$(cat ${f/type/temp}); "
                    "echo \"$f|$t|$v\"; done", su=True, timeout=20)
    if not out:
        return zones
    for line in out.splitlines():
        try:
            path, ztype, raw = line.split("|", 2)
        except ValueError:
            continue
        val = int(raw.strip()) / 1000.0 if raw.strip().lstrip("-").isdigit() \
            else None
        if val is not None:
            zones.append({"zone": path.rsplit("/", 1)[-1], "type": ztype.strip(),
                          "temp_c": round(val, 1)})
    return zones


def thermal_state():
    """cold / warm / hot / unknown selon la règle >70°C throttle."""
    zones = thermal_zones()
    temps = [z["temp_c"] for z in zones]
    if not temps:
        return "unknown"
    m = max(temps)
    return "hot" if m > 70 else ("warm" if m > 55 else "cold")


def battery_status():
    """Batterie via adb (dumpsys) ou sysfs si dispo."""
    cap = None
    if os.path.isdir("/sys/class/power_supply"):
        for name in ("battery", "BAT0", "main"):
            p = os.path.join("/sys/class/power_supply", name, "capacity")
            if os.path.exists(p):
                try:
                    with open(p, encoding="utf-8") as f:
                        cap = float(f.read().strip())
                    break
                except Exception:
                    continue
    if cap is not None:
        return {"capacity_pct": cap}
    out = adb_shell("dumpsys battery")
    if not out:
        return {}
    m = re.search(r"level:\s*(\d+)", out)
    s = re.search(r"status:\s*(\d+)", out)
    return {"capacity_pct": float(m.group(1)) if m else None,
            "status": int(s.group(1)) if s else None}


def cpu_freqs():
    """Fréquences actuelles par coeur (sysfs direct ou via adb)."""
    freqs = []
    base = "/sys/devices/system/cpu"
    if os.path.isdir(base):
        for i in range(16):
            p = os.path.join(base, f"cpu{i}", "cpufreq", "scaling_cur_freq")
            if not os.path.exists(p):
                continue
            try:
                with open(p, encoding="utf-8") as f:
                    khz = int(f.read().strip())
                freqs.append({"cpu": i, "mhz": round(khz / 1000.0, 1)})
            except Exception:
                continue
        return freqs
    out = adb_shell("for f in /sys/devices/system/cpu/cpu*/cpufreq/"
                    "scaling_cur_freq; do echo \"$f $(cat $f)\"; done",
                    su=False, timeout=20)
    if not out:
        return freqs
    for line in out.splitlines():
        m = re.match(r".*cpu(\d+)/cpufreq/scaling_cur_freq\s+(\d+)", line)
        if m:
            freqs.append({"cpu": int(m.group(1)),
                          "mhz": round(int(m.group(2)) / 1000.0, 1)})
    return freqs


def gpu_clk():
    """Fréquence GPU Adreno via devfreq/kgsl (best-effort)."""
    paths = ["/sys/class/kgsl/kgsl-3d0/gpuclk",
             "/sys/class/devfreq/*/cur_freq"]
    for pat in paths:
        if "*" in pat:
            import glob
            cands = glob.glob(pat)
        else:
            cands = [pat]
        for p in cands:
            if os.path.exists(p):
                try:
                    with open(p, encoding="utf-8") as f:
                        return round(int(f.read().strip()) / 1e6, 1)
                except Exception:
                    continue
    return None


def _read_proc_stat():
    """Lit /proc/stat (local ou via adb). Retourne {cpu, total, idle} par ligne."""
    raw = None
    if os.path.exists("/proc/stat"):
        try:
            with open("/proc/stat", encoding="utf-8") as f:
                raw = f.read()
        except Exception:
            raw = None
    if raw is None:
        raw = adb_shell("cat /proc/stat", su=False, timeout=15)
    out = {}
    if not raw:
        return out
    for line in raw.splitlines():
        if not line.startswith("cpu"):
            continue
        parts = line.split()
        key = parts[0]
        vals = [int(v) for v in parts[1:9] if v.isdigit()]
        if len(vals) < 4:
            continue
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)  # idle + iowait
        out[key] = {"total": sum(vals), "idle": idle}
    return out


def cpu_utilization(samples=2, interval_s=0.5):
    """Utilisation CPU % par coeur + global via /proc/stat (2 échantillons).

    % = 1 - delta_idle / delta_total. Sans root, fiable, standard Linux.
    Retourne {"global_pct", "cores": [{cpu, pct}], "state": "ok"|"error"}.
    """
    a = _read_proc_stat()
    if not a or "cpu" not in a:
        return {"global_pct": None, "cores": [], "state": "error"}
    import time
    time.sleep(interval_s)
    b = _read_proc_stat()
    if not b or "cpu" not in b:
        return {"global_pct": None, "cores": [], "state": "error"}
    cores = []
    for key in sorted(a):
        if key == "cpu":
            continue
        if key not in b:
            continue
        dt = b[key]["total"] - a[key]["total"]
        di = b[key]["idle"] - a[key]["idle"]
        if dt <= 0:
            continue
        cores.append({"cpu": key, "pct": round(max(0.0, 1.0 - di / dt) * 100, 1)})
    dt = b["cpu"]["total"] - a["cpu"]["total"]
    di = b["cpu"]["idle"] - a["cpu"]["idle"]
    global_pct = round(max(0.0, 1.0 - di / dt) * 100, 1) if dt > 0 else None
    return {"global_pct": global_pct, "cores": cores, "state": "ok"}


def npu_busy_estimate(htp_us_per_token=None, token_us=None, rpc_per_token=None):
    """Estimation du taux d'occupation NPU (%) — Qualcomm n'expose PAS d'util
    NPU en sysfs, on le déduit du temps DSP par token.

    npu_busy_pct = htp_us_per_token / token_us * 100
    (ex. campagne K3-K5 : T_DSP=66 ms/token sur ~131 ms => ~50 %).

    Fallback heuristique si pas de mesure : 50% par défaut (bandwidth-bound
    decode — le NPU n'est jamais saturé en compute en decode, cf. 2607.05475).
    """
    if htp_us_per_token is not None and token_us and token_us > 0:
        return round(min(100.0, max(0.0, htp_us_per_token / token_us * 100.0)), 1)
    if htp_us_per_token is not None:
        return round(min(100.0, max(0.0, htp_us_per_token / 131.0 * 100.0)), 1)
    return None


def npu_present():
    """NPU Hexagon présent ? propriétés SoC + présence libs QNN/HTP."""
    for prop in ("ro.soc.model", "ro.soc.manufacturer", "ro.board.platform"):
        out = adb_shell(f"getprop {prop}", su=False, timeout=10)
        if out and out.strip():
            blob = out.lower()
            if any(k in blob for k in ("sm8850", "sm8", "sun", "qcom",
                                       "qualcomm")):
                return True
    out = adb_shell("ls /vendor/lib64/libQnnHtp.so "
                    "2>/dev/null || ls /vendor/dsp 2>/dev/null", su=True,
                    timeout=15)
    return bool(out and out.strip())


def perfetto_capture(out_path, duration_s=20, cats=PERFETTO_CATS,
                     extra=None):
    """Capture perfetto via adb ; retourne le chemin local ou None."""
    if not os.path.exists(ADB):
        return None
    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    dev = f"/data/misc/perfetto-traces/{os.path.basename(out_path)}"
    rc, _ = _run([ADB, "shell", "perfetto", "-o", dev, "-t", f"{duration_s}s",
                  *cats.split()], timeout=duration_s + 40)
    if rc != 0:
        return None
    rc2, _ = _run([ADB, "pull", dev, out_path], timeout=60)
    if rc2 != 0:
        return None
    _run([ADB, "shell", "rm", "-f", dev])
    return out_path if os.path.exists(out_path) else None


def dmesg_tail(lines=80, su=True):
    """Kernel logs (root requis sur Android)."""
    out = adb_shell(f"dmesg | tail -n {lines}", su=su, timeout=20)
    return out or None


def parse_perfetto_metric(text, key):
    """Extrait un chiffre (ex. tps) du rapport brut."""
    if not text:
        return None
    m = re.search(r"([0-9.]+)\s*ok/s", text)
    return float(m.group(1)) if m else None


def _tp_query(tp, trace, sql):
    try:
        p = subprocess.run([tp, trace, "-q", sql], capture_output=True,
                           text=True, timeout=90)
        return p.stdout if p.returncode == 0 else None
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Mesure réelle sur le device (outils /data/local/tmp/tools/*.sh).
# ---------------------------------------------------------------------------

def run_on_device(script, su=True, timeout=300, args=None):
    """Exécute un script posé dans /data/local/tmp/tools sur le device."""
    if not os.path.exists(ADB):
        return None
    path = f"/data/local/tmp/tools/{script}"
    cmd = f"sh {path}"
    if args:
        cmd += " " + " ".join(args)
    out = adb_shell(cmd, su=su, timeout=timeout)
    return out


def device_cat(remote_path, timeout=30):
    out = adb_shell(f"cat {remote_path}", su=True, timeout=timeout)
    return out


def parse_decode_tps(text):
    """Décode token/s depuis un log de bench (RESULT json ou texte)."""
    if not text:
        return None
    m = re.search(r'"decode"\s*:\s*"?([0-9.]+)', text) \
        or re.search(r"decode\s*=\s*([0-9.]+)", text) \
        or re.search(r"([0-9.]+)\s*tok/s", text)
    return float(m.group(1)) if m else None


def bench_qairt_real(timeout=400):
    """T12 réel : bench QAIRT w4a16, retourne tps decode + log brut."""
    out = run_on_device("bench_qairt_w4a16.sh", timeout=timeout)
    if out is None:
        return None
    log = device_cat("/data/local/tmp/t12_qairt_w4a16.log", timeout=30) or out
    return {"tps": parse_decode_tps(log), "log_tail": log[-1500:]}


def parse_ftrace_counts(text):
    """Compteurs fastrpc / SMMU / interconnect depuis le résultat l2_ftrace."""
    counts = {}
    if not text:
        return counts
    for m in re.finditer(r"(\d+)\s+(fastrpc[a-z_]*:[a-z_]+)", text):
        counts[m.group(2)] = int(m.group(1))
    for m in re.finditer(r"(\d+)\s+(interconnect[a-z_]*:[a-z_]+)", text):
        counts[m.group(2)] = int(m.group(1))
    for m in re.finditer(r"(\d+)\s+(arm_smmu[a-z_]*:[a-z_]+)", text):
        counts[m.group(2)] = int(m.group(1))
    return counts


def memory_mapping_stats(filtered_path):
    """AXE-6 — reuse IOVA + compteurs de mapping depuis le filtre L2.

    ATTENTION (leçon apprise) : 'fastrpc:compute' dans map_pages est le NOM
    du groupe IOMMU (fastrpc:compute-cb@N), pas un événement RPC. On compte
    uniquement les vrais tracepoints.
    """
    stats = {"map_pages_events": 0, "unique_iova": 0, "repeated_iova": 0,
             "iommu_pgtable_add": 0, "reuse_ratio": 0.0}
    iovas = set()
    repeated = set()
    pat_map = re.compile(r"map_pages:.*?iova=([0-9a-f]+)")
    try:
        with open(filtered_path, encoding="utf-8", errors="replace") as f:
            for ln in f:
                if "map_pages:" in ln:
                    m = pat_map.search(ln)
                    if m:
                        stats["map_pages_events"] += 1
                        iova = m.group(1)
                        if iova in iovas:
                            repeated.add(iova)
                        else:
                            iovas.add(iova)
                elif "iommu_pgtable_add:" in ln:
                    stats["iommu_pgtable_add"] += 1
    except OSError:
        return stats
    stats["unique_iova"] = len(iovas)
    stats["repeated_iova"] = len(repeated)
    n = stats["map_pages_events"]
    stats["reuse_ratio"] = round(1.0 - stats["unique_iova"] / n, 4) if n else 0.0
    return stats


def ftrace_l2_real(timeout=600):
    """Capture L2 réelle : fastrpc/SMMU/interconnect + bench du modèle."""
    out = run_on_device("l2_ftrace2.sh", timeout=timeout)
    if out is None:
        return None
    res = device_cat("/data/local/tmp/l2_ftrace_results.txt", timeout=30)
    bench = device_cat("/data/local/tmp/l2_bench.log", timeout=30)
    return {"counts": parse_ftrace_counts(res or out),
            "tps": parse_decode_tps(bench),
            "log_tail": (res or out)[-1200:]}


def perfetto_metrics(trace_path):
    """Vraie extraction via trace_processor (SQL). Best-effort."""
    import shutil
    tp = os.environ.get("PERFETTO_TP") or shutil.which("trace_processor") \
        or shutil.which("trace_processor_shell")
    if not tp or not trace_path or not os.path.exists(trace_path):
        return {"parsed": False,
                "reason": "trace_processor absent (env PERFETTO_TP ou PATH)"}
    out = {"parsed": True, "trace": trace_path}
    n = _tp_query(tp, trace_path, "select count() as n from slice;")
    if n is not None:
        m = re.search(r"\n\s*(\d+)", n)
        out["slices"] = int(m.group(1)) if m else None
    sched = _tp_query(tp, trace_path, "select count() as n from sched;")
    if sched is not None:
        m = re.search(r"\n\s*(\d+)", sched)
        out["sched_switches"] = int(m.group(1)) if m else None
    top = _tp_query(tp, trace_path,
                    "select name, count() as n from slice "
                    "group by name order by n desc limit 5;")
    if top is not None:
        rows = [ln.split("|") for ln in top.splitlines()
                if "|" in ln and not ln.startswith("name")]
        out["top_slices"] = [{"name": r[0].strip(),
                              "count": int(r[1].strip())} for r in rows
                             if len(r) >= 2 and r[1].strip().isdigit()]
    return out