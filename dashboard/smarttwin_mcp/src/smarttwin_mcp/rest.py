# MCP 카탈로그를 같은 서버(:5013)에서 REST(/api/v1/*)로도 노출 — 검증·실행 함수는 MCP 와 공유
"""SmartTwinMCP REST API.

MCP 메타툴과 같은 함수(검색·설명·버전·실행)를 HTTP 로 연다. 실행은 `execute`(server.py 가 만든 MCP
catalog_run 과 같은 함수)를 그대로 부르므로 MCP 와 REST 의 동작이 어긋날 수 없다.

경로 (nginx 는 /smarttwin-api/ → 127.0.0.1:5013/api/ 로 넘긴다)
  GET  /api/v1/health                      인증 없음 — 살아 있는지·도구 수
  GET  /api/v1/openapi.json                인증 없음 — 카탈로그에서 생성한 OpenAPI 3.1
  GET  /api/v1/tools?q=&limit=             catalog_search
  GET  /api/v1/tools/{name}                catalog_describe (name@version 가능)
  GET  /api/v1/tools/{name}/versions       catalog_versions
  POST /api/v1/tools/{name}/run            catalog_run — 본문 {"args": {...}, "version": "1.0.0"?}
  POST /api/v1/reload                      catalog_reload

인증: `Authorization: Bearer kst_…`(대시보드 발급 PAT). backend `/api/me` 로 검증하고 60초 캐시한다.
같은 헤더가 도구 실행 env 로 넘어가 backend 가 호출자 권한·감사를 적용한다(MCP 와 같다).
응답 코드: 200 실행됨(본문 ok 로 성패) · 400 인자 오류 · 401 PAT 없음/무효 · 404 도구 없음 · 503 인증 서버 불가.
"""
from __future__ import annotations

import hashlib
import json
import os
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Callable

from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import JSONResponse

PREFIX = "/api/v1"
_CACHE_TTL = 60.0


