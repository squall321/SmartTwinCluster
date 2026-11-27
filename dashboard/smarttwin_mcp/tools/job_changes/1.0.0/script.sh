#!/usr/bin/env bash
# job_changes — 호출자 잡 가운데 상태가 바뀐 것 목록(커서 = 시각#registry_id) — 게이트웨이 이벤트 허브가 잡 끝을 받는 읽기 도구(R1)
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timedelta
sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
from job_helpers import caller_name, fail, is_owner, state_word

TERMINAL = ("completed", "failed", "cancelled")


def sacct(ids):
    try:
        r = subprocess.run(["sacct", "-n", "-X", "-P", "-j", ",".join(ids), "-o", "JobID,State,Submit,Start,End"],
                           capture_output=True, text=True, timeout=30)
    except Exception:
        return {}
    out = {}
    for line in r.stdout.splitlines():
        p = line.strip().split("|")
        if len(p) == 5 and p[0]:
            out[p[0]] = {"state": p[1].split()[0] if p[1].strip() else "", "submit": p[2], "start": p[3], "end": p[4]}
    return out


def ts(v):
    try:
        return datetime.fromisoformat(v)
    except (TypeError, ValueError):
        return None


def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])
    user = caller_name()
    cur_t, _, cur_id = (args.get("cursor") or "").partition("#")
    since = ts(cur_t) if cur_t else datetime.now() - timedelta(hours=24)
    if since is None:
        fail("cursor 는 ISO 시각(예 2026-11-27T09:00:00) 또는 앞 응답의 next_cursor 여야 한다")
    after = (since, int(cur_id) if cur_id.isdigit() else -1)
    limit = int(args.get("limit", 50))
    rows = [r for r in registry.list_recent(limit=1000) if r.get("slurm_job_ids") and is_owner(r, user)]
    acct = sacct(sorted({str(i) for r in rows for i in r["slurm_job_ids"]})) if rows else {}
    events = []
    for r in rows:
        jobs = {str(i): acct.get(str(i)) or {} for i in r["slurm_job_ids"]}
        state = state_word([j.get("state") for j in jobs.values()])
        key = "end" if state in TERMINAL else ("start" if state == "running" else "submit")
        times = [t for t in (ts(j.get(key)) for j in jobs.values()) if t]
        if not times:
            continue
        when = max(times)
        if (when, r["id"]) <= after:
            continue
        events.append({"kind": "job_state", "registry_id": r["id"], "tool": r.get("tool_name"),
                       "work_dir": r.get("work_dir"), "state": state,
                       "slurm_states": {i: j.get("state") or "UNKNOWN" for i, j in jobs.items()},
                       "changed_at": when.isoformat(timespec="seconds"), "_k": (when, r["id"])})
    events.sort(key=lambda e: e["_k"])
    truncated = len(events) > limit
    events = events[:limit]
    nxt = f"{events[-1]['changed_at']}#{events[-1]['registry_id']}" if events else (args.get("cursor") or since.isoformat(timespec="seconds"))
    for e in events:
        del e["_k"]
    print(json.dumps({"ok": True, "caller": user, "events": events, "count": len(events), "truncated": truncated,
                      "next_cursor": nxt}, ensure_ascii=False))


try:
    main()
except SystemExit:
    raise
except Exception as e:  # noqa: BLE001
    fail(f"{type(e).__name__}: {e}")
PY
