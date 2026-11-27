#!/usr/bin/env bash
# job_provenance — KooChainRun provenance: Run 폴더 하나의 출처 기록(provenance.json)을 보고, 없으면 지금 파일로 다시 만든다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import kcr_tools as K

TOOL = "job_provenance@1.0.0"


def go(args):
    c = K.campaign(args)
    r = K.run("provenance", [c["run_dir"], "--config", c["config"]], timeout=110)
    K.out({"ok": r.returncode == 0, "case_key": c["case_key"], "rc": r.returncode,
           "provenance": K.read_json(os.path.join(c["run_dir"], "provenance.json")),
           "stdout": r.stdout[-3000:], "stderr": r.stderr[-1500:]}, 0 if r.returncode == 0 else 1)

K.main(go)
PY
