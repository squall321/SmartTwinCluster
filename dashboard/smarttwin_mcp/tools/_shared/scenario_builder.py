#!/usr/bin/env python3
"""KooChainRun scenario.json builder — used by drop simulation MCP tools.

Builds a complete scenario.json from minimal high-level args + sensible defaults.
Defaults match Examples/portable_bundle/ verified scenarios.
"""
from __future__ import annotations

import json
import os
import re
import sys


DEFAULT_LSDYNA_PATH = "/opt/ls-dyna/lsdyna_R16.1.1"
DEFAULT_KOOMESHMODIFIER_PATH = "/opt/SmartTwinPreprocessor/bin/KooMeshModifier"
DEFAULT_KOOCHAINRUN_PATH = "/data/SmartTwinPreprocessor/bin/KooChainRun"
DEFAULT_APPTAINER_SIF_PREP = "/opt/apptainers/SmartTwinPreprocessor.sif"
DEFAULT_APPTAINER_SIF_DYNA = "/opt/apptainers/LSDynaBasic_aocc420_ompi4.0.5_mpp_s.sif"
DEFAULT_APPTAINER_SIF_POST = "/opt/apptainers/SmartTwinPostprocessor.sif"


# single-precision(I4R4) LS-DYNA의 memory= 파라미터는 32비트 정수(word 단위)라
# 2147m(=2147*10^6 < 2^31-1)을 넘기면 "Error 10904 (KEY+904)"로 즉사한다.
LSDYNA_SP_MAX_MEMORY_M = 2147


def _base_environment(lstc_ip: str, ncpu: int = 1, memory: str = "2G",
                      time_limit: str = "01:00:00") -> dict:
    lsdyna_memory_m = (
        min(int(memory.rstrip("Gg")) * 1000, LSDYNA_SP_MAX_MEMORY_M)
        if memory.endswith(("G", "g")) else 2000
    )
    return {
        "koomeshmodifier_path": DEFAULT_KOOMESHMODIFIER_PATH,
        "lsdyna_path": DEFAULT_LSDYNA_PATH,
        "mpi_path": "mpirun",
        "memory": memory,
        "lsdyna_memory": f"{lsdyna_memory_m}m",
        "apptainer_sif": DEFAULT_APPTAINER_SIF_PREP,
        "apptainer_bind": "/data:/data",
        "apptainer_env": {},
        "lsdyna_apptainer_sif": DEFAULT_APPTAINER_SIF_DYNA,
        "lsdyna_apptainer_bind": "/data:/data,/shared:/shared",
        "lsdyna_apptainer_env": {
            "LSTC_FILE": "/opt/ls-dyna_license/LSTC_FILE",
            "LSTC_LICENSE_SERVER": lstc_ip,
            "FI_PROVIDER": "tcp",
            "I_MPI_FABRICS": "ofi",
            "LD_LIBRARY_PATH": "/opt/openmpi/lib",
        },
        "apptainer_tmpdir": "/data/tmp",
        "nodes_per_job": 1,
        "mpi_launcher": "mpirun",
        "mpi_enabled": True,
        "ncpu": ncpu,
        "koochainrun_path": DEFAULT_KOOCHAINRUN_PATH,
        "time_limit": time_limit,
    }


def _base_simulation_params(
    height_mm: float = 1500,
    t_final_s: float = 0.005,
    dt_s: float = 1e-06,
    drop_surface_type: str = "Plane",
) -> dict:
    """drop_surface_type: Plane / PlaneGraded / RigidWall / PlanewithRoughness."""
    if drop_surface_type == "RigidWall":
        surface = {"type": "RigidWall"}
    else:
        surface = {
            "type": drop_surface_type,
            "size": [300, 300, 20],
            "mesh": [30, 30, 2],
            "deformable_to_rigid": False,
        }
    return {
        "height": height_mm,
        "tFinal": t_final_s,
        "dt": dt_s,
        "density": 7850,
        "youngs_modulus": 200_000_000_000,
        "poisson_ratio": 0.3,
        "drop_surface": surface,
    }


