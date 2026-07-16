#!/usr/bin/env bash
# job_rerun — 실패한 DOE 케이스만 재제출. (C): registry 로 work_dir 해석 후 제출은 backend
#   /api/jobs/rerun 경유(사용자별 권한/감사 + 소유권 검증). 네이티브 KooChainRun 직접실행 없음.
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
import audit
from job_helpers import resolve_job, backend_rerun, fail

def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])
    job = resolve_job(args)
    if not job:
        fail("Job not found in registry.")
    if job["tool_name"] not in ("single_drop_simulation", "fullangle_drop_simulation"):
        fail(f"job_rerun only supports KooChainRun-based jobs. Got: {job['tool_name']}")

    res = backend_rerun(job["work_dir"])
    if not res.get("ok"):
        fail(res.get("error", "backend rerun 실패"),
             **{k: res[k] for k in ("http", "response") if k in res})

    out = {"ok": True, "job_id": job["id"], "work_dir": job["work_dir"],
           "submitted_via": "backend_5010 /api/jobs/rerun (권한/감사)",
           "koochainrun_rerun": {"rc": res.get("rc"),
                                 "stdout": (res.get("stdout") or "")[-2000:],
                                 "stderr": (res.get("stderr") or "")[-500:]}}
    registry.update_status(job["id"], "submitted", notes="rerun triggered (backend)")
    # §25.3.1 audit row (success path only; failures stay silent per §25.3).
    actor = os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
    audit.record_event(
        actor=actor,
        tool="job_rerun@1.1.0",
        action="submit",
        summary=f"rerun triggered for job {job['id']} ({job['tool_name']}) at {job['work_dir']} via backend",
        target_kind="job",
        target_id=str(job["id"]),
        detail={
            "tool_name": job["tool_name"],
            "work_dir": job["work_dir"],
            "project_name": job.get("project_name"),
            "rc": res.get("rc"),
        },
    )
    print(json.dumps(out, ensure_ascii=False, default=str))

try: main()
except Exception as e: fail(f"{type(e).__name__}: {e}")
PY
