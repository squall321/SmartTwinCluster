# KooChainRun 새 명령(provenance·manifest·health·extract·d3plot-delete·budget·keeper·sites·gate) 도구 공통 — 호출자 캠페인·Run 폴더 찾기, 판 확인, 실행
"""job_* 도구 아홉이 쓴다. 캠페인은 호출자(PAT)의 잡만(find_owned_job — /data/single/<사용자> 안).
새 명령은 Pre v141 이상의 KooChainRun 에만 있다 — 운영 헤드가 낮은 판이면 실행 전에 koochainrun_outdated 로 거절한다.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

from job_helpers import KOOCHAINRUN
from stmc_exec import StmcError, caller_identity, campaign_dir, check_under, find_owned_job, user_area

RUN_KEY = re.compile(r"^Run_[A-Za-z0-9_]+$")
ALIAS = re.compile(r"_DOE(\d+)_S(\d+)_")


def out(obj: dict, code: int = 0) -> None:
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.exit(code)


def campaign(args: dict) -> dict:
    """호출자의 캠페인 — {user, test_dir, config, output_dir[, run_dir, case_key]}. case_key 를 주면 그 Run 폴더도 확인한다."""
    user = caller_identity()["username"]
    job_dir, row = find_owned_job(args, user)
    test_dir = campaign_dir(job_dir, row)
    output_dir = check_under((row or {}).get("output_dir") or os.path.join(test_dir, "output"), [user_area(user)], kind="dir")
    c = {"user": user, "test_dir": test_dir, "config": os.path.join(test_dir, "runner_config.json"), "output_dir": output_dir}
    if args.get("case_key") is not None:
        key = str(args["case_key"])
        if not RUN_KEY.fullmatch(key):
            raise StmcError(f"case_key 는 Run 폴더 이름(Run_<시각>_<해시>)이어야 한다: {key!r}")
        c["case_key"] = key
        c["run_dir"] = check_under(os.path.join(output_dir, key), [user_area(user)], kind="dir")
    return c


def user_file(path: str, user: str) -> str:
    """호출자 영역 안의 파일 — 문턱·추출 목록 같은 입력."""
    return check_under(path, [user_area(user)], kind="file")


def run_alias(c: dict) -> str | None:
    """Run 폴더의 simulation_index 별칭(삭제 허가·기록에 쓰는 런 이름). 못 찾으면 None."""
    try:
        with open(os.path.join(c["output_dir"], "simulation_index.json"), encoding="utf-8") as f:
            runs = json.load(f)["scenarios"][0]["runs"]
    except (OSError, ValueError, KeyError, IndexError):
        return None
    return next((a for a, r in runs.items() if isinstance(r, dict) and r.get("folder") == c.get("case_key")), None)


def require(cmd: str) -> None:
    """이 헤드의 KooChainRun 에 cmd 가 있는가 — 운영 헤드가 Pre v141 보다 낮으면 새 명령이 없다."""
    try:
        r = subprocess.run([KOOCHAINRUN, cmd, "--help"], capture_output=True, text=True, timeout=60)
    except OSError as e:
        raise StmcError(f"KooChainRun 을 실행하지 못했다({KOOCHAINRUN}): {e}")
    if r.returncode != 0:
        raise StmcError(f"koochainrun_outdated — 이 헤드의 KooChainRun 에 `{cmd}` 명령이 없다"
                        f"(SmartTwinPreprocessor v141 이상 필요). 헤드 이미지를 올린 뒤 다시 부를 것.")


def run(cmd: str, argv: list[str], timeout: int) -> subprocess.CompletedProcess:
    require(cmd)
    return subprocess.run([KOOCHAINRUN, cmd, *argv], capture_output=True, text=True, timeout=timeout)


def read_json(path: str, limit: int = 200_000):
    """작은 JSON 산출물을 읽는다. 없거나 깨졌으면 None, 너무 크면 앞부분 글자."""
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read(limit + 1)
    if len(text) > limit:
        return {"truncated": True, "head": text[:limit]}
    try:
        return json.loads(text)
    except ValueError:
        return {"unparsed": text[:4000]}


def main(fn) -> None:
    try:
        fn(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
    except StmcError as e:
        out({"ok": False, "reason": str(e)}, 1)
    except subprocess.TimeoutExpired as e:
        out({"ok": False, "reason": f"KooChainRun 이 {e.timeout}초 안에 끝나지 않았다"}, 1)
    except Exception as e:  # noqa: BLE001
        out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