# extra_scenario_overrides 로 못 바꾸는 최상위 키 — 구 mcp_slurm 의 _LOCKED_SCENARIO_KEYS 와 같은 집합.
# environment 는 자식 잡이 실행하는 solver_command·koomeshmodifier_path·lsdyna_path·apptainer_sif 를
# 담고 있어 덮어쓰기를 허용하면 컴퓨트 노드에서 임의 명령이 실행된다(RCE). mode·model_file·
# output_dir·project_name 은 디스패치·경로를 정하는 키라 사용자 입력이 끼면 안 된다.
LOCKED_SCENARIO_KEYS = frozenset({"environment", "mode", "model_file", "output_dir", "project_name"})

# environment 안에서 덮어써도 되는 키 — 시간 상한(초, 1~30일 정수)만. KooChainRun 이 environment 에서 읽는다.
SAFE_ENVIRONMENT_KEYS = frozenset({"timeout_per_step_seconds", "timeout_koomeshmodifier_seconds",
                                   "timeout_dynain_seconds"})

# 후처리 SIF(postprocess.sif_path)도 apptainer exec 로 실행되는 이미지라 같은 종류의 위험이다.
# 관리자가 배포하는 계산노드 로컬 이미지(/opt/apptainers/*.sif)만 허용한다.
_ALLOWED_SIF_RE = re.compile(r"^/opt/apptainers/[A-Za-z0-9._-]+\.sif$")


# 시나리오 값은 KooChainRun 이 셸 스크립트·#SBATCH 줄에 따옴표 없이 넣는 곳이 있다(예: section_view_axes 를
# 공백으로 이어 deep_report.sh 에, deep_memory 를 #SBATCH --mem= 에). 그래서 사용자가 준 문자열은 전부
# 공백·줄바꿈·셸 메타문자 없는 토큰이어야 한다. *_extra_args 는 생성기가 shlex 로 감싸므로 공백을 허용하되
# 줄바꿈과 실행 파일 위치를 바꾸는 옵션은 막는다.
_SAFE_STR = re.compile(r"^[\w.,:*?/@+%=-]{0,256}$")
_SAFE_KEY = re.compile(r"^[\w.-]{1,64}$")
_FORBIDDEN_TOOL_FLAGS = ("--install-dir", "--ua")
_DROP = object()


def _safe_extra_args(v):
    import shlex
    try:
        toks = shlex.split(v) if isinstance(v, str) else v
    except ValueError:
        return _DROP
    if not isinstance(toks, list) or not all(isinstance(t, (str, int, float)) and not isinstance(t, bool) for t in toks):
        return _DROP
    toks = [str(t) for t in toks]
    if any("\n" in t or "\r" in t or t.split("=", 1)[0] in _FORBIDDEN_TOOL_FLAGS for t in toks):
        return _DROP
    return toks


def sanitize_strings(obj, dropped: list | None, path: str = ""):
    """사용자 덮어쓰기 안 문자열을 안전 토큰으로 제한한다. 안 맞는 값은 빼고 경로를 `dropped` 에 적는다.
    문자열 원소가 하나라도 안 맞는 목록은 통째로 뺀다(일부만 빼면 뜻이 조용히 바뀐다)."""
    def note(p):
        if dropped is not None:
            dropped.append(p)
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            p = f"{path}.{k}" if path else str(k)
            if not isinstance(k, str) or not _SAFE_KEY.fullmatch(k):
                note(p)
                continue
            sv = _safe_extra_args(v) if k.endswith("_extra_args") else sanitize_strings(v, dropped, p)
            if sv is _DROP:
                if k.endswith("_extra_args"):
                    note(p)
                continue
            out[k] = sv
        return out
    if isinstance(obj, list):
        items = [sanitize_strings(v, dropped, f"{path}[{i}]") for i, v in enumerate(obj)]
        if any(x is _DROP for x in items):
            if dropped is not None:
                dropped[:] = [d for d in dropped if not d.startswith(path + "[")]
            note(path)
            return _DROP
        return items
    if isinstance(obj, str):
        if _SAFE_STR.fullmatch(obj):
            return obj
        note(path)
        return _DROP
    return obj


