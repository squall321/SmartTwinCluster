#!/usr/bin/env bash
# job_extract — KooChainRun extract: 런 하나의 필수 추출만 돌리고 산출물을 확인한다(d3plot 은 지우지 않음)
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import audit
import kcr_tools as K

TOOL = "job_extract@1.0.0"


def go(args):
    c = K.campaign(args)
    argv = [c["run_dir"], "--config", c["config"]]
    if args.get("spec"):
        argv += ["--spec", K.user_file(args["spec"], c["user"])]
    r = K.run("extract", argv, timeout=3590)
    if r.returncode == 0:
        audit.record_event(actor=c["user"], tool=TOOL, action="pipeline_step", summary=f"extract {c['case_key']}",
                           target_kind="job", target_id=c["test_dir"], detail={"argv": argv})
    K.out({"ok": r.returncode == 0, "case_key": c["case_key"], "rc": r.returncode,
           "stdout": r.stdout[-6000:], "stderr": r.stderr[-2000:]}, 0 if r.returncode == 0 else 1)

K.main(go)
PY
