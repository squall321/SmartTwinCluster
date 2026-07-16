#!/usr/bin/env bash
# fullangle_drop_simulation — Fibonacci N-방향 낙하. (C): 시나리오 로컬 빌드 + 제출은 backend 경유
#   (권한/감사 + 드라이버가 sinfo+DOE 로 클러스터 인식 auto-tune).
set -euo pipefail

export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"

python3 - <<'PY'
import json, os, sys, shutil

sys.path.insert(0, os.environ["SHARED_DIR"])
from scenario_builder import build_fullangle_scenario, write_scenario
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
    num_angles = int(args.get("num_angles", 162))
    height_mm = float(args.get("drop_height_mm", 1500))
    t_final = float(args.get("simulation_time_s", 0.005))
    ncpu = int(args.get("ncpu", 2))
    memory = args.get("memory", "4G")
    time_limit = args.get("time_limit", "12:00:00")
    enable_pp = bool(args.get("enable_postprocess", True))
    auto_deep = bool(args.get("auto_deep", True))
    auto_sphere = bool(args.get("auto_sphere", True))
    auto_deep_mode = args.get("auto_deep_mode", "inline")
    yield_stress = float(args.get("yield_stress_mpa", 350))
    drop_surface_type = args.get("drop_surface_type", "Plane")
    sif_post = args.get("sif_path_postprocessor")
    extra_overrides = args.get("extra_scenario_overrides")
    project_name = args.get("project_name") or f"Fullangle_Fib{num_angles}"
    dry_run = bool(args.get("dry_run", False))

    os.makedirs(work_dir, exist_ok=True)
    model_target = os.path.join(work_dir, model_file)
    if not os.path.exists(model_target):
        if model_file_path and os.path.exists(model_file_path):
            shutil.copy(model_file_path, model_target)
        else:
            fail(f"Model file missing: {model_target}")

    # 시나리오 빌드(이 도구의 핵심 가치 — fibonacci 각도 + 후처리 구성).
    scenario = build_fullangle_scenario(
        project_name=project_name,
        base_dir=work_dir,
        model_file=model_file,
        lstc_ip=lstc_ip,
        num_directions=num_angles,
        height_mm=height_mm, t_final_s=t_final,
        ncpu=ncpu, memory=memory, time_limit=time_limit,
        drop_surface_type=drop_surface_type,
        enable_postprocess=enable_pp,
        auto_deep=auto_deep,
        auto_sphere=auto_sphere,
        auto_deep_mode=auto_deep_mode,
        yield_stress_mpa=yield_stress,
        sif_path_postprocessor=sif_post,
        extra_overrides=extra_overrides,
    )
    scenario_path = os.path.join(work_dir, "scenario.json")
    write_scenario(scenario, scenario_path)
    output_dir = os.path.join(work_dir, "output")

    # (C): 제출은 backend 경유(권한/감사). 드라이버가 sinfo+DOE 로 병렬도 auto-tune 하므로
    #      여기서 KooChainRun 을 직접 prepare/submit 하지 않는다.
    res = job_helpers.backend_submit(
        template_id="smarttwin-fullangle-drop",
        files={"model_k": model_target, "scenario_json": scenario_path},
        tool_name="fullangle_drop_simulation",
        project_name=project_name, job_name=project_name,
        num_angles=num_angles, dry_run=dry_run)

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
        actor=actor, tool="fullangle_drop_simulation@1.1.0", action="submit",
        summary=f"submitted fullangle {project_name} (Fib{num_angles}) via backend -> job {job_id}",
        target_kind="job", target_id=str(reg_id or job_id),
        detail={"project_name": project_name, "num_angles": num_angles,
                "job_id": job_id, "drop_height_mm": height_mm, "dry_run": dry_run})

    print(json.dumps({
        "ok": True,
        "registry_id": reg_id,
        "job_id": job_id,
        "tool": "fullangle_drop_simulation",
        "project_name": project_name,
        "num_angles": num_angles,
        "work_dir": work_dir,
        "output_dir": output_dir,
        "scenario_path": scenario_path,
        "submitted_via": "backend_5010 (권한/감사) + 드라이버 클러스터 auto-tune",
        "sphere_report_path": os.path.join(output_dir, "sphere_report.html"),
        "follow_up_hint": (
            "job_status/job_stop/job_diagnose/job_postprocess/job_collect 에 registry_id 또는 "
            "job_id 사용. sphere_report.html 이 최종 aggregate 산출."
        ),
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        fail(f"unhandled exception: {type(e).__name__}: {e}")
PY
