#!/usr/bin/env bash
# job_manifest — KooChainRun manifest: 끝난 런의 귀환 매니페스트(return_manifest.jsonl)를 만들고 읽는다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import kcr_tools as K

TOOL = "job_manifest@1.0.0"


def go(args):
    c = K.campaign(args)
    path = os.path.join(c["output_dir"], "return_manifest.jsonl")
    argv = [c["config"], "-o", path] + (["--since", args["since"]] if args.get("since") else [])
    r = K.run("manifest", argv, timeout=290)
    lines = []
    if os.path.isfile(path):
        import json
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 2000:
                    break
                try:
                    lines.append(json.loads(line))
                except ValueError:
                    pass
    K.out({"ok": r.returncode == 0, "rc": r.returncode, "manifest_path": path,
           "header": lines[0] if lines else None, "runs": lines[1:], "truncated": len(lines) > 2000,
           "stdout": r.stdout[-2000:], "stderr": r.stderr[-1500:]}, 0 if r.returncode == 0 else 1)

K.main(go)
PY
