#!/usr/bin/env bash
# job_d3plot_delete — KooChainRun d3plot-delete: 관문(리포트 완결·필수 추출·허가·health)을 지난 런만 d3plot 을 지운다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import audit
import kcr_tools as K

TOOL = "job_d3plot_delete@1.0.0"


def go(args):
    c = K.campaign(args)
    dry = args.get("dry_run", True)
    argv = [c["run_dir"], "--config", c["config"]]
    alias = K.run_alias(c)
    if alias:
        argv += ["--run-key", alias]
    if args.get("require_clearance", True):
        argv.append("--require-clearance")
    if dry:
        argv.append("--dry-run")
    r = K.run("d3plot-delete", argv, timeout=1790)
    verdict = {0: "delete" if dry else "deleted", 2: "kept"}.get(r.returncode, "error")
    if r.returncode == 0 and not dry:
        audit.record_event(actor=c["user"], tool=TOOL, action="pipeline_step", summary=f"d3plot-delete {c['case_key']}",
                           target_kind="job", target_id=c["test_dir"], detail={"argv": argv})
    K.out({"ok": r.returncode in (0, 2), "case_key": c["case_key"], "run_key": alias, "dry_run": dry,
           "verdict": verdict, "rc": r.returncode, "stdout": r.stdout[-6000:], "stderr": r.stderr[-2000:]},
          0 if r.returncode in (0, 2) else 1)

K.main(go)
PY
