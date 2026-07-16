#!/usr/bin/env bash
# submit_lsdyna_job — raw LS-DYNA .k 제출. (C): backend lsdyna-r16-basic 템플릿 경유(권한/감사).
#   라이선스·솔버 실행은 backend 템플릿이 담당 → 로컬 sbatch 직접 생성 없음.
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import job_helpers
import audit


def fail(reason, **extra):
    print(json.dumps({"ok": False, "reason": reason, **extra}, ensure_ascii=False))
    sys.exit(1)


def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])

    k_file = args["k_file"]
    if not os.path.isabs(k_file) or not os.path.exists(k_file):
        fail(f"k_file 는 존재하는 서버측 절대경로여야 합니다: {k_file}")
    ncpu = int(args.get("ncpu", 1))
    memory = args.get("memory", "2G")
    time_limit = args.get("time_limit", "01:00:00")
    partition = args.get("partition") or ""
    image = args.get("lsdyna_sif")  # backend 이미지 id. 경로(/...)면 무시하고 템플릿 기본 사용.
    job_name = args.get("job_name") or f"raw_lsdyna_{os.path.splitext(os.path.basename(k_file))[0]}"
    dry_run = bool(args.get("dry_run", False))

    slurm_overrides = {"cpus_per_task": ncpu, "mem": memory, "time": time_limit}
    if partition:
        slurm_overrides["partition"] = partition

    res = job_helpers.backend_submit(
        template_id="lsdyna-r16-basic",
        files={"input_k": k_file},
        tool_name="submit_lsdyna_job",
        project_name=job_name, job_name=job_name,
        slurm_overrides=slurm_overrides,
        image=(image if image and not str(image).startswith("/") else None),
        dry_run=dry_run)

    if dry_run:
        print(json.dumps({"ok": res.get("ok"), "dry_run": True, "sbatch_preview": res.get("sbatch_preview"),
                          "note": "제출은 backend lsdyna-r16-basic 템플릿 경유(권한/감사). 라이선스·솔버메모리는 템플릿이 설정."},
                         ensure_ascii=False))
        return

    if not res.get("ok"):
        fail(res.get("error", "backend 제출 실패"),
             **{k: res[k] for k in ("http", "response") if k in res})

    reg_id, job_id = res.get("registry_id"), res["job_id"]

    actor = os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
    audit.record_event(
        actor=actor, tool="submit_lsdyna_job@1.1.0", action="submit",
        summary=f"submitted raw lsdyna {job_name} via backend -> job {job_id}",
        target_kind="job", target_id=str(reg_id or job_id),
        detail={"k_file": k_file, "ncpu": ncpu, "memory": memory, "job_id": job_id, "dry_run": dry_run})

    print(json.dumps({
        "ok": True,
        "registry_id": reg_id,
        "job_id": job_id,
        "tool": "submit_lsdyna_job",
        "k_file": k_file,
        "job_name": job_name,
        "submitted_via": "backend_5010 lsdyna-r16-basic 템플릿 (권한/감사)",
        "follow_up_hint": "job_status/job_stop 에 registry_id 또는 job_id 사용.",
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        fail(f"unhandled exception: {type(e).__name__}: {e}")
PY