def is_allowed_sif(path: str | None) -> bool:
    return bool(path) and bool(_ALLOWED_SIF_RE.fullmatch(str(path))) and ".." not in str(path)


def strip_locked_overrides(overrides: dict | None, dropped: list | None = None) -> dict | None:
    """잠금 키를 걷어 낸 사본을 돌려준다. 걷어 낸 키 이름은 `dropped` 에 덧붙인다(조용히 버리지 않기).

    environment 는 SAFE_ENVIRONMENT_KEYS(시간 상한 정수)만 남기고 나머지 키를 'environment.<키>' 로 기록한다.

    postprocess.sif_path 가 허용 범위(/opt/apptainers/*.sif) 밖이면 그것도 걷어 내고
    'postprocess.sif_path' 로 기록한다.
    """
    if not overrides:
        return overrides
    out = {k: v for k, v in overrides.items() if k not in LOCKED_SCENARIO_KEYS}
    notes = [k for k in overrides if k in LOCKED_SCENARIO_KEYS and k != "environment"]
    env = overrides.get("environment")
    if isinstance(env, dict):
        # 시간 상한 3종은 실행에 관여하지 않는 정수라 통과시킨다(발산 시나리오의 실제 안전망).
        safe = {k: v for k, v in env.items() if k in SAFE_ENVIRONMENT_KEYS and type(v) is int
                and 1 <= v <= 30 * 86400}
        if safe:
            out["environment"] = safe
        notes += [f"environment.{k}" for k in env if k not in safe]
    elif "environment" in overrides:
        notes.append("environment")
    pp = out.get("postprocess")
    if isinstance(pp, dict) and "sif_path" in pp and not is_allowed_sif(pp.get("sif_path")):
        out["postprocess"] = {k: v for k, v in pp.items() if k != "sif_path"}
        notes.append("postprocess.sif_path")
    env_safe = out.pop("environment", None)
    out = sanitize_strings(out, notes)
    if env_safe is not None:
        out["environment"] = env_safe
    if dropped is not None:
        dropped.extend(sorted(notes))
    return out


def deep_merge(base: dict, overrides: dict | None) -> dict:
    """Recursively merge `overrides` into `base`. Lists in overrides REPLACE base lists.

    Used to apply user-supplied `extra_scenario_overrides` on top of the Tier 1 scenario.
    """
    if not overrides:
        return base
    for k, v in overrides.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            deep_merge(base[k], v)
        else:
            base[k] = v
    return base


def build_single_angle_scenario(
    project_name: str,
    base_dir: str,
    model_file: str,
    lstc_ip: str,
    roll_deg: float = 0.0,
    pitch_deg: float = 0.0,
    yaw_deg: float = 0.0,
    height_mm: float = 1500,
    t_final_s: float = 0.005,
    ncpu: int = 1,
    memory: str = "2G",
    time_limit: str = "01:00:00",
    drop_surface_type: str = "Plane",
    extra_overrides: dict | None = None,
    locked_dropped: list | None = None,
) -> dict:
    """1방향 지정각도 낙하 시나리오.

    KooChainRun에 'manual' source_type이 없으므로 pitching_sweep을
    pitch_min=pitch_max로 1방향만 만드는 트릭 사용. roll/yaw는 fixed로 지정.

    extra_overrides: Tier 2 옵션 (scenarios[0].batch_koomeshmodifier, tolerance, 등) 통과용.
    """
    scenario = {
        "project_name": project_name,
        "base_dir": base_dir,
        "environment": _base_environment(lstc_ip, ncpu, memory, time_limit),
        "simulation_params": _base_simulation_params(height_mm, t_final_s,
                                                     drop_surface_type=drop_surface_type),
        "scenarios": [
            {
                "scenario_name": f"Single_R{roll_deg}_P{pitch_deg}_Y{yaw_deg}",
                "template": model_file,
                "angle_source": {
                    "source_type": "pitching_sweep",
                    "pitching_sweep": {
                        "pitch_min": pitch_deg,
                        "pitch_max": pitch_deg,
                        "pitch_step": 1,
                        "roll_fixed": roll_deg,
                        "yaw_fixed": yaw_deg,
                    },
                },
                "cumulative": {
                    "num_steps": 1,
                    "mode_sequence": ["DROP"],
                    "base_angle_index": 0,
                    "angle_mixing": {"strategy": "same_angle"},
                },
            }
        ],
    }
    return deep_merge(scenario, strip_locked_overrides(extra_overrides, locked_dropped))


