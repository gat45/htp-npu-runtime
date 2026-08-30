"""Pont harness → governor : un seul point d'entrée pour la plume."""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _governor():
    import sys
    if ROOT not in sys.path:
        sys.path.insert(0, ROOT)
    from governor.engine import Governor
    cfg_path = os.path.join(ROOT, "config.json")
    try:
        with open(cfg_path, encoding="utf-8") as f:
            gcfg = (json.load(f) or {}).get("governor")
    except Exception:
        gcfg = None
    return Governor(root=ROOT, config=gcfg)


def run_op(op, caps=None, seed_baseline=None, dry_run=True):
    g = _governor()
    if op == "plan":
        return g.decide()
    if op == "step":
        out = g.step(dry_run=dry_run)
        stop = g.should_stop()
        out["stop_check"] = stop
        return {k: v for k, v in out.items() if k != "decision"} | {
            "next_action": (out.get("decision", {}).get("ranked") or [None])[0]}
    if op == "gate":
        if seed_baseline:
            g._save_variants({**g._load_variants(),
                              "baseline": {"caps": seed_baseline,
                                           "parent": None}})
        return g.attribute_and_gate(caps or {})
    if op == "report":
        return g.report()
    if op == "recall":
        # Unified RAG: search conversation memory + 64K+ docs knowledge base
        query = caps.get("query") if isinstance(caps, dict) else str(caps or "")
        mode = caps.get("mode", "hybrid") if isinstance(caps, dict) else "hybrid"
        results = []
        # Conversation memory
        conv = g.memory.query(query)
        results.extend({"source": "conversation", "key": e["key"],
                        "value": e["value"], "confidence": e["confidence"]}
                       for e in conv)
        # Unified RAG
        try:
            from governor.unified_rag import get_rag
            rag = get_rag()
            rag_results = rag.search(query, mode=mode, top_k=5)
            results.extend({"source": r.get("source_type", "rag"),
                            "title": r.get("title", ""), "content": r.get("content", "")[:300],
                            "score": r.get("hybrid_score") or r.get("score", 0)}
                           for r in rag_results)
        except Exception as e:
            results.append({"source": "rag_error", "error": str(e)})
        return {"results": results, "query": query, "mode": mode}
    if op in ("profile_layers", "select_layer_formats", "challenge_result"):
        return _run_adapter_op(g, op, caps, dry_run)
    if op == "research":
        from .web_research import research
        q = caps.get("query") if isinstance(caps, dict) else str(caps or "")
        return research(q or "", sources=caps.get("sources")
                        if isinstance(caps, dict) else None,
                        subreddit=caps.get("subreddit")
                        if isinstance(caps, dict) else None)
    return {"error": f"op inconnue: {op}",
            "ops": ["plan", "step", "gate", "report", "recall", "research",
                    "profile_layers", "select_layer_formats",
                    "challenge_result"]}


def _run_adapter_op(g, op, caps, dry_run):
    """Expose une action de l'adapter (ex. profiler) comme op du bridge."""
    spec = next((s for s in g.adapter.action_space() if s.name == op), None)
    if spec is None:
        return {"error": f"action {op} indisponible (adapter={g.adapter.id})"}
    ctx = dict(caps or {}) if isinstance(caps, dict) else {}
    ctx.setdefault("run_dir", os.path.join(ROOT, "bench_results",
                                           "gov_plume"))
    ctx.setdefault("cwd", ROOT)
    if dry_run:
        return {"dry_run": True, "action": op, "adapter": g.adapter.id}
    return g.adapter.execute(spec, ctx)
