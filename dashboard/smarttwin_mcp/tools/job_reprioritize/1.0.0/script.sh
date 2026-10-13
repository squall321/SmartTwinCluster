#!/usr/bin/env bash
# job_reprioritize — KooChainRun reprioritize 계획·적용(admin)·hold 해제를 캠페인 소속 잡 검증 뒤에 실행한다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity, campaign_dir, campaign_queue, find_owned_job
from job_helpers import KOOCHAINRUN

TOOL = "job_reprioritize@1.0.0"


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.exit(code)


def held(queued):
    return sorted(j for j, q in queued.items() if q["state"] == "PENDING" and q["reason"].startswith("JobHeld"))


def audit_step(user, test_dir, summary, detail):
    import audit
    audit.record_event(actor=user, tool=TOOL, action="pipeline_step", summary=summary,
                       target_kind="job", target_id=test_dir, detail=detail)


def main(args):
    if args.get("apply") and args.get("release_held"):
        raise StmcError("apply 와 release_held 는 함께 쓸 수 없다")
    ident = caller_identity()
    job_dir, row = find_owned_job(args, ident["username"])
    test_dir = campaign_dir(job_dir, row)
    if not os.path.isfile(os.path.join(test_dir, "jobs.json")):
        raise StmcError(f"jobs.json 이 없다(아직 submit 전): {test_dir}")
    queued, foreign = campaign_queue(test_dir)
    if foreign and (args.get("apply") or args.get("release_held")):
        raise StmcError(f"jobs.json 의 잡 {', '.join(foreign[:10])} 은 이 캠페인 폴더의 스크립트로 제출된 잡이 아니다 — "
                        "scontrol 을 걸지 않는다")

    if args.get("release_held"):
        done = []
        for j in held(queued):
            r = subprocess.run(["scontrol", "release", j], capture_output=True, text=True, timeout=30)
            done.append({"job_id": j, "rc": r.returncode, "error": r.stderr.strip()[:200] or None})
        ok_ids = [d["job_id"] for d in done if d["rc"] == 0]
        if ok_ids:
            audit_step(ident["username"], test_dir, f"released {len(ok_ids)} held jobs", {"job_ids": ok_ids[:50]})
        out({"ok": all(d["rc"] == 0 for d in done), "test_dir": test_dir, "released": done,
             "note": None if done else "hold 된 대기 잡이 없다"}, 0 if all(d["rc"] == 0 for d in done) else 1)

    if args.get("apply") and ident["role"] != "admin":
        raise StmcError("apply 는 admin 만 쓸 수 있다 — scontrol top/hold 는 공유 계정의 큐 순서를 바꾸고, hold 된 잡은 "
                        "풀기 전까지 돌지 않는다. 계획은 apply 없이 보고, 적용은 관리자에게 요청할 것")
    cmd = [KOOCHAINRUN, "reprioritize", test_dir]
    for k, flag in (("radius_deg", "--radius-deg"), ("z_thr", "--z-thr"), ("yield_factor", "--yield-factor"),
                    ("top_n", "--top-n")):
        if args.get(k) is not None:
            cmd += [flag, str(args[k])]
    if args.get("apply"):
        cmd.append("--apply")
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    after = campaign_queue(test_dir)[0] if args.get("apply") else queued
    if args.get("apply") and r.returncode == 0:
        audit_step(ident["username"], test_dir, "reprioritize --apply",
                   {"args": cmd[3:], "held_after": len(held(after))})
    res = {"ok": r.returncode == 0, "test_dir": test_dir, "applied": bool(args.get("apply")), "rc": r.returncode,
           "queued_jobs": len(queued), "held_jobs": held(after), "stdout": r.stdout[-6000:], "stderr": r.stderr[-1500:]}
    if held(after):
        res["note"] = "hold 된 잡은 release_held=true 로 풀기 전까지 돌지 않는다(캠페인 드라이버도 끝나지 않는다)."
    if foreign:
        res["foreign_jobs"] = foreign
    out(res, 0 if r.returncode == 0 else 1)


try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
