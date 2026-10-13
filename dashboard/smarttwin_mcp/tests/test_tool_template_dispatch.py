# smarttwin-tool 템플릿 디스패처를 가짜 apptainer 로 실행해 화이트리스트·경로 검사·결과 기록을 시험
"""backend 템플릿(dashboard/templates/official/simulation/smarttwin-tool.yaml)의 main_exec 에 박힌
파이썬 디스패처를 꺼내, Slurm 없이 가짜 `apptainer`(인자를 기록하고 산출물 하나를 만든다)로 돌린다.

디스패처는 사용자가 backend 에 직접 제출해도 안전해야 한다 — MCP 가 만든 request.json 만 온다고
가정하지 않는다. 그래서 거절 경로를 전부 시험한다.
"""
from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path

import pytest
import yaml

TEMPLATE = (Path(__file__).resolve().parents[2] / "templates" / "official" / "simulation"
            / "smarttwin-tool.yaml")


def _dispatcher_source() -> str:
    t = yaml.safe_load(TEMPLATE.read_text(encoding="utf-8"))
    me = t["script"]["main_exec"]
    return me.split("<<'STMC_DISPATCH'\n", 1)[1].split("\nSTMC_DISPATCH\n", 1)[0]


FAKE_APPTAINER = """#!/bin/bash
# 가짜 apptainer: 받은 인자를 기록하고, 작업 폴더에 산출물 하나를 만든다.
printf '%s\\n' "$@" > "$STMC_FAKE_LOG"
pwd_arg=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--pwd" ]; then pwd_arg="$2"; fi
  shift
done
echo "result" > "$pwd_arg/fake_output.txt"
echo "fake stdout"
exit ${STMC_FAKE_RC:-0}
"""


