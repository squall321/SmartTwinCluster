# E1 시험 — 직접 도구 inputSchema 는 카탈로그 args.schema 그대로, 옛 {"args": {...}} 꼴도 받음, stateless HTTP 로 세션 없이 응답
"""포털 mcp-modernize 1단계. 직접 도구는 예전에 inputSchema 를 `args: object` 하나로 버렸다."""
from __future__ import annotations

import asyncio
import json
from pathlib import Path

from fastmcp import Client
from starlette.testclient import TestClient

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.server import build_server

TOOLS = Path(__file__).resolve().parent.parent / "tools"


def _with_client(fn):
    async def go():
        async with Client(build_server(TOOLS)) as c:
            return await fn(c)
    return asyncio.run(go())


def test_direct_tools_publish_the_catalog_schema():
    listed = _with_client(lambda c: c.list_tools())
    by_name = {t.name: t for t in listed}
    direct = [e for e in load_catalog(TOOLS).all_entries() if e.is_latest and e.meta.expose in ("direct", "both")]
    assert direct
    for e in direct:
        want = {k: v for k, v in e.args_schema.items() if k != "$schema"}
        assert by_name[e.name].inputSchema == want, e.name


def test_direct_tool_accepts_flat_and_legacy_wrapped_args():
    async def calls(c):
        flat = await c.call_tool("echo", {"message": "hi", "count": 2})
        legacy = await c.call_tool("echo", {"args": {"message": "hi", "count": 2}})
        return flat, legacy
    flat, legacy = _with_client(calls)
    for r in (flat, legacy):
        out = json.loads(r.content[0].text)
        assert out["ok"] is True and out["tool"] == "echo@1.0.0", out
        assert r.structured_content == out


def test_direct_tool_validation_error_is_reported():
    r = _with_client(lambda c: c.call_tool("echo", {"message": "hi", "count": 0}, raise_on_error=False))
    out = json.loads(r.content[0].text)
    assert out["ok"] is False and "count" in out["error"], out


def test_stateless_http_answers_without_a_session():
    app = build_server(TOOLS).http_app(stateless_http=True)
    hdr = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
    with TestClient(app) as c:
        for i in (1, 2):  # initialize 없이, 세션 머리 없이 따로따로
            r = c.post("/mcp", headers=hdr, json={"jsonrpc": "2.0", "id": i, "method": "tools/list"})
            assert r.status_code == 200, r.text
            assert "mcp-session-id" not in {k.lower() for k in r.headers}
            body = r.text if r.text.lstrip().startswith("{") else r.text.split("data:", 1)[1]
            names = {t["name"] for t in json.loads(body)["result"]["tools"]}
            assert {"catalog_search", "job_status", "echo"} <= names
