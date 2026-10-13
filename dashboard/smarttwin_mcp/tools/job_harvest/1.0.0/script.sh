#!/usr/bin/env bash
# job_harvest — KooChainRun harvest 로 끝난 캠페인의 위험 상위 각도·위치를 risk_<kind>.json 으로 뽑는다
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, subprocess, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
from stmc_exec import StmcError, caller_identity, campaign_dir, check_under, find_owned_job, user_area
from job_helpers import KOOCHAINRUN

TOOL = "job_harvest@1.0.0"


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.exit(code)


def risk_files(d):
    return {f: os.path.getmtime(os.path.join(d, f)) for f in ("risk_angles.json", "risk_positions.json")
            if os.path.isfile(os.path.join(d, f))}


def main(args):
    if args.get("parts") and args.get("from_scenario"):
        raise StmcError("parts 와 from_scenario 는 함께 쓸 수 없다")
    ident = caller_identity()
    job_dir, row = find_owned_job(args, ident["username"])
    if not os.path.isdir(job_dir):
        raise StmcError(f"결과 폴더가 아직 없다: {job_dir}")
    try:
        test_dir = campaign_dir(job_dir, row)
    except StmcError:
        test_dir = job_dir  # 통합 리포트만 있는 폴더도 된다
    cmd = [KOOCHAINRUN, "harvest", test_dir]
    for k, flag in (("top", "--top"), ("z_thr", "--z-thr"), ("yield_factor", "--yield-factor"), ("parts", "--parts"),
                    ("yield_mpa", "--yield"), ("yield_by_part", "--yield-by-part")):
        if args.get(k) is not None:
            cmd += [flag, str(args[k])]
    if args.get("from_scenario"):
        cmd += ["--from-scenario", check_under(args["from_scenario"], [user_area(ident["username"])], kind="file")]
    if args.get("hot_only"):
        cmd.append("--hot-only")
    before = risk_files(test_dir)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=540)
    made = {f: os.path.join(test_dir, f) for f, t in risk_files(test_dir).items() if before.get(f) != t}
    preview = {}
    for f, p in made.items():
        with open(p, encoding="utf-8", errors="replace") as fh:
            preview[p] = fh.read(4000)
    if r.returncode == 0 and made:
        import audit
        audit.record_event(actor=ident["username"], tool=TOOL, action="pipeline_step",
                           summary=f"harvest -> {', '.join(made)}", target_kind="job", target_id=test_dir,
                           detail={"args": cmd[3:], "files": list(made.values())})
    out({"ok": r.returncode == 0, "test_dir": test_dir, "rc": r.returncode, "risk_files": list(made.values()),
         "preview": preview, "stdout": r.stdout[-5000:], "stderr": r.stderr[-1500:]}, 0 if r.returncode == 0 else 1)


try:
    main(json.loads(os.environ.get("STMC_ARGS_JSON") or "{}"))
except StmcError as e:
    out({"ok": False, "reason": str(e)}, 1)
except Exception as e:  # noqa: BLE001
    out({"ok": False, "reason": f"{type(e).__name__}: {e}"}, 1)
PY
