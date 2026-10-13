# 후속 도구 시험 — tool_result·smarttwin_capabilities·job_reprioritize·job_harvest 의 소유권·권한·실제 동작
"""가짜 backend(/api/me)와 임시 registry·audit DB 로 도구 스크립트를 실제로 돌린다.

호출자 영역은 backend 규칙대로 /data/single/<사용자> 고정이라, 시험용 사용자 stmcpytest·stmcother 의 폴더를
/data/single 아래에 만들고 지운다(쓸 수 없으면 skip). 큐 시험은 hold 된 더미 잡을 실제로 내고 끝에 지운다
(sbatch 없으면 skip). KooChainRun 시험은 /data/SmartTwinPreprocessor/bin/KooChainRun 이 있어야 한다.
"""
from __future__ import annotations

import importlib
import json
import os
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.runner import run as run_tool

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
SHARED = TOOLS / "_shared"
SPECS = json.loads((SHARED / "stmc_specs.json").read_text(encoding="utf-8"))
PYKOOCAE = Path(os.environ.get("PYKOOCAE_ROOT", "/home/koopark/serviceApptainers/appt313/opt/pyKooCAE"))
KCR = Path("/data/SmartTwinPreprocessor/bin/KooChainRun")
USER, OTHER = "stmcpytest", "stmcother"
TOKENS = {"Bearer kst_user": {"username": USER, "role": "user"},
          "Bearer kst_admin": {"username": USER, "role": "admin"},
          "Bearer kst_other": {"username": OTHER, "role": "user"}}

needs_area = pytest.mark.skipif(not os.access("/data/single", os.W_OK), reason="/data/single 에 쓸 수 없음")
needs_slurm = pytest.mark.skipif(shutil.which("sbatch") is None, reason="Slurm 없음")
needs_kcr = pytest.mark.skipif(not KCR.is_file(), reason="KooChainRun 없음")


class _Me(BaseHTTPRequestHandler):
    def do_GET(self):
        ident = TOKENS.get(self.headers.get("Authorization", ""))
        ok = ident is not None and self.path == "/api/me"
        body = json.dumps(ident if ok else {"detail": "invalid token"}).encode()
        self.send_response(200 if ok else 401)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


@pytest.fixture(scope="module")
def backend():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), _Me)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


@pytest.fixture
def registry(backend, tmp_path, monkeypatch):
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
    """(내 폴더, 남의 폴더) — 시험마다 새로 만들고 지운다."""
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


def _run(tool, args, token="kst_user"):
    entry = load_catalog(TOOLS).resolve(tool)
    assert entry is not None, tool
    env = {"STMC_CLUSTER_TOKEN": token} if token else {}
    res = run_tool(entry, args, env)
    assert isinstance(res.parsed, dict), res.stdout + res.stderr
    return res.parsed


def _tool_job(reg, d: Path, *, job_id="900001", done=True):
    """smarttwin-tool 잡 하나를 registry 에 넣고(폴더는 done 일 때만) registry_id 를 돌려준다."""
    if done:
        (d / "work").mkdir(parents=True)
        (d / "work" / "summary.txt").write_text("Nodes: 8\n")
        (d / "stmc_result.json").write_text(json.dumps({
            "state": "done", "rc": 0, "duration_s": 3,
            "outputs": [{"path": str(d / "work" / "summary.txt"), "size": 9}]}))
        (d / "stmc_stdout.log").write_text("hello from the tool\n")
    return reg.record_submission(tool_name="remap_info", work_dir=str(d), output_dir=str(d / "work"),
                                 slurm_job_ids=[job_id], extra={"kind": "smarttwin-tool", "web_user": USER})


def _campaign(d: Path, jobs: dict[str, str]) -> Path:
    """runner_config.json·jobs.json 만 있는 최소 KooChainRun 캠페인 폴더."""
    (d / "output" / "slurm_scripts").mkdir(parents=True, exist_ok=True)
    angles = {str(i): {"1": {"roll": 30.0 * i, "pitch": 10.0 * i, "yaw": 0.0}} for i in range(1, 4)}
    (d / "runner_config.json").write_text(json.dumps({
        "project": {"name": "pytest", "output_dir": str(d / "output")},
        "scenario": {"doe_count": 3, "doe_angles": angles}}))
    (d / "jobs.json").write_text(json.dumps({"jobs": {
        doe: {"job_id": jid, "job_name": f"pytest_DOE{int(doe):03d}"} for doe, jid in jobs.items()}}))
    return d


