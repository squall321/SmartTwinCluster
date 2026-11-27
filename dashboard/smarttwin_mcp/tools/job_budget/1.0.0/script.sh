#!/usr/bin/env bash
# job_budget — KooChainRun budget: 정상 파일럿 런을 기준으로 캠페인의 디스크 예산을 본다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import kcr_tools as K

TOOL = "job_budget@1.0.0"


def go(args):
    c = K.campaign(args)
    from stmc_exec import check_under, user_area
    argv = [c["config"], "--pilot", check_under(args["pilot"], [user_area(c["user"])], kind="dir")]
    if args.get("pilot_config"):
        argv += ["--pilot-config", K.user_file(args["pilot_config"], c["user"])]
    for k, flag in (("concurrency", "--concurrency"), ("threshold", "--threshold"), ("backlog", "--backlog")):
        if args.get(k) is not None:
            argv += [flag, str(args[k])]
    r = K.run("budget", argv, timeout=290)
    K.out({"ok": r.returncode in (0, 2), "verdict": {0: "pass", 2: "shrink", 1: "reject"}.get(r.returncode, "error"),
           "rc": r.returncode, "stdout": r.stdout[-6000:], "stderr": r.stderr[-1500:]}, 0 if r.returncode in (0, 2) else 1)

K.main(go)
PY
