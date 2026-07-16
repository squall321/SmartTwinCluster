#!/usr/bin/env bash
# single_drop_simulation — 수동 각도(roll/pitch/yaw) 낙하. (C): 시나리오 로컬 빌드 + 제출은 backend 경유
#   (권한/감사 + 드라이버가 sinfo 로 클러스터 인식 auto-tune).
set -euo pipefail

export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
export PYTHONPATH="$SHARED_DIR:${PYTHONPATH:-}"

python3 - <<'PY'
import json, os, sys, shutil

sys.path.insert(0, os.environ["SHARED_DIR"])
from scenario_builder import build_single_angle_scenario, write_scenario
import job_helpers
import audit


def fail(reason: str, **extra):
    print(json.dumps({"ok": False, "reason": reason, **extra}, ensure_ascii=False))
    sys.exit(1)


def main():
    args = json.loads(os.environ["STMC_ARGS_JSON"])

    work_dir = args["work_dir"]
    lstc_ip = args["lstc_license_ip"]
    model_file = args.get("model_file", "MinimumModel.k")
    model_file_path = args.get("model_file_path")
    roll = float(args.get("roll_deg", 0))
    pitch = float(args.get("pitch_deg", 0))
    yaw = float(args.get("yaw_deg", 0))
    height_mm = float(args.get("drop_height_mm", 1500))
    t_final = float(args.get("simulation_time_s", 0.005))
    ncpu = int(args.get("ncpu", 1))
    memory = args.get("memory", "2G")
    time_limit = args.get("time_limit", "01:00:00")
    project_name = args.get("project_name") or f"SingleDrop_R{int(roll)}_P{int(pitch)}_Y{int(yaw)}"
    drop_surface_type = args.get("drop_surface_type", "Plane")
    extra_overrides = args.get("extra_scenario_overrides")
    dry_run = bool(args.get("dry_run", False))

    os.makedirs(work_dir, exist_ok=True)
    model_target = os.path.join(work_dir, model_file)
    if not os.path.exists(model_target):
        if model_file_path and os.path.exists(model_file_path):
            shutil.copy(model_file_path, model_target)
        else:
            fail(f"Model file missing: {model_target} (and no valid model_file_path provided)")

    # 시나리오 빌드(이 도구의 핵심 가치 — 단일 각도 회전).
    scenario = build_single_angle_scenario(
        project_name=project_name,
        base_dir=work_dir,
        model_file=model_file,
        lstc_ip=lstc_ip,
        roll_deg=roll, pitch_deg=pitch, yaw_deg=yaw,
        height_mm=height_mm, t_final_s=t_final,
        ncpu=ncpu, memory=memory, time_limit=time_limit,
        drop_surface_type=drop_surface_type,
        extra_overrides=extra_overrides,
    )
    scenario_path = os.path.join(work_dir, "scenario.json")
    write_scenario(scenario, scenario_path)
    output_dir = os.path.join(work_dir, "output")

    # (C): 제출은 backend 경유(권한/감사). 드라이버가 병렬도 auto-tune.
    res = job_helpers.backend_submit(
        template_id="smarttwin-fullangle-drop", model_path=model_target,
        scenario_path=scenario_path, tool_name="single_drop_simulation",
        project_name=project_name, job_name=project_name, num_angles=1, dry_run=dry_run)

    if dry_run:
        print(json.dumps({"ok": res.get("ok"), "dry_run": True, "scenario_path": scenario_path,
                          "sbatch_preview": res.get("sbatch_preview"),
                          "note": "제출은 backend 경유(권한/감사) + 드라이버가 sinfo 로 병렬도 auto-tune"},
                         ensure_ascii=False))
        return

    if not res.get("ok"):
        fail(res.get("error", "backend 제출 실패"),
             **{k: res[k] for k in ("http", "response") if k in res})

    reg_id, job_id = res.get("registry_id"), res["job_id"]

    actor = os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown"
    audit.record_event(
        actor=actor, tool="single_drop_simulation@1.1.0", action="submit",
        summary=f"submitted single drop {project_name} (R{roll}/P{pitch}/Y{yaw}) via backend -> job {job_id}",
        target_kind="job", target_id=str(reg_id or job_id),
        detail={"project_name": project_name, "angle": {"roll": roll, "pitch": pitch, "yaw": yaw},
                "drop_height_mm": height_mm, "job_id": job_id, "dry_run": dry_run})

    print(json.dumps({
        "ok": True,
        "registry_id": reg_id,
        "job_id": job_id,
        "tool": "single_drop_simulation",
        "project_name": project_name,
        "angle": {"roll": roll, "pitch": pitch, "yaw": yaw},
        "work_dir": work_dir,
        "output_dir": output_dir,
        "scenario_path": scenario_path,
        "submitted_via": "backend_5010 (권한/감사) + 드라이버 클러스터 auto-tune",
        "follow_up_hint": (
            "job_status/job_stop/job_diagnose/job_postprocess/job_collect 에 registry_id 또는 "
            "job_id 사용. list_recent_jobs 로 세션 넘어서 다시 찾기."
        ),
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        fail(f"unhandled exception: {type(e).__name__}: {e}")
PY
