# SM-01 시험 — 직접 sbatch 도구는 PAT 호출자의 허용 루트 안에서만, 잡 comment 에 호출자, submit_lsdyna_remote 는 닫힘
"""train_pytorch_gpu·submit_distributed_train 1.1.0 은 PAT 를 보지 않고 서비스 계정으로 sbatch 를 냈다.
이제 sbatch 파일을 쓰기 전에(dry_run 포함) 호출자와 work_dir 를 확인하고, 실제 제출엔 --comment=stmc:<호출자>.
실제 sbatch 대신 인자를 적어 두는 가짜 sbatch 를 PATH 앞에 둔다. 가짜 backend·시험 사용자 영역은 conftest.py.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from conftest import USER

GPU_TOOLS = {
    "train_pytorch_gpu": {"gpus": 1, "gpu_partition": "gpu-a100"},
    "submit_distributed_train": {"nodes": 2, "ntasks_per_node": 1, "gpus": 1, "gpu_partition": "gpu-a100"},
}


@pytest.fixture
def fake_sbatch(tmp_path, monkeypatch):
    """PATH 앞에 가짜 sbatch — 받은 인자를 sbatch_args.json 에 적고 잡 번호를 찍는다."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    log = tmp_path / "sbatch_args.json"
    (bindir / "sbatch").write_text(
        f"#!/bin/bash\npython3 -c 'import json,sys; json.dump(sys.argv[1:], open(\"{log}\", \"w\"))' \"$@\"\n"
        "echo 'Submitted batch job 7777'\n")
    (bindir / "sbatch").chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")
    return log


def _args(tool: str, d: Path, **kw) -> dict:
    (d / "train.py").write_text("print('hi')\n")
    return {"train_script": str(d / "train.py"), "work_dir": str(d), **GPU_TOOLS[tool], **kw}


@pytest.mark.parametrize("tool", GPU_TOOLS)
def test_another_users_work_dir_is_refused_even_in_dry_run(registry, area, run_as, tool):
    _, theirs = area
    out = run_as(tool, _args(tool, theirs, dry_run=True))
    assert out["ok"] is False and "허용 범위 밖" in out["reason"], out
    assert not (theirs / "train.sbatch").exists()


@pytest.mark.parametrize("tool", GPU_TOOLS)
def test_no_pat_is_refused(registry, area, run_as, tool):
    mine, _ = area
    out = run_as(tool, _args(tool, mine, dry_run=True), token=None)
    assert out["ok"] is False and "PAT" in out["reason"], out
    assert not (mine / "train.sbatch").exists()


@pytest.mark.parametrize("tool", GPU_TOOLS)
def test_own_work_dir_submits_with_the_caller_in_the_job_comment(registry, area, run_as, fake_sbatch, tool):
    mine, _ = area
    out = run_as(tool, _args(tool, mine, dry_run=False))
    assert out["ok"] is True and out["slurm_job_ids"] == ["7777"], out
    argv = json.loads(fake_sbatch.read_text())
    assert argv == [f"--comment=stmc:{USER}", str(mine / "train.sbatch")], argv
    row = registry.get_by_id(out["registry_id"])
    assert row["extra"]["caller"] == USER, row


@pytest.mark.parametrize("version", ["1.1.0", "1.0.0"])
def test_submit_lsdyna_remote_is_closed(registry, run_as, version):
    out = run_as(f"submit_lsdyna_remote@{version}", {"k_file": "/data/single/x/in.k", "lstc_license_ip": "10.0.0.1"})
    assert out["ok"] is False and "닫혔다" in out["reason"], out
