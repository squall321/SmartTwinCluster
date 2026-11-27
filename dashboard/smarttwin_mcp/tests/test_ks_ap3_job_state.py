# KS-AP3 시험 — job_status state 는 Slurm 상태를 queued·running·completed·failed·cancelled·unknown 하나로, 끝난 잡은 sacct 로
"""가짜 squeue·sacct 를 PATH 앞에 둔다(FAKE_SQUEUE·FAKE_SACCT 의 줄을 그대로 찍는다). 가짜 backend·시험 사용자 영역은 conftest.py."""
from __future__ import annotations

import json
import os

import pytest


@pytest.fixture
def slurm(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for name, var in (("squeue", "FAKE_SQUEUE"), ("sacct", "FAKE_SACCT")):
        (bindir / name).write_text(f'#!/bin/bash\nprintf "%b" "${{{var}:-}}"\n')
        (bindir / name).chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")

    def set_(squeue="", sacct=""):
        monkeypatch.setenv("FAKE_SQUEUE", squeue)
        monkeypatch.setenv("FAKE_SACCT", sacct)
    return set_


def _job(reg, d, ids, index_runs=None):
    d.mkdir(parents=True, exist_ok=True)
    rc = None
    if index_runs is not None:
        (d / "output").mkdir()
        rc = d / "runner_config.json"
        rc.write_text("{}")
        (d / "output" / "simulation_index.json").write_text(json.dumps({"scenarios": [{"runs": index_runs}]}))
    return reg.record_submission(tool_name="fullangle_drop_simulation", work_dir=str(d), output_dir=str(d / "output"),
                                 project_name=d.name, runner_config_path=str(rc) if rc else None, slurm_job_ids=ids)


@pytest.mark.parametrize("squeue,sacct,word", [
    ("940001 RUNNING drv node1\\n", "", "running"),
    ("940001 PENDING drv (Priority)\\n", "", "queued"),
    ("", "940001|COMPLETED\\n", "completed"),
    ("", "940001|CANCELLED by 1000\\n", "cancelled"),
    ("", "940001|TIMEOUT\\n", "failed"),
    ("", "", "unknown"),
])
def test_single_job_state_word(registry, area, run_as, slurm, squeue, sacct, word):
    mine, _ = area
    slurm(squeue, sacct)
    rid = _job(registry, mine / f"j_{word}", ["940001"])
    out = run_as("job_status", {"registry_id": rid})
    assert out["ok"] and out["state"] == word, out
    assert list(out["slurm_states"]) == ["940001"], out


def test_mixed_jobs_and_runs_summary(registry, area, run_as, slurm):
    mine, _ = area
    slurm("940002 RUNNING drv node1\\n", "940003|COMPLETED\\n")
    rid = _job(registry, mine / "camp_mixed", ["940002", "940003"],
               {"a_DOE001_S001_X": {"status": "completed"}, "a_DOE002_S001_X": {"status": "failed"},
                "a_DOE003_S001_X": {"status": "completed"}})
    out = run_as("job_status", {"registry_id": rid})
    assert out["state"] == "running" and out["slurm_states"] == {"940002": "RUNNING", "940003": "COMPLETED"}, out
    assert out["runs_summary"] == {"completed": 2, "failed": 1}, out

    slurm("", "940002|FAILED\\n940003|CANCELLED by 1000\\n")
    assert run_as("job_status", {"registry_id": rid})["state"] == "cancelled"
