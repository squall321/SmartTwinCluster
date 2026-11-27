#!/usr/bin/env bash
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, re, sys
sys.path.insert(0, os.environ["SHARED_DIR"])
import registry
import audit
from job_helpers import resolve_job, run_koochainrun, slurm_final_states, slurm_queue_for, fail

RUN_FOLDER = re.compile(r"^Run_[A-Za-z0-9_]+$")
ALIAS = re.compile(r"_DOE(\d+)_S(\d+)_")  # KooChainRun 별칭 <project>_CUM<n>_DOE<ddd>_S<sss>_<MODE>_<condition>

def drop_runs(job):
    """각도마다 run 폴더·d3plot·상태 (C-1) — runner_config 의 doe_angles 와 output_dir 의 simulation_index 를 잇는다.
    index 는 registry output_dir 기준으로만 읽는다(runner_config 의 index_file 은 사용자가 고칠 수 있는 파일이다)."""
    rc_path = job.get("runner_config_path")
    if not rc_path or not os.path.exists(rc_path):
        return [], "KooChainRun 잡이 아니다(runner_config.json 없음)"
    with open(rc_path, encoding="utf-8") as f:
        scen = json.load(f).get("scenario") or {}
    angles = scen.get("doe_angles")
    if not angles:
        return [], "각도 DOE 잡이 아니다(runner_config 에 doe_angles 없음)"
    modes = {int(s["step"]): s.get("mode") for s in scen.get("steps") or [] if "step" in s}
    out_dir = job["output_dir"]
    try:
        with open(os.path.join(out_dir, "simulation_index.json"), encoding="utf-8") as f:
            index_runs = json.load(f)["scenarios"][0]["runs"]
    except (OSError, ValueError, KeyError, IndexError):
        index_runs = {}  # 아직 아무 각도도 시작하지 않았다 — 전부 pending
    by_key = {}
    for alias, rec in index_runs.items():
        m = ALIAS.search(alias)
        if m:
            by_key[(int(m[1]), int(m[2]))] = rec
    runs = []
    for doe in sorted(angles, key=int):
        for step in sorted(angles[doe], key=int):
            a = angles[doe][step]
            rec = by_key.get((int(doe), int(step))) or {}
            folder = rec.get("folder") or ""
            run_dir = os.path.join(out_dir, folder) if RUN_FOLDER.match(folder) else None
            d3plot = os.path.join(run_dir, "Output", "d3plot") if run_dir else None
            row = {"doe": int(doe), "step": int(step), "mode": rec.get("mode") or modes.get(int(step)),
                   "case_key": folder if run_dir else None,
                   "angle": {"name": a.get("angle_name"), "roll": a.get("roll"),
                             "pitch": a.get("pitch"), "yaw": a.get("yaw")},
                   "run_dir": run_dir,
                   "d3plot": d3plot if d3plot and os.path.isfile(d3plot) else None,
                   "status": rec.get("status") or "pending"}
            if rec.get("error"):
                row["error"] = rec["error"]
            runs.append(row)
    return runs, None

# KS-AP3 — Slurm 상태를 안정된 낱말로. 끝난 잡은 squeue 에 없어 sacct 로 본다.
STATE_WORD = {"PENDING": "queued", "REQUEUED": "queued", "CONFIGURING": "running", "RUNNING": "running",
              "COMPLETING": "running", "SUSPENDED": "running", "RESIZING": "running", "STAGE_OUT": "running",
              "COMPLETED": "completed", "CANCELLED": "cancelled", "FAILED": "failed", "TIMEOUT": "failed",
              "NODE_FAIL": "failed", "OUT_OF_MEMORY": "failed", "BOOT_FAIL": "failed", "DEADLINE": "failed",
              "PREEMPTED": "failed"}

def job_state(ids, squeue):
    """잡 전체 상태 — queued·running·completed·failed·cancelled·unknown 하나와 잡별 Slurm 상태."""
    states = {i: (squeue.get(i) or {}).get("state") for i in ids}
    missing = [i for i, st in states.items() if not st]
    if missing:
        final = slurm_final_states(missing)
        states.update({i: final.get(i) for i in missing})
    words = {STATE_WORD.get(st or "", "unknown") for st in states.values()}
    if not ids:
        word = "unknown"
    elif "running" in words:
        word = "running"
    elif "queued" in words:
        word = "queued"
    elif words == {"completed"}:
        word = "completed"
    elif "cancelled" in words:
        word = "cancelled"
    elif "failed" in words:
        word = "failed"
    else:
        word = "unknown"
    return word, {i: st or "UNKNOWN" for i, st in states.items()}

def runs_summary(job):
    """KooChainRun 캠페인이면 simulation_index 의 런 상태 수 — 드라이버 잡이 끝나도 실패한 각도가 있을 수 있다."""
    try:
        with open(os.path.join(job["output_dir"], "simulation_index.json"), encoding="utf-8") as f:
            runs = json.load(f)["scenarios"][0]["runs"]
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        return None
    counts = {}
    for rec in runs.values():
        st = (rec.get("status") if isinstance(rec, dict) else None) or "unknown"
        counts[st] = counts.get(st, 0) + 1
    return counts

def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])
    job = resolve_job(args)
    if not job:
        fail("Job not found in registry.")
    out = {"ok": True, "job_id": job["id"], "tool": job["tool_name"],
           "work_dir": job["work_dir"], "output_dir": job["output_dir"]}

    slurm_ids = job.get("slurm_job_ids") or []
    # 종료 판정용 — squeue 결과가 비어도(끝났거나 조회 실패) 어떤 잡을 물었는지 남긴다.
    out["slurm_job_ids"] = [str(i) for i in slurm_ids]
    out["sphere_job_id"] = job.get("sphere_job_id")
    if job.get("sphere_job_id"):
        slurm_ids = list(slurm_ids) + [job["sphere_job_id"]]
    out["squeue"] = slurm_queue_for(slurm_ids) if slurm_ids else {}
    out["state"], out["slurm_states"] = job_state([str(i) for i in slurm_ids], out["squeue"])
    summary = runs_summary(job) if job.get("runner_config_path") else None
    if summary is not None:
        out["runs_summary"] = summary

    # KooChainRun status (only for tools that use KooChainRun)
    rc_path = job.get("runner_config_path")
    if rc_path and os.path.exists(rc_path):
        rc, so, se = run_koochainrun("status", rc_path, timeout=30)
        out["koochainrun_status"] = {"rc": rc, "stdout": so[-2000:], "stderr": se[-500:]}

    if args.get("runs"):
        # 각도별 목록이 깨져도 상태 응답은 돌려준다.
        try:
            out["runs"], note = drop_runs(job)
        except Exception as e:
            out["runs"], note = [], f"각도별 목록을 만들지 못했다 — {type(e).__name__}: {e}"
        if note:
            out["runs_note"] = note

    # §25.3.3 inspection audit with 5-min session_seen dedup guard.
    caller = os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
    tool_qn = "job_status@1.0.0"
    target_id = str(job["id"])
    if not audit.session_seen(caller, tool_qn, target_id, within_sec=300):
        audit.record_event(
            actor=caller,
            tool=tool_qn,
            action="inspect",
            summary=f"inspected job {target_id} ({job['tool_name']})",
            target_kind="job",
            target_id=target_id,
            detail={
                "tool_inspected": job["tool_name"],
                "slurm_job_ids": slurm_ids,
            },
        )

    print(json.dumps(out, ensure_ascii=False, default=str))

try: main()
except Exception as e: fail(f"{type(e).__name__}: {e}")
PY
