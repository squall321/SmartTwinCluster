#!/usr/bin/env bash
# job_keeper — KooChainRun keeper: 리포트 없는 끝난 런만 골라 deep 리포트 배열 잡 하나로 낸다(한 번)
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import audit
import kcr_tools as K

TOOL = "job_keeper@1.0.0"


def go(args):
    c = K.campaign(args)
    dry = args.get("dry_run", True)
    argv = [c["config"]] + (["--dry-run"] if dry else [])
    for k, flag in (("cpus", "--cpus"), ("mem", "--mem"), ("partition", "--partition"), ("time", "--time"),
                    ("max_parallel", "--max-parallel"), ("exclude", "--exclude")):
        if args.get(k) is not None:
            argv += [flag, str(args[k])]
    r = K.run("keeper", argv, timeout=290)
    if r.returncode == 0 and not dry:
        audit.record_event(actor=c["user"], tool=TOOL, action="pipeline_step", summary="keeper deep array",
                           target_kind="job", target_id=c["test_dir"], detail={"argv": argv, "stdout": r.stdout[-1000:]})
    K.out({"ok": r.returncode == 0, "dry_run": dry, "rc": r.returncode,
           "stdout": r.stdout[-6000:], "stderr": r.stderr[-1500:]}, 0 if r.returncode == 0 else 1)

K.main(go)
PY
