#!/usr/bin/env bash
# tool_result — smarttwin-tool 잡의 상태·rc·산출물·로그 꼬리를 호출자 영역 안에서 읽는다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity, find_owned_job, read_result, wait_result

TOOL = "tool_result@1.0.0"


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.exit(code)


def queue_of(ids):
    if not ids:
        return []
    r = subprocess.run(["squeue", "-h", "-o", "%i %T %M %r", "-j", ",".join(ids)],
                       capture_output=True, text=True, timeout=30)
    return r.stdout.strip().splitlines() if r.returncode == 0 else []


def audit_inspect(user, target):
    try:
        import audit
        if not audit.session_seen(user, TOOL, target, within_sec=300):
            audit.record_event(actor=user, tool=TOOL, action="inspect", summary=f"read tool result {target}",
                               target_kind="job", target_id=target)
    except Exception:  # noqa: BLE001 — 감사 실패가 조회를 막지 않는다
        pass


def main(args):
    ident = caller_identity()
    job_dir, row = find_owned_job(args, ident["username"])
    row = row or {}
    extra = row.get("extra") if isinstance(row.get("extra"), dict) else {}
    ids = [str(i) for i in (row.get("slurm_job_ids") or ([args["job_id"]] if args.get("job_id") else []))]
    base = {"ok": True, "tool": row.get("tool_name"), "registry_id": row.get("id"), "job_ids": ids,
            "result_dir": job_dir, "queue": queue_of(ids)}
    audit_inspect(ident["username"], str(row.get("id") or job_dir))
    if extra.get("kind") == "smarttwin-tool" or os.path.isfile(os.path.join(job_dir, "stmc_result.json")):
        w = int(args.get("wait_sec") or 0)
        out({**base, "result": (wait_result(job_dir, w) if w else None) or read_result(job_dir)})
    files = sorted(os.listdir(job_dir))[:100] if os.path.isdir(job_dir) else []
    out({**base, "kind": extra.get("kind") or "unknown", "files": files,
         "note": "smarttwin-tool 잡이 아니다 — KooChainRun 캠페인이면 job_status·job_collect·job_diagnose 를 쓸 것."})


try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
