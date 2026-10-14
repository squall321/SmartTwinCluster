# 시험 공용 픽스처 — 가짜 backend(/api/me·/api/jobs/preview), 임시 registry·audit DB, 시험 사용자 영역, 도구 실행
"""도구 스크립트는 subprocess 로 돌므로 가짜 backend 주소·DB 경로는 환경변수로 넘긴다.

호출자 영역은 backend 규칙대로 /data/single/<사용자> 고정이라 시험 사용자 stmcpytest·stmcother 의 폴더를
/data/single 아래에 만들고 지운다(쓸 수 없으면 그 픽스처를 쓰는 시험은 skip).
"""
from __future__ import annotations

import importlib
import json
import os
import shutil
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.runner import run as _run_tool

TOOLS = Path(__file__).resolve().parent.parent / "tools"
SHARED = TOOLS / "_shared"
USER, OTHER = "stmcpytest", "stmcother"
FAKE_SLURM_JOB_ID = 4242  # 가짜 backend 가 /api/jobs/submit 에 돌려주는 잡 번호
TOKENS = {"Bearer kst_user": {"username": USER, "role": "user"},
          "Bearer kst_admin": {"username": USER, "role": "admin"},
          "Bearer kst_other": {"username": OTHER, "role": "user"}}


class _FakeBackend(BaseHTTPRequestHandler):
    def _send(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        ident = TOKENS.get(self.headers.get("Authorization", ""))
        if ident and self.path == "/api/me":
            return self._send(200, ident)
        self._send(401, {"detail": "invalid token"})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if not TOKENS.get(self.headers.get("Authorization", "")):
            return self._send(401, {"detail": "invalid token"})
        if self.path == "/api/jobs/preview":
            return self._send(200, {"script": "#!/bin/bash\n#SBATCH --job-name=stmc_preview\n"})
        if self.path == "/api/jobs/submit":
            return self._send(201, {"success": True, "job_id": FAKE_SLURM_JOB_ID})
        self._send(404, {"detail": "not in fake backend"})

    def log_message(self, *a):
        pass


@pytest.fixture(scope="session")
def backend():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), _FakeBackend)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


@pytest.fixture
def registry(backend, tmp_path, monkeypatch):
    """가짜 backend + 임시 DB 를 환경에 걸고 registry 모듈을 돌려준다(행을 넣을 때 쓴다)."""
    monkeypatch.setenv("STMC_CLUSTER_URL", backend)
    monkeypatch.delenv("STMC_CLUSTER_TOKEN", raising=False)
    monkeypatch.setenv("STMC_JOBS_DB", str(tmp_path / "jobs.db"))
    monkeypatch.setenv("STMC_AUDIT_DB", str(tmp_path / "audit.db"))
    sys.path.insert(0, str(SHARED))
    try:
        return importlib.reload(importlib.import_module("registry"))
    finally:
        sys.path.remove(str(SHARED))


@pytest.fixture
def area(tmp_path):
    """(내 폴더, 남의 폴더) — 시험마다 /data/single/<시험 사용자>/ 아래에 새로 만들고 지운다."""
    if not os.access("/data/single", os.W_OK):
        pytest.skip("/data/single 에 쓸 수 없음")
    created = []
    for user in (USER, OTHER):
        p = Path("/data/single") / user
        if not p.exists():
            p.mkdir()
            created.append(p)
    mine, theirs = Path("/data/single") / USER / tmp_path.name, Path("/data/single") / OTHER / tmp_path.name
    mine.mkdir()
    theirs.mkdir()
    yield mine, theirs
    shutil.rmtree(mine, ignore_errors=True)
    shutil.rmtree(theirs, ignore_errors=True)
    for p in created:
        shutil.rmtree(p, ignore_errors=True)


@pytest.fixture
def run_as():
    """run_as(도구[@버전], args, token="kst_user"|None) → 도구가 찍은 JSON."""
    cat = load_catalog(TOOLS)

    def _run(tool: str, args: dict, token: str | None = "kst_user") -> dict:
        entry = cat.resolve(tool)
        assert entry is not None, tool
        res = _run_tool(entry, args, {"STMC_CLUSTER_TOKEN": token} if token else {})
        assert isinstance(res.parsed, dict), res.stdout + res.stderr
        return res.parsed
    return _run
