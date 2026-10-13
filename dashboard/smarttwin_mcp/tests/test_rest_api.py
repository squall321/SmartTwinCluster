# REST(/api/v1) 시험 — 인증 게이트·응답 코드·OpenAPI 전 도구·MCP catalog_run 과 같은 결과(패리티)
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
from fastmcp import Client
from starlette.testclient import TestClient

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.server import build_server

TOOLS = Path(__file__).resolve().parent.parent / "tools"
GOOD = {"Authorization": "Bearer kst_good"}


def _fake_verifier(header: str):
    return (200, {"username": "u", "role": "user"}) if header == "Bearer kst_good" else (401, None)


@pytest.fixture(scope="module")
def mcp():
    return build_server(TOOLS, rest_verifier=_fake_verifier)


@pytest.fixture(scope="module")
def client(mcp):
    with TestClient(mcp.http_app()) as c:
        yield c


def test_health_needs_no_auth(client):
    r = client.get("/api/v1/health")
    assert r.status_code == 200 and r.json()["ok"] is True and r.json()["tools"] > 100


@pytest.mark.parametrize("method,path", [("get", "/api/v1/tools"), ("get", "/api/v1/tools/echo"),
                                         ("get", "/api/v1/tools/echo/versions"), ("post", "/api/v1/tools/echo/run"),
                                         ("post", "/api/v1/reload")])
def test_everything_but_health_and_openapi_needs_a_valid_pat(client, method, path):
    assert getattr(client, method)(path).status_code == 401
    assert getattr(client, method)(path, headers={"Authorization": "Bearer kst_bad"}).status_code == 401


def test_search_describe_versions(client):
    r = client.get("/api/v1/tools", params={"q": "낙하", "limit": 5}, headers=GOOD)
    assert r.status_code == 200 and r.json()["hits"]
    r = client.get("/api/v1/tools/kmm_transform", headers=GOOD)
    assert r.status_code == 200 and r.json()["args_schema"]["required"] == ["model_path"]
    assert client.get("/api/v1/tools/nope_tool", headers=GOOD).status_code == 404
    r = client.get("/api/v1/tools/fullangle_drop_simulation/versions", headers=GOOD)
    assert r.status_code == 200 and "1.1.1" in r.json()["versions"]


def test_run_status_codes(client):
    ok = client.post("/api/v1/tools/echo/run", json={"args": {"message": "hi", "count": 2}}, headers=GOOD)
    assert ok.status_code == 200 and ok.json()["ok"] is True and ok.json()["result"]["echoed"] == ["hi", "hi"]
    bad = client.post("/api/v1/tools/echo/run", json={"args": {"nope": 1}}, headers=GOOD)
    assert bad.status_code == 400 and "validation" in bad.json()["error"]
    missing = client.post("/api/v1/tools/nope_tool/run", json={"args": {}}, headers=GOOD)
    assert missing.status_code == 404
    notjson = client.post("/api/v1/tools/echo/run", content=b"x", headers=GOOD)
    assert notjson.status_code == 400


def test_run_generated_tool_dry_run(client):
    r = client.post("/api/v1/tools/kmm_transform/run", headers=GOOD,
                    json={"args": {"model_path": "/data/single/u/m.k", "dry_run": True,
                                   "options": {"Translation": [0, 0, 1]}}})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True and "Translation,0,0,1" in body["result"]["texts"]["stmc_options.txt"]


def test_openapi_lists_every_tool_with_its_schema(client):
    spec = client.get("/api/v1/openapi.json").json()
    assert spec["openapi"] == "3.1.0"
    cat = load_catalog(TOOLS)
    for name, entry in cat.latest_by_name.items():
        op = spec["paths"][f"/v1/tools/{name}/run"]["post"]
        args = op["requestBody"]["content"]["application/json"]["schema"]["properties"]["args"]
        assert args.get("properties") == entry.args_schema.get("properties"), name


def test_rest_and_mcp_return_the_same_result(client, mcp):
    args = {"message": "parity", "count": 3}
    rest = client.post("/api/v1/tools/echo/run", json={"args": args}, headers=GOOD).json()

    async def via_mcp():
        async with Client(mcp) as c:
            res = await c.call_tool("catalog_run", {"name": "echo", "args": args})
            return res.data if hasattr(res, "data") and res.data is not None else res.structured_content
    m = asyncio.run(via_mcp())
    assert {k: rest[k] for k in ("tool", "ok", "exit_code", "result")} == {k: m[k] for k in ("tool", "ok", "exit_code", "result")}
