# job_status runs:true 시험 — 각도별 run 폴더·d3plot·상태 (낙하 트윈 계약 C-1)
"""runner_config.json 의 doe_angles 와 output/simulation_index.json 을 이은 각도별 목록.
실패·대기 각도도 빠지지 않고, index 의 folder 가 Run 폴더 꼴이 아니면 경로를 싣지 않는다.
가짜 backend·임시 DB·시험 사용자 영역은 conftest.py.
"""
from __future__ import annotations

import json
from pathlib import Path


def _campaign(d: Path, index_runs: dict | None, doe_angles: dict | None) -> Path:
    (d / "output").mkdir(parents=True)
    scen = {"total_steps": 1, "steps": [{"step": 1, "mode": "DROP", "condition": "P0001"}]}
    if doe_angles is not None:
        scen["doe_angles"] = doe_angles
    rc = d / "runner_config.json"
    rc.write_text(json.dumps({"project": {"name": d.name, "output_dir": str(d / "output")}, "scenario": scen}))
    if index_runs is not None:
        (d / "output" / "simulation_index.json").write_text(
            json.dumps({"scenarios": [{"runs": index_runs}]}))
    return rc


def _row(reg, d: Path, rc: Path, job_id: str) -> int:
    return reg.record_submission(tool_name="fullangle_drop_simulation", work_dir=str(d),
                                 output_dir=str(d / "output"), project_name=d.name,
                                 runner_config_path=str(rc), slurm_job_ids=[job_id])


ANGLES = {str(i): {"1": {"angle_name": f"P000{i}", "roll": 10.0 * i, "pitch": -5.0, "yaw": 0.0}}
          for i in (1, 2, 3, 4)}


def test_runs_lists_every_planned_angle_with_its_folder_and_status(registry, area, run_as):
    mine, _ = area
    d = mine / "camp_920001"
    rc = _campaign(d, {
        "p_CUM001_DOE001_S001_DROP_P0001": {"run_id": "20261125_000001_aaaaaa", "status": "completed",
                                            "folder": "Run_20261125_000001_aaaaaa", "mode": "DROP"},
        "p_CUM001_DOE002_S001_DROP_P0002": {"run_id": "20261125_000002_bbbbbb", "status": "failed",
                                            "folder": "Run_20261125_000002_bbbbbb", "mode": "DROP",
                                            "error": "LS-DYNA failed"},
        "p_CUM001_DOE004_S001_DROP_P0004": {"run_id": "x", "status": "completed",
                                            "folder": "../../stmcother/Run_x", "mode": "DROP"},
    }, ANGLES)
    done = d / "output" / "Run_20261125_000001_aaaaaa" / "Output"
    done.mkdir(parents=True)
    (done / "d3plot").write_bytes(b"\0")
    rid = _row(registry, d, rc, "920001")

    out = run_as("job_status", {"registry_id": rid, "runs": True})
    assert out["ok"] is True and "runs_note" not in out, out
    runs = out["runs"]
    assert [(r["doe"], r["step"]) for r in runs] == [(1, 1), (2, 1), (3, 1), (4, 1)], runs

    ok, failed, pending, bad = runs
    assert ok["case_key"] == "Run_20261125_000001_aaaaaa" and ok["status"] == "completed", ok
    assert ok["run_dir"] == str(d / "output" / "Run_20261125_000001_aaaaaa"), ok
    assert ok["d3plot"] == str(done / "d3plot"), ok
    assert ok["angle"] == {"name": "P0001", "roll": 10.0, "pitch": -5.0, "yaw": 0.0}, ok
    assert ok["mode"] == "DROP" and "error" not in ok, ok

    assert failed["status"] == "failed" and failed["error"] == "LS-DYNA failed", failed
    assert failed["run_dir"] == str(d / "output" / "Run_20261125_000002_bbbbbb"), failed
    assert failed["d3plot"] is None, failed  # 폴더는 있어도 d3plot 이 없다

    assert pending["status"] == "pending" and pending["run_dir"] is None, pending
    assert pending["case_key"] is None and pending["d3plot"] is None, pending
    assert pending["mode"] == "DROP" and pending["angle"]["name"] == "P0003", pending

    assert bad["run_dir"] is None and bad["case_key"] is None and bad["d3plot"] is None, bad


def test_runs_is_absent_unless_asked(registry, area, run_as):
    mine, _ = area
    d = mine / "camp_920002"
    rid = _row(registry, d, _campaign(d, {}, ANGLES), "920002")
    out = run_as("job_status", {"registry_id": rid})
    assert out["ok"] is True and "runs" not in out and "runs_note" not in out, out


def test_runs_before_any_angle_started_are_all_pending(registry, area, run_as):
    mine, _ = area
    d = mine / "camp_920003"
    rid = _row(registry, d, _campaign(d, None, ANGLES), "920003")
    out = run_as("job_status", {"registry_id": rid, "runs": True})
    assert out["ok"] is True and [r["status"] for r in out["runs"]] == ["pending"] * 4, out


def test_runs_on_a_job_without_angles_is_empty_with_a_note(registry, area, run_as):
    mine, _ = area
    d = mine / "camp_920004"
    rid = _row(registry, d, _campaign(d, {}, None), "920004")
    out = run_as("job_status", {"registry_id": rid, "runs": True})
    assert out["ok"] is True and out["runs"] == [] and "doe_angles" in out["runs_note"], out

    d2 = mine / "camp_920005"
    d2.mkdir()
    rid2 = registry.record_submission(tool_name="submit_lsdyna_job", work_dir=str(d2),
                                      output_dir=str(d2), project_name=d2.name, slurm_job_ids=["920005"])
    out = run_as("job_status", {"registry_id": rid2, "runs": True})
    assert out["ok"] is True and out["runs"] == [] and "runner_config" in out["runs_note"], out
