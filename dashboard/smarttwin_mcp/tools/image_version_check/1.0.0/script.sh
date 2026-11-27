#!/usr/bin/env bash
# image_version_check — 헤드·표본 노드·NFS 의 Pre/Post 이미지 판을 기대값과 대조(읽기 전용, cluster/utils/image_version_check.sh 를 감싼다)
# mode: read-all (§18.2).
set -euo pipefail
export STMC_TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 - <<'PY'
import json
import os
import subprocess
import sys

TOOL = "image_version_check"
EXPECT_ENV = {"expect_pre_sha": "EXPECT_PRE_SHA", "expect_post_sha": "EXPECT_POST_SHA",
              "expect_post_version": "EXPECT_POST_VERSION", "expect_remapper_commit": "EXPECT_REMAPPER_COMMIT",
              "expect_kcr_sha": "EXPECT_KCR_SHA"}
COLUMNS = ("where", "item", "actual", "expected", "verdict")


def fail(reason, **extra):
    print(json.dumps({"ok": False, "tool": TOOL, "reason": reason, **extra}, ensure_ascii=False))
    sys.exit(1)


args = json.loads(os.environ.get("STMC_ARGS_JSON") or "{}")
# 점검 스크립트는 판 안 사본(tools/_shared — cluster/utils/image_version_check.sh 와 바이트 동일, 시험이 묶는다).
# 운영 MCP 판 폴더는 smarttwin_mcp 만 담아 리포 뿌리의 cluster/ 가 없다. 시험·다른 배치는 env 로.
script = os.environ.get("STMC_IMAGE_CHECK_SCRIPT") or os.path.normpath(
    os.path.join(os.environ["STMC_TOOL_DIR"], "../../_shared/image_version_check.sh"))
if not os.path.isfile(script):
    fail(f"점검 스크립트가 없다: {script}")

env = dict(os.environ)
for key, var in EXPECT_ENV.items():
    env.pop(var, None)
    if args.get(key):
        env[var] = args[key]
env["NODES"] = " ".join(args.get("nodes") or [])
env["SAMPLE_PER_PARTITION"] = str(args.get("sample_per_partition", 1))
env["NODE_SHA"] = "1" if args.get("node_sha", True) else "0"

try:
    r = subprocess.run(["bash", script], capture_output=True, text=True, env=env,
                       timeout=850, stdin=subprocess.DEVNULL)
except subprocess.TimeoutExpired:
    fail("점검이 850초 안에 끝나지 않았다 — 표본 노드를 줄이거나 node_sha: false")

rows, summary = [], None
for line in r.stdout.splitlines():
    if line.startswith("| ") and not line.startswith("| 위치 |"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == len(COLUMNS):
            rows.append(dict(zip(COLUMNS, cells)))
    elif line.startswith("점검:"):
        summary = line
if not rows:
    fail("점검 표가 나오지 않았다", exit_code=r.returncode, stderr=r.stderr[-1000:])

counts = {v: sum(1 for row in rows if row["verdict"] == v) for v in ("OK", "DIFF", "ERR", "-")}
print(json.dumps({"ok": True, "tool": TOOL, "all_ok": r.returncode == 0, "counts": counts, "rows": rows,
                  "summary": summary, "table": r.stdout.strip()}, ensure_ascii=False))
PY
