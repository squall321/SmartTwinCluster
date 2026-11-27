# SM-02 시험 — tools/list 의 annotations.readOnlyHint 가 catalog_* 는 고정값, 직접 도구는 meta.yaml read_only 를 따른다
"""게이트웨이 읽기 목록을 박스 덧씌우기 없이 채우려는 표지. mode-* 태그는 시야 구분이라 쓰지 않는다."""
from __future__ import annotations

import asyncio
from pathlib import Path

from fastmcp import Client

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.server import build_server

TOOLS = Path(__file__).resolve().parent.parent / "tools"
READ = {"catalog_search", "catalog_describe", "catalog_versions", "echo", "get_job_details", "job_status",
        "list_recent_jobs", "recipe_list", "smarttwin_capabilities", "tool_result", "job_changes"}


def _listed() -> dict:
    async def go():
        async with Client(build_server(TOOLS)) as c:
            return {t.name: t.annotations for t in await c.list_tools()}
    return asyncio.run(go())


def test_every_listed_tool_carries_read_only_hint_and_reads_are_marked():
    listed = _listed()
    assert all(a is not None and a.readOnlyHint is not None for a in listed.values()), listed
    assert {n for n, a in listed.items() if a.readOnlyHint} == READ, listed
    assert listed["catalog_run"].readOnlyHint is False and listed["catalog_reload"].readOnlyHint is False


def test_direct_tools_follow_meta_read_only():
    listed = _listed()
    for e in load_catalog(TOOLS).all_entries():
        if e.is_latest and e.meta.expose in ("direct", "both"):
            assert listed[e.name].readOnlyHint is e.meta.read_only, e.name


def test_c6_four_hints_in_camel_case_on_every_listed_tool():
    import json
    from starlette.testclient import TestClient
    hdr = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
    with TestClient(build_server(TOOLS).http_app(stateless_http=True)) as c:
        r = c.post("/mcp", headers=hdr, json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    body = r.text if r.text.lstrip().startswith("{") else r.text.split("data:", 1)[1]
    tools = json.loads(body)["result"]["tools"]
    keys = {"readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint"}
    for t in tools:
        assert keys <= set(t.get("annotations") or {}), t["name"]
        assert not any("_hint" in k for k in t["annotations"]), t["name"]  # snake_case 가 새면 클라이언트가 못 읽는다
    by = {t["name"]: t["annotations"] for t in tools}
    assert by["job_stop"]["destructiveHint"] is True and by["catalog_run"]["destructiveHint"] is True
    assert by["job_status"]["idempotentHint"] is True and by["submit_job"]["idempotentHint"] is False
    assert all(a["openWorldHint"] is False for a in by.values())
