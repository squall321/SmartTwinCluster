#!/usr/bin/env bash
# batch_cancel_jobs — cancel many jobs by filter (mode: own, dry_run default true)
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"

python3 - <<'PY'
import json, os, sys, urllib.request, urllib.error

sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
import job_helpers
import audit

MAX_BATCH = 100


def _backend_cancel(base, token, jid):
    # (C): 직접 scancel 대신 backend 권한/감사 경유로 취소.
    req = urllib.request.Request(
        f"{base}/api/slurm/jobs/{jid}/cancel",
        data=json.dumps({"dry_run": False}).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return None, str(e)

def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])

    caller = os.environ.get("USER") or os.environ.get("LOGNAME")
    if not caller:
        job_helpers.fail("cannot determine caller identity (USER/LOGNAME unset)")

    dry_run = bool(args.get("dry_run", True))

    # --- collect candidate jobs, ALWAYS filtered by user = caller first ---
    if "registry_ids" in args:
        # explicit-id path. Look each up; skip rows owned by other users (don't fail —
        # the user may have passed a mixed list and only own a subset).
        candidates = []
        skipped_not_owner = 0
        missing = []
        for rid in args["registry_ids"]:
            row = registry.get_by_id(int(rid))
            if row is None:
                missing.append(rid)
                continue
            if row.get("user") != caller:
                skipped_not_owner += 1
                continue
            candidates.append(row)
    else:
        # filter path. Use SQL filters from registry.list_recent where possible.
        skipped_not_owner = 0  # SQL filter already excludes other users
        missing = []
        submitted_before = args.get("submitted_before")
        # If submitted_before is set, we post-filter — fetch a wider pool so we
        # can still detect "> MAX_BATCH" matches accurately.
        fetch_limit = (MAX_BATCH * 5 + 1) if submitted_before is not None else (MAX_BATCH + 1)
        candidates = registry.list_recent(
            limit=fetch_limit,
            user=caller,
            status=args.get("status"),
            tool=args.get("tool_name"),
            project_like=args.get("project_like"),
        )
        if submitted_before is not None:
            candidates = [c for c in candidates if (c.get("submitted_at") or 0) < int(submitted_before)]

    # --- enforce hard batch cap on the FINAL matched count ---
    if len(candidates) > MAX_BATCH:
        job_helpers.fail(
            f"batch too large: {len(candidates)} matches > MAX_BATCH={MAX_BATCH}. "
            f"Narrow your filter (e.g. submitted_before, project_like) or chunk the request.",
            matched=len(candidates),
            max_batch=MAX_BATCH,
        )

    def summarize(row):
        return {
            "registry_id": row["id"],
            "tool_name": row.get("tool_name"),
            "project_name": row.get("project_name"),
            "work_dir": row.get("work_dir"),
            "slurm_job_ids": row.get("slurm_job_ids") or [],
            "status": row.get("status"),
            "user": row.get("user"),
        }

    out = {
        "ok": True,
        "tool": "batch_cancel_jobs",
        "dry_run": dry_run,
        "would_cancel": [],
        "cancelled": [],
        "failures": [],
    }

    if dry_run:
        out["would_cancel"] = [summarize(r) for r in candidates]
    else:
        base = (os.environ.get("STMC_CLUSTER_URL") or "").rstrip("/")
        token = os.environ.get("STMC_CLUSTER_TOKEN") or ""
        if not base or not token:
            job_helpers.fail("취소는 backend 권한을 경유합니다 — STMC_CLUSTER_URL(서버 env) 과 "
                             "요청 PAT(Authorization) 가 필요합니다(fail-closed).")
        for row in candidates:
            slurm_ids = row.get("slurm_job_ids") or []
            entry = summarize(row)
            if not slurm_ids:
                # No Slurm IDs recorded → mark cancelled in registry only.
                registry.update_status(row["id"], "cancelled",
                                       notes="cancelled via batch_cancel_jobs (no slurm ids)")
                out["cancelled"].append(entry)
                continue
            # (C): 각 slurm id 를 backend 권한/감사 경유로 취소.
            per, all_ok = [], True
            for s in slurm_ids:
                code, body = _backend_cancel(base, token, str(s))
                ok = code is not None and 200 <= code < 300
                all_ok = all_ok and ok
                per.append({"slurm_job_id": str(s), "http": code, "ok": ok})
            entry["cancel_results"] = per
            if all_ok:
                registry.update_status(row["id"], "cancelled",
                                       notes="cancelled via batch_cancel_jobs (backend)")
                out["cancelled"].append(entry)
            else:
                entry["reason"] = "backend cancel 일부 실패"
                out["failures"].append(entry)

    out["summary"] = {
        "matched": len(candidates),
        "cancelled": len(out["cancelled"]),
        "failed": len(out["failures"]),
        "skipped_not_owner": skipped_not_owner,
    }
    if missing:
        out["summary"]["missing_registry_ids"] = missing

    # §25.3.1 audit row — only when something was actually cancelled (real run
    # with rc=0 from scancel). dry_run is a preview and writes no audit row.
    if not dry_run and out["cancelled"]:
        cancelled_ids = [e["registry_id"] for e in out["cancelled"]]
        actor = caller  # already $USER (job_helpers.fail above ensures it's set)
        audit.record_event(
            actor=actor,
            tool="batch_cancel_jobs@1.1.0",
            action="cancel",
            summary=f"batch_cancel: cancelled {len(out['cancelled'])} jobs (matched={len(candidates)}, failed={len(out['failures'])})",
            target_kind="job",
            target_id=",".join(str(i) for i in cancelled_ids[:10]) + ("..." if len(cancelled_ids) > 10 else ""),
            detail={
                "matched": len(candidates),
                "cancelled_ids": cancelled_ids,
                "failed_count": len(out["failures"]),
                "filter": {k: args.get(k) for k in ("status", "tool_name", "project_like", "submitted_before") if args.get(k) is not None},
            },
        )

    print(json.dumps(out, ensure_ascii=False, default=str))

try:
    main()
except SystemExit:
    raise
except Exception as e:
    job_helpers.fail(f"{type(e).__name__}: {e}")
PY