def _held_job(script: Path) -> str:
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text("#!/bin/bash\n#SBATCH -n 1\n#SBATCH -t 00:01:00\nexit 0\n")
    r = subprocess.run(["sbatch", "--parsable", "--hold", "-J", "stmc_pytest", str(script)],
                       capture_output=True, text=True, check=True)
    return r.stdout.strip().split(";")[0]


# ── smarttwin_capabilities ───────────────────────────────────────────────────────

def test_capabilities_covers_every_family_and_points_at_real_tools():
    out = _run("smarttwin_capabilities", {}, token=None)
    assert out["ok"] and out["total"] == len(SPECS["index"])
    assert set(out["families"]) == {"KooMeshModifier", "KooAutomatedModeller", "KooRemapper", "KooChainRun",
                                    "SmartTwinPostprocessor"}
    names = set(load_catalog(TOOLS).latest_by_name)
    missing = {r["tool"] for rows in out["families"].values() for r in rows} - names
    assert not missing, missing


def test_capabilities_filters():
    post = _run("smarttwin_capabilities", {"family": "SmartTwinPostprocessor"}, token=None)
    assert list(post["families"]) == ["SmartTwinPostprocessor"] and post["total"] == 10
    drop = _run("smarttwin_capabilities", {"query": "낙하"}, token=None)
    tools = {r["tool"] for rows in drop["families"].values() for r in rows}
    assert {"kmm_drop_attitude", "scenario_drop", "fullangle_drop_simulation"} <= tools


@pytest.mark.skipif(not (PYKOOCAE / "Runner" / "cli_help_kcr.py").is_file(), reason="pyKooCAE 소스 없음")
def test_every_koochainrun_command_has_a_tool():
    sys.path.insert(0, str(PYKOOCAE))
    try:
        cat = importlib.import_module("Runner.cli_help_kcr").CATALOG
    finally:
        sys.path.pop(0)
    commands = {m.name for m in cat.modes if m.category == "명령"} - {"run"}
    indexed = {r["capability"]: r["tool"] for r in SPECS["index"] if r["category"] == "명령"}
    assert commands == set(indexed), commands ^ set(indexed)
    names = set(load_catalog(TOOLS).latest_by_name)
    assert set(indexed.values()) <= names


# ── tool_result ──────────────────────────────────────────────────────────────────

@needs_area
def test_tool_result_reads_a_finished_job_by_registry_or_job_id(registry, area):
    mine, _ = area
    rid = _tool_job(registry, mine / "remap_info_900001")
    for args in ({"registry_id": rid}, {"job_id": "900001"}, {"job_id": 900001}):
        out = _run("tool_result", args)
        assert out["ok"], out
        res = out["result"]
        assert res["state"] == "done" and res["rc"] == 0
        assert "hello from the tool" in res["stdout_tail"]
        assert list(res["inline_outputs"].values()) == ["Nodes: 8\n"]


@needs_area
def test_tool_result_pending_job_has_no_folder_yet(registry, area):
    mine, _ = area
    rid = _tool_job(registry, mine / "queued_900002", job_id="900002", done=False)
    out = _run("tool_result", {"registry_id": rid})
    assert out["ok"] and out["result"]["state"] == "pending"


@needs_area
def test_tool_result_refuses_another_users_job(registry, area):
    _, theirs = area
    rid = _tool_job(registry, theirs / "remap_info_900003", job_id="900003")
    out = _run("tool_result", {"registry_id": rid})
    assert out["ok"] is False and "허용 범위 밖" in out["reason"]
    assert _run("tool_result", {"registry_id": rid}, token="kst_other")["ok"] is True
    out = _run("tool_result", {"work_dir": str(theirs / "remap_info_900003")})
    assert out["ok"] is False and "허용 범위 밖" in out["reason"]


def test_tool_result_without_pat_is_refused(registry):
    out = _run("tool_result", {"registry_id": 1}, token=None)
    assert out["ok"] is False


# ── job_reprioritize ─────────────────────────────────────────────────────────────

