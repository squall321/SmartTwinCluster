#!/usr/bin/env bash
# job_sites — KooChainRun sites: IMPACT 캠페인의 자리 표(sites.csv)를 만들고 읽는다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import kcr_tools as K

TOOL = "job_sites@1.0.0"


def go(args):
    c = K.campaign(args)
    import csv
    path = os.path.join(c["output_dir"], "sites.csv")
    argv = [c["config"], "--csv", path] + (["--face", args["face"]] if args.get("face") else [])
    r = K.run("sites", argv, timeout=110)
    rows = []
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace", newline="") as f:
            rows = [row for _, row in zip(range(5001), csv.DictReader(f))]
    K.out({"ok": r.returncode == 0, "rc": r.returncode, "sites_path": path, "sites": rows[:5000],
           "truncated": len(rows) > 5000, "stdout": r.stdout[-2000:], "stderr": r.stderr[-1500:]},
          0 if r.returncode == 0 else 1)

K.main(go)
PY
