#!/usr/bin/env bash
# (C) 하이브리드: 취소는 backend_5010 권한/감사 경유. registry 로 job_id 해석 + 로컬 audit 기록 유지.
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys, urllib.request, urllib.error
sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
import audit
from job_helpers import resolve_job, fail


def backend_cancel(base, token, jid):
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
    job = resolve_job(args)
    if not job:
        fail("Job not found in registry. (registry_id 또는 work_dir 을 확인하세요.)")

    base = (os.environ.get("STMC_CLUSTER_URL") or "").rstrip("/")
    token = os.environ.get("STMC_CLUSTER_TOKEN") or ""
    if not base or not token:
        fail("취소는 backend 권한을 경유합니다 — STMC_CLUSTER_URL(서버 env) 과 "
             "요청 PAT(Authorization) 가 필요합니다(fail-closed, 직접 scancel 안 함).")

    slurm_ids = list(job.get("slurm_job_ids") or [])
    if job.get("sphere_job_id"):
        slurm_ids.append(job["sphere_job_id"])
    if not slurm_ids:
        fail("이 잡에 기록된 Slurm job_id 가 없습니다(제출이 registry 에 안 남았을 수 있음).")

    results, all_ok = [], True
    for jid in slurm_ids:
        code, body = backend_cancel(base, token, str(jid))
        ok = code is not None and 200 <= code < 300
        all_ok = all_ok and ok
        results.append({"slurm_job_id": str(jid), "http": code, "ok": ok, "detail": (body or "")[:200]})

    out = {"ok": all_ok, "job_id": job["id"], "tool": job["tool_name"],
           "work_dir": job["work_dir"], "cancelled_via": "backend_5010 (권한/감사)",
           "results": results}
    if all_ok:
        registry.update_status(job["id"], "cancelled", notes="stopped via job_stop (backend)")
        out["new_status"] = "cancelled"

    actor = os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
    audit.record_event(
        actor=actor, tool="job_stop@1.1.0", action="cancel",
        summary=f"stopped job {job['id']} ({job['tool_name']}) via backend",
        target_kind="job", target_id=str(job["id"]),
        detail={"slurm_job_ids": [str(x) for x in slurm_ids], "results": results,
                "previous_status": job.get("status")},
    )
    print(json.dumps(out, ensure_ascii=False, default=str))


try:
    main()
except Exception as e:  # noqa: BLE001
    fail(f"{type(e).__name__}: {e}")
PY
