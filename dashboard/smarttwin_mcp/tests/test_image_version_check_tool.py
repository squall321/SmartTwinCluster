# image_version_check 도구(cluster/utils/image_version_check.sh 감싸기) — 인자→env, 표 해석, 판정 집계, 실패 경로
import json
import os
import subprocess
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tools" / "image_version_check" / "latest" / "script.sh"
REAL_SCRIPT = Path(__file__).resolve().parents[3] / "cluster" / "utils" / "image_version_check.sh"

# 받은 env 를 표 행으로 되비추는 가짜 점검 스크립트 — 판정은 EXPECT_PRE_SHA 가 deadbeef 면 DIFF
FAKE = r'''#!/bin/bash
v=OK; [ "${EXPECT_PRE_SHA:-}" = deadbeef ] && v=DIFF
echo "| 위치 | 항목 | 실제 | 기대 | 판정 |"
echo "|---|---|---|---|---|"
echo "| 헤드 h01 | SmartTwinPreprocessor.sif sha256 | 1c973c25aaaa | ${EXPECT_PRE_SHA:--} | $v |"
echo "| env | NODES | ${NODES:-none} | - | - |"
echo "| env | NODE_SHA·SAMPLE | ${NODE_SHA}·${SAMPLE_PER_PARTITION} | - | - |"
echo "| env | KCR | ${EXPECT_KCR_SHA:-unset} | - | - |"
echo
echo "점검: fake · h01 · done"
[ $v = OK ] || exit 1
'''


def _run(tmp_path, args, script_body=FAKE, env_extra=None):
    fake = tmp_path / "check.sh"
    fake.write_text(script_body)
    env = dict(os.environ, STMC_ARGS_JSON=json.dumps(args), STMC_IMAGE_CHECK_SCRIPT=str(fake),
               EXPECT_KCR_SHA="leaked-from-server-env")
    env.update(env_extra or {})
    r = subprocess.run(["bash", str(TOOL)], capture_output=True, text=True, env=env, timeout=60)
    return r.returncode, json.loads(r.stdout)


def test_rows_counts_and_env_mapping(tmp_path):
    rc, out = _run(tmp_path, {"expect_pre_sha": "1c973c25", "nodes": ["node001", "node002"],
                              "node_sha": False, "sample_per_partition": 2})
    assert rc == 0 and out["ok"] and out["all_ok"]
    assert out["rows"][0] == {"where": "헤드 h01", "item": "SmartTwinPreprocessor.sif sha256",
                              "actual": "1c973c25aaaa", "expected": "1c973c25", "verdict": "OK"}
    by_item = {r["item"]: r["actual"] for r in out["rows"]}
    assert by_item["NODES"] == "node001 node002"
    assert by_item["NODE_SHA·SAMPLE"] == "0·2"
    assert by_item["KCR"] == "unset"          # 서버 env 의 EXPECT_* 가 새어 들어가지 않는다
    assert out["counts"] == {"OK": 1, "DIFF": 0, "ERR": 0, "-": 3}
    assert out["summary"] == "점검: fake · h01 · done"
    assert out["table"].startswith("| 위치 |")


def test_defaults(tmp_path):
    rc, out = _run(tmp_path, {})
    by_item = {r["item"]: r["actual"] for r in out["rows"]}
    assert by_item["NODES"] == "none" and by_item["NODE_SHA·SAMPLE"] == "1·1"


def test_diff_is_ok_but_not_all_ok(tmp_path):
    rc, out = _run(tmp_path, {"expect_pre_sha": "deadbeef"})
    assert rc == 0 and out["ok"] is True and out["all_ok"] is False
    assert out["counts"]["DIFF"] == 1


def test_missing_script_fails(tmp_path):
    env = dict(os.environ, STMC_ARGS_JSON="{}", STMC_IMAGE_CHECK_SCRIPT=str(tmp_path / "nope.sh"))
    r = subprocess.run(["bash", str(TOOL)], capture_output=True, text=True, env=env, timeout=60)
    out = json.loads(r.stdout)
    assert r.returncode == 1 and out["ok"] is False and "없다" in out["reason"]


def test_no_table_fails(tmp_path):
    rc, out = _run(tmp_path, {}, script_body="#!/bin/bash\necho boom >&2\nexit 2\n")
    assert rc == 1 and out["ok"] is False and "boom" in out["stderr"]


def test_default_script_path_resolves_to_repo_script():
    # 도구 폴더에서 다섯 단계 위 = 리포 뿌리 — 배포된 리포에서 env 없이 찾는다
    resolved = (TOOL.parent / "../../../../.." / "cluster/utils/image_version_check.sh").resolve()
    assert resolved == REAL_SCRIPT.resolve() and REAL_SCRIPT.is_file()