def build_fullangle_scenario(
    project_name: str,
    base_dir: str,
    model_file: str,
    lstc_ip: str,
    num_directions: int = 162,
    height_mm: float = 1500,
    t_final_s: float = 0.005,
    ncpu: int = 2,
    memory: str = "4G",
    time_limit: str = "12:00:00",
    drop_surface_type: str = "Plane",
    enable_postprocess: bool = True,
    auto_deep: bool = True,
    auto_sphere: bool = True,
    auto_deep_mode: str = "inline",
    yield_stress_mpa: float = 350,
    sif_path_postprocessor: str | None = None,
    extra_overrides: dict | None = None,
    locked_dropped: list | None = None,
) -> dict:
    """Fibonacci 전각도 낙하 + 자동 후처리.

    extra_overrides: Tier 2 옵션 통과용 (예: tolerance, batch_koomeshmodifier, custom timeouts).
    """
    scenario = {
        "project_name": project_name,
        "base_dir": base_dir,
        "environment": _base_environment(lstc_ip, ncpu, memory, time_limit),
        "simulation_params": _base_simulation_params(height_mm, t_final_s,
                                                     drop_surface_type=drop_surface_type),
        "scenarios": [
            {
                "scenario_name": f"Fib{num_directions}",
                "template": model_file,
                "angle_source": {
                    "source_type": "fibonacci_lattice",
                    "fibonacci_lattice": {"num_directions": num_directions},
                },
                "cumulative": {
                    "num_steps": 1,
                    "mode_sequence": ["DROP"],
                    "base_angle_index": 0,
                    "angle_mixing": {"strategy": "same_angle"},
                },
            }
        ],
    }

    if enable_postprocess:
        pp = {
            "enabled": True,
            "auto_deep": auto_deep,
            "auto_sphere": auto_sphere,
            "yield_stress_mpa": yield_stress_mpa,
            "section_view_axes": ["z"],
            "section_view_fields": ["von_mises"],
            "section_view_mode": "section",
            "ua_threads": 4,
            "sv_threads": 4,
            "deep_timeout_seconds": 3600,
            "sphere_time_limit": "04:00:00",
        }
        if auto_deep_mode == "separate_job":
            pp["auto_deep_mode"] = "separate_job"
        if sif_path_postprocessor:
            if not is_allowed_sif(sif_path_postprocessor):
                raise ValueError(
                    f"sif_path_postprocessor 는 /opt/apptainers/*.sif 만 허용된다: {sif_path_postprocessor}")
            pp["sif_path"] = sif_path_postprocessor
        scenario["postprocess"] = pp

    return deep_merge(scenario, strip_locked_overrides(extra_overrides, locked_dropped))


