#!/usr/bin/env bash
# list_recent_jobs — SQLite-backed registry query
set -euo pipefail

export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"

python3 - <<'PY'
import json, os, sys, time, datetime

sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
import job_helpers
from stmc_exec import StmcError, caller_identity


def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])

    limit = int(args.get("limit", 20))
    status = args.get("status")
    tool = args.get("tool")
    project_like = args.get("project_like")
    only_mine = bool(args.get("only_mine", True))

    since = None
    hrs = args.get("since_hours_ago")
    if hrs is not None:
        since = int(time.time() - float(hrs) * 3600)

    # 호출자 = PAT 의 웹 사용자. 전체 목록은 admin 이 only_mine=false 로 물을 때만(HWAX 가 plat:smarttwin 전원에게 연다).
    # registry 의 user 열은 서비스 계정이라 소유는 잡 폴더로 본다(job_helpers.is_owner).
    try:
        ident = caller_identity()
    except StmcError as e:
        job_helpers.fail(str(e))
    see_all = (not only_mine) and ident["role"] == "admin"
    rows = registry.list_recent(
        limit=5000 if not see_all else limit, status=status, tool=tool,
        since=since, project_like=project_like,
    )
    if not see_all:
        rows = [r for r in rows if job_helpers.is_owner(r, ident["username"])][:limit]

    # Add human-readable timestamps
    for r in rows:
        ts = r.get("submitted_at")
        if ts:
            r["submitted_at_human"] = datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
        # Truncate notes for brevity
        if r.get("notes") and len(r["notes"]) > 200:
            r["notes"] = r["notes"][:200] + "..."

    print(json.dumps({
        "ok": True,
        "total_returned": len(rows),
        "filters_applied": {
            "limit": limit, "status": status, "tool": tool,
            "since_hours_ago": hrs, "project_like": project_like,
            "only_mine": only_mine,
        },
        "caller": ident["username"],
        "scope": "all" if see_all else "mine",
        "note": None if see_all or only_mine else "전체 목록은 admin 만 볼 수 있다 — 내 잡만 돌려준다",
        "jobs": rows,
    }, ensure_ascii=False, default=str))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({"ok": False, "reason": f"{type(e).__name__}: {e}"}))
        sys.exit(1)
PY
