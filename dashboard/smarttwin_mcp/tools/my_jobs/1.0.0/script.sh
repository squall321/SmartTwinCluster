#!/usr/bin/env bash
# my_jobs — §18 mode: own. 호출자(PAT → /api/me)의 잡(잡 폴더가 /data/single/<사용자> 안)만 나열한다.
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"

python3 - <<'PY'
import json, os, sys

sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
import job_helpers


def fail(reason, **extra):
    print(json.dumps({"ok": False, "reason": reason, **extra}, ensure_ascii=False))
    sys.exit(1)


def main():
    # §18.1: caller identity never comes from args. HTTP 서비스에서 $USER 는 서비스 계정이라
    # 웹 사용자는 PAT(/api/me)로 확인하고, 소유는 잡 폴더로 판단한다(registry user 열은 서비스 계정).
    caller = job_helpers.caller_name()

    args = json.loads(os.environ["STMC_ARGS_JSON"])

    limit = int(args.get("limit", 20))
    status = args.get("status")
    tool_name = args.get("tool_name")
    since = args.get("since")
    if since is not None:
        since = int(since)

    # 소유 판단이 잡 폴더 기준이라 SQL 로 못 거른다 — 넓게 읽고 호출자 잡만 남긴다.
    rows = [r for r in registry.list_recent(limit=5000, status=status, tool=tool_name, since=since)
            if job_helpers.is_owner(r, caller)][:limit]

    # §18.5: every row must carry `user` so the LLM can confirm ownership.
    # registry.list_recent already returns the column, but defend against
    # legacy rows where it was never written.
    for r in rows:
        r.setdefault("user", None)

    print(json.dumps({
        "ok": True,
        "tool": "my_jobs",
        "caller": caller,
        "count": len(rows),
        "jobs": rows,
    }, ensure_ascii=False, default=str))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        fail(f"{type(e).__name__}: {e}")
PY
