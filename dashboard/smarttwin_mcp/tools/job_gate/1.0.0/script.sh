#!/usr/bin/env bash
# job_gate — KooChainRun gate: 캠페인 덱 관문(카나리아 DOE 를 주면 이미 돈 런을 본다) — 거절이면 끝 코드 1
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import kcr_tools as K

TOOL = "job_gate@1.0.0"


def go(args):
    c = K.campaign(args)
    path = os.path.join(c["output_dir"], "gate_report.json")
    argv = [c["config"], "--json", path] + (["--canary", args["canary"]] if args.get("canary") else [])
    r = K.run("gate", argv, timeout=890)
    K.out({"ok": r.returncode == 0, "verdict": "pass" if r.returncode == 0 else ("reject" if r.returncode == 1 else "error"),
           "rc": r.returncode, "report_path": path, "report": K.read_json(path),
           "stdout": r.stdout[-4000:], "stderr": r.stderr[-1500:]}, 0 if r.returncode == 0 else 1)

K.main(go)
PY
