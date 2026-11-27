#!/usr/bin/env bash
# job_health — KooChainRun health: 런(또는 캠페인 전체)의 정상 종료·건강 판정
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import kcr_tools as K

TOOL = "job_health@1.0.0"


def go(args):
    c = K.campaign(args)
    import json
    argv = [c.get("run_dir") or c["config"], "--json"]
    if args.get("thresholds"):
        argv += ["--thresholds", K.user_file(args["thresholds"], c["user"])]
    if args.get("no_binout"):
        argv.append("--no-binout")
    if not args.get("write", True):
        argv.append("--no-write")
    r = K.run("health", argv, timeout=590)
    try:
        verdict = json.loads(r.stdout)
    except ValueError:
        verdict = None
    K.out({"ok": r.returncode == 0, "rc": r.returncode, "target": argv[0], "health": verdict,
           "stdout": "" if verdict is not None else r.stdout[-4000:], "stderr": r.stderr[-1500:]},
          0 if r.returncode == 0 else 1)

K.main(go)
PY