def write_scenario(scenario: dict, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(scenario, f, indent=2)


if __name__ == "__main__":
    # CLI for testing
    print("scenario_builder.py — import as module")
    sys.exit(0)


# ── 범용 시나리오(scenario_* 도구) — environment 는 항상 서버가 만든다 ─────────────────────────

LSDYNA_SIFS = {
    "single": "/opt/apptainers/LSDynaBasic_aocc420_ompi4.0.5_mpp_s.sif",
    "double": "/opt/apptainers/LSDynaBasic_aocc420_ompi4.0.5_mpp_d.sif",   # THERM ICPower 는 배정밀 필수
}
WORKFLOW_MODES = ("part_validation", "drop_weight_impact")


def mode_environment(workflow: str | None, lstc_ip: str, *, ncpu: int = 2, memory: str = "4G",
                     time_limit: str = "12:00:00", precision: str = "single",
                     partition: str | None = None) -> dict:
    """모드별 검증된 environment. 사용자 입력은 숫자·고정 목록 선택만 들어온다(경로·명령은 여기서 고정)."""
    # lstc_ip 는 DWI 명령 문자열에 그대로 들어가므로 IPv4 가 아니면 거절한다.
    if not re.fullmatch(r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}", str(lstc_ip)):
        raise ValueError(f"lstc_license_ip 는 IPv4 여야 한다: {lstc_ip!r}")
    if not re.fullmatch(r"[0-9]+[GM]", str(memory)) or not re.fullmatch(r"[0-9]{1,3}:[0-5][0-9]:[0-5][0-9]", str(time_limit)):
        raise ValueError("memory(예: 4G)·time_limit(HH:MM:SS) 형식이 아니다")
    if partition is not None and not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", str(partition)):
        raise ValueError(f"partition 이름 형식이 아니다: {partition!r}")
    ncpu = int(ncpu)
    sif = LSDYNA_SIFS[precision]
    if workflow == "drop_weight_impact":
        # smarttwin-partial-impact 템플릿 기본 블록과 같은 명령 문자열(DWI 워크플로우가 그대로 실행한다)
        env = {
            "koomeshmodifier_path": ("apptainer exec --bind /data:/data /opt/apptainers/SmartTwinPreprocessor.sif "
                                     "/opt/SmartTwinPreprocessor/bin/KooMeshModifier"),
            "sif_path": "",
            "solver_command": (f"apptainer exec --bind /data:/data --env LSTC_FILE=/opt/ls-dyna_license/LSTC_FILE "
                               f"--env LSTC_LICENSE_SERVER={lstc_ip} --env FI_PROVIDER=tcp --env I_MPI_FABRICS=ofi "
                               f"--env LD_LIBRARY_PATH=/opt/openmpi/lib /data/apptainers/{sif.rsplit('/', 1)[1]} "
                               f"/opt/openmpi/bin/mpirun -np {int(ncpu)} /opt/ls-dyna/lsdyna"),
            **{k: v for k, v in _base_environment(lstc_ip, ncpu, memory, time_limit).items()
               if k not in ("koomeshmodifier_path",)},
        }
        env["lsdyna_apptainer_sif"] = sif
    elif workflow == "part_validation":
        env = {"koomeshmodifier_path": "/data/SmartTwinPreprocessor/bin/KooMeshModifier", "sif_path": sif,
               "solver_command": "ls-dyna", "ncpu": int(ncpu), "memory": memory}
    else:
        env = _base_environment(lstc_ip, ncpu, memory, time_limit)
        env["lsdyna_apptainer_sif"] = sif
        if precision == "double" and memory.endswith(("G", "g")):
            env["lsdyna_memory"] = f"{int(memory.rstrip('Gg')) * 1000}m"   # 배정밀은 32비트 상한이 없다
    if partition:
        env["partition"] = partition
    return env


def build_mode_scenario(skeleton: dict, overrides: dict | None, *, workflow: str | None,
                        environment: dict, model_name: str, locked_dropped: list | None = None) -> dict:
    """카탈로그 사례(skeleton) 위에 사용자 덮어쓰기(잠금 키 제외)를 얹고, environment·경로 키는 서버 값으로 고정."""
    import copy
    sc = copy.deepcopy(skeleton)
    sc.pop("environment", None)
    sc = deep_merge(sc, strip_locked_overrides(overrides, locked_dropped))
    sc["environment"] = {**environment, **(sc.get("environment") or {})}   # 남은 것은 시간 상한뿐
    sc["project_name"] = "stmc_scenario"   # 템플릿이 잡 이름으로 바꾼다
    if workflow:
        sc["mode"] = workflow
        sc["model_file"] = model_name
        sc["output_dir"] = "output"
        sc.pop("base_dir", None)
    else:
        sc.pop("mode", None)
        sc["base_dir"] = "%RESULT_DIR%"
        for s in sc.get("scenarios") or []:
            s["template"] = model_name
    return sc
