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
