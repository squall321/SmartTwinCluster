# 카탈로그 검색이 한글 질의로도 SmartTwin 도구를 찾는지 시험 (조사가 붙은 설명 포함)
from __future__ import annotations

from pathlib import Path

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.search import search

TOOLS = Path(__file__).resolve().parent.parent / "tools"


def _names(q, k=10):
    return [h.name for h in search(load_catalog(TOOLS).all_entries(), q, limit=k)]


def test_korean_query_finds_drop_tools():
    hits = _names("낙하 자세")
    assert "kmm_drop_attitude" in hits


def test_korean_query_with_particles_in_text():
    # "재질" 은 설명에 "재질을/재질의" 처럼 조사와 붙어 나온다 — 부분 문자열로 맞아야 한다
    hits = _names("재질 교체", 15)
    assert "kmm_material_exchange" in hits or "remap_matdb" in hits or "remap_matswap" in hits


def test_ascii_search_unchanged():
    assert _names("airmesh")[0] == "kam_airmesh"
    assert "submit_job" in _names("slurm", 50)


def test_empty_query_lists_all():
    assert len(_names("", 500)) == len(load_catalog(TOOLS).latest_by_name)