@needs_area
@needs_kcr
def test_reprioritize_plans_for_owner_and_apply_is_admin_only(registry, area):
    mine, _ = area
    camp = _campaign(mine / "camp", {"1": "900011", "2": "900012"})
    plan = _run("job_reprioritize", {"work_dir": str(camp)})
    assert plan["ok"] and plan["applied"] is False and "적응 우선순위 재배치" in plan["stdout"], plan
    denied = _run("job_reprioritize", {"work_dir": str(camp), "apply": True})
    assert denied["ok"] is False and "admin" in denied["reason"]
    both = _run("job_reprioritize", {"work_dir": str(camp), "apply": True, "release_held": True}, token="kst_admin")
    assert both["ok"] is False and "함께" in both["reason"]
    applied = _run("job_reprioritize", {"work_dir": str(camp), "apply": True}, token="kst_admin")
    assert applied["ok"] and applied["applied"] is True and applied["held_jobs"] == [], applied


@needs_area
@needs_slurm
@needs_kcr
def test_reprioritize_never_touches_jobs_from_outside_the_campaign(registry, area):
    mine, _ = area
    camp = mine / "camp"
    own = _held_job(camp / "output" / "slurm_scripts" / "run_doe_001.sh")
    foreign = _held_job(mine / "elsewhere" / "s.sh")
    try:
        _campaign(camp, {"1": own, "2": foreign})
        out = _run("job_reprioritize", {"work_dir": str(camp), "release_held": True})
        assert out["ok"] is False and foreign in out["reason"] and "제출된 잡이 아니다" in out["reason"], out
        out = _run("job_reprioritize", {"work_dir": str(camp), "apply": True}, token="kst_admin")
        assert out["ok"] is False and foreign in out["reason"], out
        state = subprocess.run(["squeue", "-h", "-o", "%r", "-j", foreign], capture_output=True, text=True).stdout
        assert "JobHeld" in state  # 남의 잡은 그대로

        _campaign(camp, {"1": own})
        out = _run("job_reprioritize", {"work_dir": str(camp), "release_held": True})
        assert out["ok"] and [d["job_id"] for d in out["released"]] == [own], out
    finally:
        subprocess.run(["scancel", own, foreign], capture_output=True)


@needs_area
def test_reprioritize_refuses_another_users_campaign(registry, area):
    _, theirs = area
    camp = _campaign(theirs / "camp", {"1": "900021"})
    out = _run("job_reprioritize", {"work_dir": str(camp)})
    assert out["ok"] is False and "허용 범위 밖" in out["reason"]


# ── job_harvest ──────────────────────────────────────────────────────────────────

def _sphere_report(d: Path):
    stresses = [100, 110, 105, 300, 95, 102]
    (d / "output").mkdir(parents=True, exist_ok=True)
    (d / "output" / "sphere_report.json").write_text(json.dumps({"results_summary": [
        {"run_id": f"R{i:04d}", "angle": {"roll": 15.0 * i, "pitch": 5.0 * i, "yaw": 0.0},
         "parts": {"1": {"name": "Frame", "peak_stress": s}}} for i, s in enumerate(stresses, 1)]}))


@needs_area
@needs_kcr
def test_harvest_writes_risk_angles_for_the_owner(registry, area):
    mine, _ = area
    camp = _campaign(mine / "camp", {"1": "900031"})
    _sphere_report(camp)
    out = _run("job_harvest", {"work_dir": str(camp), "top": 3})
    assert out["ok"], out
    assert out["risk_files"] == [str(camp / "risk_angles.json")]
    doc = json.loads((camp / "risk_angles.json").read_text())
    assert len(doc["angles"]) == 3 and doc["angles"][0]["roll"] == 60.0  # 300 MPa 인 R0004 가 맨 위


@needs_area
@needs_kcr
def test_harvest_without_results_fails_cleanly_and_checks_owner(registry, area):
    mine, theirs = area
    camp = _campaign(mine / "camp", {"1": "900041"})
    out = _run("job_harvest", {"work_dir": str(camp)})
    assert out["ok"] is False and out["risk_files"] == []
    _sphere_report(theirs)
    out = _run("job_harvest", {"work_dir": str(theirs)})
    assert out["ok"] is False and "허용 범위 밖" in out["reason"]
    out = _run("job_harvest", {"work_dir": str(camp), "from_scenario": str(theirs / "scenario.json")})
    assert out["ok"] is False and "허용 범위 밖" in out["reason"]
