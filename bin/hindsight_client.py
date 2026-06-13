#!/usr/bin/env python3
"""
hindsight_client — minimal client for the cluster to talk to a Hindsight
memory server. Used by clusterctl to:
  1. Auto-remember every ask (user prompt + assistant response) on success
  2. Surface memory stats in the cluster health endpoint

Hindsight API (assumed compatible with hindsight-api v0.7.x):
  GET  {base}/health                          -> {"status":"healthy","version":...}
  GET  {base}/v1/default/banks/{bank}/stats  -> {"node_count":..., "edge_count":..., ...}
  POST {base}/v1/default/banks/{bank}/memory -> body: {"content": "..."}  -> 201

If the server is unreachable, all calls log a warning and return None
(graceful degradation — the cluster keeps working without memory).
"""
from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from typing import Any

HINDSIGHT_BASE = os.environ.get("HINDSIGHT_BASE", "http://127.0.0.1:8765")
HINDSIGHT_BANK = os.environ.get("HINDSIGHT_BANK", "cluster")
DEFAULT_TIMEOUT = 5

log = logging.getLogger("hindsight")


def _get(path: str, timeout: int = DEFAULT_TIMEOUT) -> Any | None:
    url = HINDSIGHT_BASE + path
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except (urllib.error.URLError, OSError, TimeoutError, json.JSONDecodeError) as e:
        log.debug("hindsight GET %s failed: %s", url, e)
        return None


def _post(path: str, body: dict, timeout: int = DEFAULT_TIMEOUT) -> Any | None:
    url = HINDSIGHT_BASE + path
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except (urllib.error.URLError, OSError, TimeoutError, json.JSONDecodeError) as e:
        log.debug("hindsight POST %s failed: %s", url, e)
        return None


def health() -> dict:
    """Returns a normalized health shape regardless of Hindsight version."""
    h = _get("/health")
    if h is None:
        return {"ok": False, "latency_ms": None, "version": None, "error": "unreachable"}
    import time
    t0 = time.time()
    # Re-ping to get latency (the _get above may have used cached or short timeout)
    ping = _get("/health", timeout=2)
    latency = round((time.time() - t0) * 1000, 1) if ping is not None else None
    return {
        "ok": True,
        "latency_ms": latency,
        "version": h.get("version") or h.get("api_version"),
        "error": None,
    }


def stats() -> dict:
    """Returns memory stats. Empty dict if Hindsight unreachable."""
    s = _get(f"/v1/default/banks/{HINDSIGHT_BANK}/stats")
    if s is None:
        return {}
    return {
        "node_count": s.get("node_count", 0),
        "edge_count": s.get("edge_count", 0),
        "document_count": s.get("document_count", 0),
        "entity_count": s.get("entity_count", 0),
    }


def remember(content: str, metadata: dict | None = None) -> str | None:
    """Store a memory. Returns the new memory ID, or None on failure."""
    body = {
        "content": content,
        "metadata": metadata or {},
    }
    r = _post(f"/v1/default/banks/{HINDSIGHT_BANK}/memory", body)
    if r is None:
        return None
    return r.get("id") or r.get("memory_id")


def recent(limit: int = 5) -> list[dict]:
    """Return the most recent N memories (best-effort)."""
    s = _get(f"/v1/default/banks/{HINDSIGHT_BANK}/memory?limit={limit}")
    if s is None or not isinstance(s, list):
        return _get(f"/v1/default/banks/{HINDSIGHT_BANK}/memories?limit={limit}") or []
    return s