class PatVerifier:
    """PAT → /api/me 신원. 성공만 60초 캐시(실패는 캐시하지 않는다)."""

    def __init__(self, base_url: str | None = None):
        self.base_url = (base_url or os.environ.get("STMC_CLUSTER_URL") or "").rstrip("/")
        self._cache: dict[str, tuple[float, dict]] = {}
        self._lock = threading.Lock()

    def __call__(self, auth_header: str) -> tuple[int, dict | None]:
        if not auth_header or not auth_header[:7].lower() == "bearer " or not auth_header[7:].strip():
            return 401, None
        if not self.base_url:
            return 503, None
        key = hashlib.sha256(auth_header.encode()).hexdigest()
        now = time.time()
        with self._lock:
            hit = self._cache.get(key)
            if hit and hit[0] > now:
                return 200, hit[1]
        req = urllib.request.Request(self.base_url + "/api/me",
                                     headers={"Authorization": auth_header, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                ident = json.loads(r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            return (401 if e.code in (401, 403) else 503), None
        except Exception:  # noqa: BLE001
            return 503, None
        if not isinstance(ident, dict) or not ident.get("username"):
            return 401, None
        with self._lock:
            self._cache[key] = (now + _CACHE_TTL, ident)
        return 200, ident


def _err(status: int, msg: str, **extra) -> JSONResponse:
    return JSONResponse({"ok": False, "error": msg, **extra}, status_code=status)


def _schema_for_openapi(schema: dict) -> dict:
    return {k: v for k, v in schema.items() if k not in ("$schema", "title")}


def build_openapi(catalog) -> dict:
    run_result = {"type": "object", "properties": {
        "tool": {"type": "string"}, "ok": {"type": "boolean"}, "exit_code": {"type": ["integer", "null"]},
        "result": {}, "stdout": {"type": "string"}, "stderr": {"type": "string"},
        "transport": {"type": "string"}, "command": {"type": "string"}}}
    common = {"400": {"description": "인자 검증 실패"}, "401": {"description": "PAT 없음/무효"},
              "404": {"description": "도구 없음"}, "503": {"description": "인증 서버(backend) 불가"}}
    paths: dict[str, Any] = {
        "/v1/health": {"get": {"operationId": "health", "summary": "살아 있는지·도구 수", "security": [],
                               "responses": {"200": {"description": "ok"}}}},
        "/v1/tools": {"get": {"operationId": "catalog_search", "summary": "도구 검색(빈 q = 전체)",
                              "parameters": [{"name": "q", "in": "query", "schema": {"type": "string"}},
                                             {"name": "limit", "in": "query", "schema": {"type": "integer"}}],
                              "responses": {"200": {"description": "검색 결과"}, **common}}},
        "/v1/tools/{name}": {"get": {"operationId": "catalog_describe", "summary": "도구 설명·인자 스키마·예제",
                                     "parameters": [{"name": "name", "in": "path", "required": True,
                                                     "schema": {"type": "string"}}],
                                     "responses": {"200": {"description": "설명"}, **common}}},
        "/v1/tools/{name}/versions": {"get": {"operationId": "catalog_versions", "summary": "버전 목록",
                                              "parameters": [{"name": "name", "in": "path", "required": True,
                                                              "schema": {"type": "string"}}],
                                              "responses": {"200": {"description": "버전"}, **common}}},
        "/v1/reload": {"post": {"operationId": "catalog_reload", "summary": "tools/ 재검색",
                                "responses": {"200": {"description": "개수·문제"}, **common}}},
    }
    for name, entry in sorted(catalog.latest_by_name.items()):
        paths[f"/v1/tools/{name}/run"] = {"post": {
            "operationId": f"run_{name}", "summary": entry.meta.summary,
            "description": (entry.meta.description or "")[:6000],
            "tags": [t for t in entry.meta.tags[:1]],
            "requestBody": {"required": True, "content": {"application/json": {"schema": {
                "type": "object", "required": ["args"], "additionalProperties": False,
                "properties": {"args": _schema_for_openapi(entry.args_schema),
                               "version": {"type": "string", "description": "버전 고정(생략 = latest)"}}}}}},
            "responses": {"200": {"description": "실행됨 — 성패는 본문 ok",
                                  "content": {"application/json": {"schema": run_result}}}, **common}}}
    return {"openapi": "3.1.0",
            "info": {"title": "SmartTwinMCP REST", "version": "1",
                     "description": "MCP(/mcp) 와 같은 카탈로그·같은 실행 경로. 인증 = 대시보드 PAT(Bearer kst_…)."},
            "servers": [{"url": os.environ.get("STMC_REST_PUBLIC_BASE", "/smarttwin-api"), "description": "nginx"},
                        {"url": "/api", "description": "127.0.0.1:5013 직결(터널)"}],
            "components": {"securitySchemes": {"bearer": {"type": "http", "scheme": "bearer"}}},
            "security": [{"bearer": []}],
            "paths": paths}


def register(mcp, *, get_catalog: Callable, search: Callable, describe: Callable, versions: Callable,
             execute: Callable, reload: Callable, verifier: Callable | None = None) -> None:
    """MCP 서버에 REST 경로를 단다. execute(name, args, version, extra_env) 는 MCP catalog_run 과 같은 함수."""
    verify = verifier or PatVerifier()

    async def _auth(request: Request):
        status, ident = await run_in_threadpool(verify, request.headers.get("authorization", ""))
        if status != 200:
            msg = {401: "PAT(Authorization: Bearer kst_…)가 없거나 무효다", 503: "인증 서버(backend /api/me)에 닿지 못했다"}
            return None, _err(status, msg.get(status, "인증 실패"))
        return ident, None

    @mcp.custom_route(f"{PREFIX}/health", methods=["GET"])
    async def _health(request: Request):
        return JSONResponse({"ok": True, "server": "SmartTwinMCP", "tools": len(get_catalog().latest_by_name)})

    @mcp.custom_route(f"{PREFIX}/openapi.json", methods=["GET"])
    async def _openapi(request: Request):
        return JSONResponse(build_openapi(get_catalog()))

    @mcp.custom_route(f"{PREFIX}/tools", methods=["GET"])
    async def _search(request: Request):
        _, deny = await _auth(request)
        if deny:
            return deny
        try:
            limit = int(request.query_params.get("limit", "20"))
        except ValueError:
            return _err(400, "limit 은 정수")
        return JSONResponse(search(request.query_params.get("q", ""), limit))

    @mcp.custom_route(PREFIX + "/tools/{name}", methods=["GET"])
    async def _describe(request: Request):
        _, deny = await _auth(request)
        if deny:
            return deny
        out = describe(request.path_params["name"])
        return JSONResponse(out, status_code=404 if "error" in out else 200)

    @mcp.custom_route(PREFIX + "/tools/{name}/versions", methods=["GET"])
    async def _versions(request: Request):
        _, deny = await _auth(request)
        if deny:
            return deny
        out = versions(request.path_params["name"])
        return JSONResponse(out, status_code=404 if "error" in out else 200)

    @mcp.custom_route(PREFIX + "/tools/{name}/run", methods=["POST"])
    async def _run(request: Request):
        _, deny = await _auth(request)
        if deny:
            return deny
        try:
            body = await request.json()
        except Exception:  # noqa: BLE001
            return _err(400, "본문은 JSON 객체여야 한다 — {\"args\": {...}}")
        if not isinstance(body, dict) or not isinstance(body.get("args", {}), dict):
            return _err(400, "본문은 {\"args\": {...}, \"version\": 선택} 형태")
        auth = request.headers.get("authorization", "")
        extra_env = {"STMC_CLUSTER_TOKEN": auth[7:].strip(), "STMC_AUTH": auth}
        out = await run_in_threadpool(execute, request.path_params["name"], body.get("args") or {},
                                      body.get("version"), extra_env)
        if out.get("ok") is False and "error" in out and "exit_code" not in out:
            code = 404 if str(out["error"]).startswith("tool not found") else 400
            return JSONResponse(out, status_code=code)
        return JSONResponse(out)

    @mcp.custom_route(f"{PREFIX}/reload", methods=["POST"])
    async def _reload(request: Request):
        _, deny = await _auth(request)
        if deny:
            return deny
        return JSONResponse(await run_in_threadpool(reload))