@pytest.fixture
def env(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    fake = bindir / "apptainer"
    fake.write_text(FAKE_APPTAINER)
    fake.chmod(0o755)
    sif = tmp_path / "pre.sif"
    sif.write_text("sif")
    result = tmp_path / "result"
    (result / "work").mkdir(parents=True)
    user_area = tmp_path / "single_alice"
    user_area.mkdir()
    e = {
        "PATH": f"{bindir}:{os.environ['PATH']}",
        "RESULT_DIR": str(result),
        "WEB_USER": "alice",
        "STMC_PRE_SIF": str(sif),
        "STMC_POST_SIF": str(sif),
        "STMC_EXTRA_ROOTS": str(user_area),
        "STMC_FAKE_LOG": str(tmp_path / "fake.log"),
        "SLURM_CPUS_PER_TASK": "2",
    }
    return {"env": e, "tmp": tmp_path, "result": result, "user_area": user_area}


def _run(env, request: dict, files: dict[str, str] | None = None, raw_members=None, extra_env=None):
    tmp = env["tmp"]
    req = tmp / "request.json"
    req.write_text(json.dumps(request))
    e = {**env["env"], "FILE_REQUEST_JSON": str(req), **(extra_env or {})}
    if files is not None or raw_members is not None:
        tgz = tmp / "inputs.tgz"
        with tarfile.open(tgz, "w:gz") as tf:
            for name, text in (files or {}).items():
                data = text.encode()
                ti = tarfile.TarInfo(name)
                ti.size = len(data)
                tf.addfile(ti, io.BytesIO(data))
            for ti in raw_members or []:
                tf.addfile(ti, io.BytesIO(b""))
        e["FILE_INPUTS_TGZ"] = str(tgz)
    proc = subprocess.run([sys.executable, "-c", _dispatcher_source()], env=e,
                          capture_output=True, text=True, cwd=str(env["result"]))
    res_path = env["result"] / "stmc_result.json"
    res = json.loads(res_path.read_text()) if res_path.exists() else None
    return proc, res


def _req(**kw):
    base = {"schema": "stmc-tool/1", "tool": "remap_info", "family": "remap",
            "binary": "KooRemapper", "argv": ["info", "@@WORK@@/model.k"]}
    base.update(kw)
    return base


def test_happy_path_runs_whitelisted_binary(env):
    proc, res = _run(env, _req(texts=["model.k"]), files={"model.k": "*KEYWORD\n*END\n"})
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert res["ok"] is True and res["rc"] == 0 and res["state"] == "done"
    assert res["inputs"] == ["model.k"]
    assert any(o["path"].endswith("fake_output.txt") for o in res["outputs"])
    assert not any(o["path"].endswith("model.k") for o in res["outputs"])  # 입력은 산출물이 아니다
    called = Path(env["env"]["STMC_FAKE_LOG"]).read_text().splitlines()
    assert called[-3:] == ["/opt/kooremapper/bin/KooRemapper", "info",
                           str(env["result"] / "work" / "model.k")]  # @@WORK@@ 치환
    assert "--bind" in called and "/data:/data" in called


def test_nonzero_rc_is_reported(env):
    proc, res = _run(env, _req(), files={"model.k": "x"}, extra_env={"STMC_FAKE_RC": "3"})
    assert proc.returncode == 3
    assert res["ok"] is False and res["rc"] == 3


@pytest.mark.parametrize("family,binary", [("remap", "bash"), ("shell", "KooRemapper"),
                                           ("post", "python3"), ("kmm", "KooRemapper")])
def test_rejects_non_whitelisted(env, family, binary):
    proc, res = _run(env, _req(family=family, binary=binary))
    assert proc.returncode == 1 and res["ok"] is False
    assert "허용되지 않은" in res["error"]


def test_rejects_bad_schema(env):
    proc, res = _run(env, _req(schema="other"))
    assert proc.returncode == 1 and "schema" in res["error"]


def test_rejects_argv_not_list_of_str(env):
    proc, res = _run(env, _req(argv="info model.k"))
    assert proc.returncode == 1 and "argv" in res["error"]


def test_rejects_foreign_absolute_path_in_argv(env):
    proc, res = _run(env, _req(argv=["info", "/etc/passwd"]))
    assert proc.returncode == 1 and "허용 범위 밖" in res["error"]
    proc, res = _run(env, _req(argv=["info", "--model=/data/single/bob/secret.k"]))
    assert proc.returncode == 1 and "허용 범위 밖" in res["error"]


def test_allows_bundle_paths_in_argv(env):
    proc, res = _run(env, _req(argv=["matdb", "/opt/kooremapper/materials/material_db.json"]))
    assert proc.returncode == 0, res


def test_rejects_dotdot_in_argv(env):
    proc, res = _run(env, _req(argv=["info", "../../bob/secret.k"]))
    assert proc.returncode == 1 and "'..'" in res["error"]


def test_rejects_unsafe_tar_members(env):
    evil = tarfile.TarInfo("../evil.txt")
    proc, res = _run(env, _req(), raw_members=[evil])
    assert proc.returncode == 1 and "안전하지 않은" in res["error"]
    link = tarfile.TarInfo("link")
    link.type = tarfile.SYMTYPE
    link.linkname = "/etc/passwd"
    proc, res = _run(env, _req(), raw_members=[link])
    assert proc.returncode == 1 and "안전하지 않은" in res["error"]


def test_rejects_foreign_paths_inside_texts(env):
    opt = "*Inputfile\n/data/single/bob/model.k\n*End\n"
    proc, res = _run(env, _req(texts=["opt.txt"]), files={"opt.txt": opt})
    assert proc.returncode == 1 and "허용 범위 밖" in res["error"]
    opt = "*Inputfile\n../../bob/model.k\n*End\n"
    proc, res = _run(env, _req(texts=["opt.txt"]), files={"opt.txt": opt})
    assert proc.returncode == 1 and "'..'" in res["error"]


def test_texts_placeholders_are_substituted(env):
    opt = "*Inputfile\n@@WORK@@/model.k\n*End\n"
    proc, res = _run(env, _req(texts=["opt.txt"]), files={"opt.txt": opt, "model.k": "k"})
    assert proc.returncode == 0, res
    body = (env["result"] / "work" / "opt.txt").read_text()
    assert str(env["result"] / "work" / "model.k") in body and "@@WORK@@" not in body


def test_existing_dir_must_be_inside_user_area(env, tmp_path):
    outside = tmp_path / "elsewhere"
    outside.mkdir()
    proc, res = _run(env, _req(cwd="existing", existing_dir=str(outside), argv=["info"]))
    assert proc.returncode == 1 and "기존 폴더" in res["error"]
    inside = env["user_area"] / "case1"
    inside.mkdir()
    proc, res = _run(env, _req(cwd="existing", existing_dir=str(inside), argv=["info"]))
    assert proc.returncode == 0, res
    assert res["cwd"] == str(inside.resolve())
    assert (inside / "fake_output.txt").exists()


def test_missing_sif_fails_cleanly(env):
    proc, res = _run(env, _req(), extra_env={"STMC_PRE_SIF": "/nonexistent.sif"})
    assert proc.returncode == 1 and "SIF" in res["error"]
