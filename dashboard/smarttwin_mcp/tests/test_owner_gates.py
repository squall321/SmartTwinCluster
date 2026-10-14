# 소유권·경로 게이트 시험 — job_* 는 PAT 호출자의 잡만, 낙하 도구는 허용 루트 안만, 옛 버전은 최신으로 위임
"""HWAX 게이트웨이는 plat:smarttwin 사용자 누구에게나 이 MCP 를 연다. 그래서
- job_*·get_job_details·my_jobs·batch_cancel_jobs 는 PAT(/api/me) 호출자의 잡(잡 폴더가 /data/single/<사용자> 안)만,
- fullangle·single drop 은 work_dir·model_file_path 가 허용 루트 안일 때만,
- 옛 버전을 version 으로 고정해 불러도 같은 검사를 지나야 한다(위임 스텁).
가짜 backend·임시 DB·시험 사용자 영역은 conftest.py.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from conftest import TOOLS, USER

JOB_TOOLS = ["job_status", "job_collect", "job_diagnose", "job_logs", "job_logs_mpi", "job_progress",
             "job_postprocess", "job_rerun", "job_stop", "fetch_job_output", "get_job_details"]
DELEGATED = {  # 도구: ([옛 버전], 위임 대상)
    "fullangle_drop_simulation": (["1.0.0", "1.1.0", "1.1.1"], "1.1.2"),
    "single_drop_simulation": (["1.0.0", "1.1.0", "1.1.1"], "1.1.2"),
    "batch_cancel_jobs": (["1.0.0"], "1.1.0"),
    "job_stop": (["1.0.0"], "1.1.0"),
    "job_rerun": (["1.0.0"], "1.1.0"),
    "submit_lsdyna_job": (["1.0.0"], "1.1.0"),
    "submit_lsdyna_remote": (["1.0.0"], "1.1.0"),
    "train_pytorch_gpu": (["1.0.0"], "1.1.0"),
    "submit_distributed_train": (["1.0.0"], "1.1.0"),
    "scenario_full_reference": (["1.0.0"], "1.0.1"),
}
MODEL = "*KEYWORD\n*NODE\n       1             0.0             0.0             0.0\n*END\n"


def _row(reg, d: Path, tool="fullangle_drop_simulation", job_id="910001") -> int:
    return reg.record_submission(tool_name=tool, work_dir=str(d), output_dir=str(d / "output"),
                                 project_name=d.name, slurm_job_ids=[job_id])


# ── job_* 소유권 ─────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("tool", JOB_TOOLS)
def test_job_tools_refuse_another_users_job(registry, area, run_as, tool):
    _, theirs = area
    rid = _row(registry, theirs / "camp_910001")
    out = run_as(tool, {"registry_id": rid})
    assert out["ok"] is False and "잡이 아니다" in out["reason"], out
    out = run_as(tool, {"registry_id": rid}, token=None)
    assert out["ok"] is False and "PAT" in out["reason"], out


def test_job_status_and_details_work_for_the_owner(registry, area, run_as):
    mine, _ = area
    rid = _row(registry, mine / "camp_910002", job_id="910002")
    out = run_as("job_status", {"registry_id": rid})
    assert out["ok"] is True and out["work_dir"] == str(mine / "camp_910002"), out
    out = run_as("get_job_details", {"registry_id": rid})
    assert out["ok"] is True and out["job"]["id"] == rid, out
    out = run_as("job_status", {"work_dir": str(mine / "camp_910002")})
    assert out["ok"] is True and out["job_id"] == rid, out


def test_my_jobs_lists_only_the_callers_jobs(registry, area, run_as):
    mine, theirs = area
    own = _row(registry, mine / "a_910003", job_id="910003")
    _row(registry, theirs / "b_910004", job_id="910004")
    out = run_as("my_jobs", {})
    assert out["ok"] is True and out["caller"] == USER, out
    assert [j["id"] for j in out["jobs"]] == [own], out


def test_batch_cancel_skips_other_users_jobs(registry, area, run_as):
    mine, theirs = area
    own = _row(registry, mine / "a_910005", job_id="910005")
    other = _row(registry, theirs / "b_910006", job_id="910006")
    for version in ("batch_cancel_jobs", "batch_cancel_jobs@1.0.0"):
        out = run_as(version, {"registry_ids": [own, other], "dry_run": True})
        assert out["ok"] is True, out
        assert json.dumps(out).count('"910006"') == 0 and '"910005"' in json.dumps(out), out
        assert out["summary"]["skipped_not_owner"] == 1 and out["summary"]["matched"] == 1, out


# ── 낙하 도구 경로 ────────────────────────────────────────────────────────────────

@pytest.fixture
def upload(area):
    mine, theirs = area
    (mine / "model.k").write_text(MODEL)
    (theirs / "model.k").write_text(MODEL)
    return mine / "model.k", theirs / "model.k"


def _drop_args(work_dir, model_path, **kw):
    return {"work_dir": str(work_dir), "model_file_path": str(model_path), "lstc_license_ip": "192.168.122.1",
            "num_angles": 4, "dry_run": True, **kw}


@pytest.mark.parametrize("tool", ["fullangle_drop_simulation", "single_drop_simulation"])
def test_drop_tools_build_inside_the_callers_area(registry, area, upload, run_as, tool):
    mine, _ = area
    args = _drop_args(mine / "wd", upload[0])
    if tool == "single_drop_simulation":
        args.pop("num_angles")
    out = run_as(tool, args)
    assert out["ok"] is True and out["scenario_path"] == str(mine / "wd" / "scenario.json"), out
    assert (mine / "wd" / "MinimumModel.k").read_text() == MODEL


@pytest.mark.parametrize("tool", ["fullangle_drop_simulation", "single_drop_simulation"])
@pytest.mark.parametrize("version", ["", "@1.0.0", "@1.1.0", "@1.1.1"])
def test_drop_tools_refuse_paths_outside_the_roots_in_every_version(registry, area, upload, run_as, tool, version,
                                                                     tmp_path):
    mine, theirs = area
    cases = [
        (_drop_args(theirs / "wd", upload[0]), "허용 범위 밖"),           # 남의 영역에 작업 폴더
        (_drop_args(tmp_path / "wd", upload[0]), "허용 범위 밖"),         # 허용 루트가 아닌 곳
        (_drop_args(mine / "wd", upload[1]), "허용 범위 밖"),             # 남의 업로드를 모델로
        (_drop_args(mine / "wd", upload[0], model_file="../x.k"), "파일 이름만"),
    ]
    for args, why in cases:
        if tool == "single_drop_simulation":
            args.pop("num_angles")
        out = run_as(tool + version, args)
        assert out["ok"] is False and why in out["reason"], (args, out)
    assert not (theirs / "wd").exists() and not (tmp_path / "wd").exists()


def test_extra_work_root_from_server_env(registry, area, upload, run_as, tmp_path, monkeypatch):
    root = tmp_path / "dynaforge"
    monkeypatch.setenv("STMC_WORK_ROOTS", f"{root}/{{user}}")
    out = run_as("fullangle_drop_simulation", _drop_args(root / USER / "job1", upload[0]))
    assert out["ok"] is True, out
    out = run_as("fullangle_drop_simulation", _drop_args(root / "someone_else" / "job1", upload[0]))
    assert out["ok"] is False and "허용 범위 밖" in out["reason"], out


def test_symlinks_in_the_work_dir_are_refused(registry, area, upload, run_as, tmp_path):
    mine, _ = area
    wd = mine / "wd"
    wd.mkdir()
    (wd / "scenario.json").symlink_to(tmp_path / "elsewhere.json")
    out = run_as("fullangle_drop_simulation", _drop_args(wd, upload[0]))
    assert out["ok"] is False and "심볼릭 링크" in out["reason"], out
    assert not (tmp_path / "elsewhere.json").exists()


def test_drop_tools_need_a_pat(registry, area, upload, run_as):
    mine, _ = area
    out = run_as("fullangle_drop_simulation", _drop_args(mine / "wd", upload[0]), token=None)
    assert out["ok"] is False and "PAT" in out["reason"], out


# ── 옛 버전 위임 ──────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("tool,olds,new", [(t, o, n) for t, (o, n) in DELEGATED.items()])
def test_old_versions_delegate_to_the_fixed_version(tool, olds, new):
    new_schema = json.loads((TOOLS / tool / new / "args.schema.json").read_text())["properties"]
    for old in olds:
        d = TOOLS / tool / old
        script = (d / "script.sh").read_text()
        assert f'exec "$(dirname "$0")/../{new}/script.sh"' in script, (tool, old)
        assert os.access(d / "script.sh", os.X_OK)
        assert json.loads((d / "args.schema.json").read_text())["properties"] == new_schema, (tool, old)
        assert "deprecated: true" in (d / "meta.yaml").read_text(), (tool, old)
