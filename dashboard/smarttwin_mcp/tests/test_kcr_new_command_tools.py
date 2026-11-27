# KooChainRun 새 명령 도구 9개 시험 — 호출자 캠페인만, Run 폴더 이름 검사, 명령 없는 판은 koochainrun_outdated, 명령별 인자·산출 읽기
"""가짜 KooChainRun(STMC_KOOCHAINRUN)이 받은 인자를 적고 명령마다 산출을 흉내 낸다. FAKE_KCR_MISSING 에 든 명령은
`--help` 가 실패한다(Pre v141 보다 낮은 헤드). 가짜 backend·시험 사용자 영역은 conftest.py.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

FAKE = r'''#!/usr/bin/env python3
import json, os, sys
cmd, rest = sys.argv[1], sys.argv[2:]
with open(os.environ["FAKE_KCR_LOG"], "a") as f:
    f.write(json.dumps([cmd] + rest) + "\n")
if rest == ["--help"]:
    sys.exit(2 if cmd in os.environ.get("FAKE_KCR_MISSING", "").split(",") else 0)
def opt(flag):
    return rest[rest.index(flag) + 1] if flag in rest else None
if cmd == "provenance":
    json.dump({"run": os.path.basename(rest[0])}, open(os.path.join(rest[0], "provenance.json"), "w"))
elif cmd == "manifest":
    with open(opt("-o"), "w") as f:
        f.write(json.dumps({"header": True, "runs": 1}) + "\n" + json.dumps({"run_key": "a"}) + "\n")
elif cmd == "health":
    print(json.dumps({"verdict": "valid", "target": rest[0]}))
elif cmd == "d3plot-delete":
    print("보존 — 허가가 없다"); sys.exit(2)
elif cmd == "budget":
    sys.exit(2)
elif cmd == "sites":
    open(opt("--csv"), "w").write("name,x,y\nS1,1,2\nS2,3,4\n")
elif cmd == "gate":
    json.dump({"pass": False, "reasons": ["mass"]}, open(opt("--json"), "w")); sys.exit(1)
'''
RUN = "Run_20261127_000001_abcdef"


@pytest.fixture
def kcr(tmp_path, monkeypatch):
    fake = tmp_path / "KooChainRun"
    fake.write_text(FAKE)
    fake.chmod(0o755)
    log = tmp_path / "kcr.log"
    monkeypatch.setenv("STMC_KOOCHAINRUN", str(fake))
    monkeypatch.setenv("FAKE_KCR_LOG", str(log))
    monkeypatch.delenv("FAKE_KCR_MISSING", raising=False)
    return lambda: [json.loads(l) for l in log.read_text().splitlines()] if log.exists() else []


def _campaign(reg, d: Path, job_id: str) -> int:
    (d / "output" / RUN).mkdir(parents=True)
    (d / "runner_config.json").write_text(json.dumps({"project": {"name": d.name}}))
    (d / "output" / "simulation_index.json").write_text(json.dumps(
        {"scenarios": [{"runs": {"p_CUM001_DOE001_S001_DROP_P0001": {"folder": RUN, "status": "completed"}}}]}))
    return reg.record_submission(tool_name="fullangle_drop_simulation", work_dir=str(d), output_dir=str(d / "output"),
                                 project_name=d.name, runner_config_path=str(d / "runner_config.json"),
                                 slurm_job_ids=[job_id])


def _calls(log, cmd):
    return [c[1:] for c in log() if c[0] == cmd and c[1:] != ["--help"]]


def test_each_tool_runs_its_command_and_reads_back_the_output(registry, area, run_as, kcr):
    mine, _ = area
    d = mine / "camp_930001"
    rid = _campaign(registry, d, "930001")
    run_dir, out_dir, cfg = str(d / "output" / RUN), str(d / "output"), str(d / "runner_config.json")

    r = run_as("job_provenance", {"registry_id": rid, "case_key": RUN})
    assert r["ok"] and r["provenance"] == {"run": RUN}, r
    r = run_as("job_manifest", {"registry_id": rid, "since": "2026-11-17T00:00"})
    assert r["ok"] and r["header"]["header"] and r["runs"] == [{"run_key": "a"}], r
    assert _calls(kcr, "manifest")[-1] == [cfg, "-o", f"{out_dir}/return_manifest.jsonl", "--since", "2026-11-17T00:00"]
    r = run_as("job_health", {"registry_id": rid, "case_key": RUN, "write": False, "no_binout": True})
    assert r["ok"] and r["health"]["verdict"] == "valid", r
    assert _calls(kcr, "health")[-1] == [run_dir, "--json", "--no-binout", "--no-write"]
    r = run_as("job_health", {"registry_id": rid})  # 캠페인 전체
    assert _calls(kcr, "health")[-1] == [cfg, "--json"], r
    r = run_as("job_extract", {"registry_id": rid, "case_key": RUN})
    assert r["ok"] and _calls(kcr, "extract")[-1] == [run_dir, "--config", cfg], r
    r = run_as("job_d3plot_delete", {"registry_id": rid, "case_key": RUN})
    assert r["ok"] and r["verdict"] == "kept" and r["dry_run"] is True, r
    assert _calls(kcr, "d3plot-delete")[-1] == [run_dir, "--config", cfg, "--run-key", "p_CUM001_DOE001_S001_DROP_P0001",
                                                "--require-clearance", "--dry-run"]
    r = run_as("job_budget", {"registry_id": rid, "pilot": run_dir, "concurrency": 8})
    assert r["ok"] and r["verdict"] == "shrink", r
    assert _calls(kcr, "budget")[-1] == [cfg, "--pilot", run_dir, "--concurrency", "8"]
    r = run_as("job_keeper", {"registry_id": rid, "mem": "200G"})
    assert r["ok"] and r["dry_run"] is True and _calls(kcr, "keeper")[-1] == [cfg, "--dry-run", "--mem", "200G"], r
    r = run_as("job_sites", {"registry_id": rid, "face": "TOP"})
    assert r["ok"] and [s["name"] for s in r["sites"]] == ["S1", "S2"], r
    r = run_as("job_gate", {"registry_id": rid, "canary": "1,5"})
    assert r["ok"] is False and r["verdict"] == "reject" and r["report"]["reasons"] == ["mass"], r


def test_outdated_head_refuses_before_running(registry, area, run_as, kcr, monkeypatch):
    mine, _ = area
    rid = _campaign(registry, mine / "camp_930002", "930002")
    monkeypatch.setenv("FAKE_KCR_MISSING", "provenance")
    r = run_as("job_provenance", {"registry_id": rid, "case_key": RUN})
    assert r["ok"] is False and "koochainrun_outdated" in r["reason"], r
    assert _calls(kcr, "provenance") == []


def test_another_users_campaign_and_foreign_paths_are_refused(registry, area, run_as, kcr):
    mine, theirs = area
    other = _campaign(registry, theirs / "camp_930003", "930003")
    r = run_as("job_manifest", {"registry_id": other})
    assert r["ok"] is False, r
    rid = _campaign(registry, mine / "camp_930004", "930004")
    r = run_as("job_provenance", {"registry_id": rid, "case_key": "../../x"})
    assert r["ok"] is False and "Run 폴더 이름" in r["reason"], r
    (theirs / "t.json").write_text("{}")
    r = run_as("job_health", {"registry_id": rid, "thresholds": str(theirs / "t.json")})
    assert r["ok"] is False and "허용 범위 밖" in r["reason"], r
    r = run_as("job_budget", {"registry_id": rid, "pilot": str(theirs / "camp_930003" / "output" / RUN)})
    assert r["ok"] is False and "허용 범위 밖" in r["reason"], r
    assert kcr() == [] or all(c[1:] == ["--help"] for c in kcr())


def test_keeper_submission_leaves_an_audit_row_for_the_caller(registry, area, run_as, kcr):
    import importlib
    import sys
    from conftest import SHARED, USER
    mine, _ = area
    rid = _campaign(registry, mine / "camp_930005", "930005")
    r = run_as("job_keeper", {"registry_id": rid, "dry_run": False})
    assert r["ok"] and r["dry_run"] is False and _calls(kcr, "keeper")[-1] == [str(mine / "camp_930005" / "runner_config.json")]
    sys.path.insert(0, str(SHARED))
    try:
        audit = importlib.reload(importlib.import_module("audit"))
    finally:
        sys.path.remove(str(SHARED))
    rows = [e for e in audit.list_events(limit=50) if e["tool"] == "job_keeper@1.0.0"]
    assert rows and rows[0]["actor"] == USER, rows
