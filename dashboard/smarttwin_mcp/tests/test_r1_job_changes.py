# R1 시험 — job_changes 는 호출자 잡 가운데 커서 뒤에 상태가 바뀐 것을 시간순으로, limit·next_cursor 로 이어 부르기
"""가짜 sacct 가 FAKE_SACCT 의 줄(JobID|State|Submit|Start|End)을 찍는다. 가짜 backend·시험 사용자 영역은 conftest.py."""
from __future__ import annotations

import os

import pytest


@pytest.fixture
def sacct(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    (bindir / "sacct").write_text('#!/bin/bash\nprintf "%b" "${FAKE_SACCT:-}"\n')
    (bindir / "sacct").chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")
    return lambda text: monkeypatch.setenv("FAKE_SACCT", text)


def _row(reg, d, jid):
    d.mkdir(parents=True, exist_ok=True)
    return reg.record_submission(tool_name="fullangle_drop_simulation", work_dir=str(d), output_dir=str(d / "output"),
                                 project_name=d.name, slurm_job_ids=[jid])


def test_changes_after_the_cursor_in_time_order(registry, area, run_as, sacct):
    mine, theirs = area
    a = _row(registry, mine / "a_950001", "950001")
    b = _row(registry, mine / "b_950002", "950002")
    c = _row(registry, mine / "c_950003", "950003")
    _row(registry, theirs / "x_950004", "950004")  # 남의 잡 — 안 나온다
    sacct("950001|COMPLETED|2026-11-27T08:00:00|2026-11-27T08:01:00|2026-11-27T09:30:00\\n"
          "950002|CANCELLED by 1000|2026-11-27T08:00:00|2026-11-27T08:02:00|2026-11-27T09:10:00\\n"
          "950003|RUNNING|2026-11-27T08:00:00|2026-11-27T09:20:00|Unknown\\n"
          "950004|FAILED|2026-11-27T08:00:00|2026-11-27T08:05:00|2026-11-27T09:40:00\\n")
    out = run_as("job_changes", {"cursor": "2026-11-27T09:00:00"})
    assert out["ok"] and [(e["registry_id"], e["state"]) for e in out["events"]] == \
        [(b, "cancelled"), (c, "running"), (a, "completed")], out
    assert out["events"][0]["changed_at"] == "2026-11-27T09:10:00" and out["truncated"] is False

    first = run_as("job_changes", {"cursor": "2026-11-27T09:00:00", "limit": 1})
    assert first["truncated"] is True and first["next_cursor"] == f"2026-11-27T09:10:00#{b}", first
    rest = run_as("job_changes", {"cursor": first["next_cursor"]})
    assert [e["registry_id"] for e in rest["events"]] == [c, a], rest


def test_no_pat_is_refused(registry, run_as, sacct):
    out = run_as("job_changes", {}, token=None)
    assert out["ok"] is False and "PAT" in out["reason"], out
