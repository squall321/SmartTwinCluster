# extra_scenario_overrides 잠금 키(environment 등)·후처리 SIF 경로 제한 시험 — stcx 운영 배포 요청 §2
"""environment 를 덮어쓰면 자식 잡의 solver_command 가 바뀌어 컴퓨트 노드에서 임의 명령이 돈다.
두 낙하 도구(1.1.1)는 잠금 키를 걷어 내고 응답에 적어야 하며, 써진 scenario.json 의 environment 는
서버 기본값 그대로여야 한다. 공용 빌더가 걷어 내므로 핀 고정한 이전 버전도 같이 막힌다.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.runner import run as run_tool

ROOT = Path(__file__).resolve().parent.parent
TOOLS_ROOT = ROOT / "tools"
sys.path.insert(0, str(TOOLS_ROOT / "_shared"))

import scenario_builder as sb  # noqa: E402

EVIL_ENV = {"environment": {"solver_command": "touch /tmp/x", "koomeshmodifier_path": "/tmp/evil"}}


def _run(tool, version, work_dir, overrides, **extra):
    os.environ.pop("STMC_CLUSTER_URL", None)  # dry_run 이라 backend 없이도 scenario.json 은 써진다
    (work_dir / "MinimumModel.k").write_text("*KEYWORD\n*END\n")
    cat = load_catalog(TOOLS_ROOT)
    entry = cat.resolve(f"{tool}@{version}")
    assert entry is not None
    args = {"work_dir": str(work_dir), "lstc_license_ip": "192.168.122.1", "dry_run": True,
            "extra_scenario_overrides": overrides, **extra}
    result = run_tool(entry, args)
    scenario = json.loads((work_dir / "scenario.json").read_text())
    return result, scenario


def _default_env(tool):
    if tool == "fullangle_drop_simulation":
        return sb.build_fullangle_scenario("p", "/x", "m.k", "192.168.122.1")["environment"]
    return sb.build_single_angle_scenario("p", "/x", "m.k", "192.168.122.1")["environment"]


@pytest.mark.parametrize("tool", ["fullangle_drop_simulation", "single_drop_simulation"])
def test_environment_override_is_dropped_and_reported(tmp_path, tool):
    result, scenario = _run(tool, "1.1.1", tmp_path, {**EVIL_ENV, "mode": "drop_weight_impact",
                                                      "project_name": "x", "model_file": "/etc/passwd",
                                                      "output_dir": "/tmp"})
    assert scenario["environment"] == _default_env(tool)
    assert "touch" not in json.dumps(scenario)
    assert "mode" not in scenario and "output_dir" not in scenario and "model_file" not in scenario
    out = result.parsed
    assert out["locked_overrides_dropped"] == ["environment.koomeshmodifier_path", "environment.solver_command",
                                               "mode", "model_file", "output_dir", "project_name"]
    assert "environment.solver_command" in out["locked_note"]


@pytest.mark.parametrize("tool", ["fullangle_drop_simulation", "single_drop_simulation"])
def test_timeout_knobs_pass_but_nothing_else(tmp_path, tool):
    ov = {"environment": {"timeout_per_step_seconds": 3600, "timeout_dynain_seconds": 900,
                          "timeout_koomeshmodifier_seconds": "1800", "solver_command": "id",
                          "apptainer_sif": "/data/x.sif"}}
    result, scenario = _run(tool, "1.1.1", tmp_path, ov)
    env = scenario["environment"]
    assert env["timeout_per_step_seconds"] == 3600 and env["timeout_dynain_seconds"] == 900
    base = _default_env(tool)
    assert {k: v for k, v in env.items() if not k.startswith("timeout_")} == \
        {k: v for k, v in base.items() if not k.startswith("timeout_")}
    # 문자열로 온 시간값·실행 경로 키는 버리고 적는다
    assert result.parsed["locked_overrides_dropped"] == ["environment.apptainer_sif", "environment.solver_command",
                                                         "environment.timeout_koomeshmodifier_seconds"]


def test_timeout_out_of_range_or_bool_is_dropped():
    dropped = []
    out = sb.strip_locked_overrides({"environment": {"timeout_per_step_seconds": 0,
                                                     "timeout_dynain_seconds": True}}, dropped)
    assert "environment" not in out
    assert dropped == ["environment.timeout_dynain_seconds", "environment.timeout_per_step_seconds"]


@pytest.mark.parametrize("tool", ["fullangle_drop_simulation", "single_drop_simulation"])
def test_pinned_old_version_is_also_protected(tmp_path, tool):
    # 1.1.0 스크립트는 응답에 적지는 않지만, 공용 빌더가 걷어 내므로 써진 시나리오는 안전해야 한다.
    _, scenario = _run(tool, "1.1.0", tmp_path, EVIL_ENV)
    assert scenario["environment"] == _default_env(tool)


def test_non_locked_overrides_still_merge(tmp_path):
    result, scenario = _run("fullangle_drop_simulation", "1.1.1", tmp_path,
                            {"simulation_params": {"height": 777, "dynamic_relaxation": True}})
    assert scenario["simulation_params"]["height"] == 777
    assert scenario["simulation_params"]["dynamic_relaxation"] is True
    assert result.parsed["locked_overrides_dropped"] == []
    assert result.parsed["locked_note"] is None


def test_postprocess_sif_override_outside_apptainers_is_dropped(tmp_path):
    result, scenario = _run("fullangle_drop_simulation", "1.1.1", tmp_path,
                            {"postprocess": {"sif_path": "/data/single/u/evil.sif", "sphere_memory": "32G"}})
    assert scenario["postprocess"].get("sif_path") is None
    assert scenario["postprocess"]["sphere_memory"] == "32G"  # 같은 블록의 다른 키는 살아 있다
    assert "postprocess.sif_path" in result.parsed["locked_overrides_dropped"]


def test_postprocess_sif_override_inside_apptainers_is_kept(tmp_path):
    result, scenario = _run("fullangle_drop_simulation", "1.1.1", tmp_path,
                            {"postprocess": {"sif_path": "/opt/apptainers/SmartTwinPostprocessor.sif"}})
    assert scenario["postprocess"]["sif_path"] == "/opt/apptainers/SmartTwinPostprocessor.sif"
    assert result.parsed["locked_overrides_dropped"] == []


@pytest.mark.parametrize("bad", ["/data/single/u/evil.sif", "/opt/apptainers/../../tmp/x.sif",
                                 "/opt/apptainers/sub/x.sif"])
def test_sif_path_argument_must_be_under_opt_apptainers(tmp_path, bad):
    os.environ.pop("STMC_CLUSTER_URL", None)
    (tmp_path / "MinimumModel.k").write_text("*KEYWORD\n*END\n")
    cat = load_catalog(TOOLS_ROOT)
    entry = cat.resolve("fullangle_drop_simulation")
    result = run_tool(entry, {"work_dir": str(tmp_path), "lstc_license_ip": "192.168.122.1",
                              "dry_run": True, "sif_path_postprocessor": bad})
    assert not result.ok
    assert "/opt/apptainers" in result.parsed["reason"]
    assert not (tmp_path / "scenario.json").exists()


def test_strip_helper_does_not_mutate_input():
    ov = {"environment": {"a": 1}, "simulation_params": {"height": 1}}
    dropped = []
    out = sb.strip_locked_overrides(ov, dropped)
    assert "environment" in ov and "environment" not in out and dropped == ["environment.a"]


# ── 문자열 안전 토큰 (KooChainRun 이 따옴표 없이 셸·#SBATCH 에 넣는 값) ───────────────────────

@pytest.mark.parametrize("ov,dropped_path", [
    ({"postprocess": {"section_view_axes": ["x; touch /tmp/p"]}}, "postprocess.section_view_axes"),
    ({"postprocess": {"deep_memory": "8G\nid"}}, "postprocess.deep_memory"),
    ({"postprocess": {"sphere_partition": "normal $(id)"}}, "postprocess.sphere_partition"),
    ({"postprocess": {"deep_extra_args": "--parts 1 --install-dir /x"}}, "postprocess.deep_extra_args"),
    ({"postprocess": {"deep_extra_args": ["--ua=/bin/sh"]}}, "postprocess.deep_extra_args"),
    ({"scenarios": [{"scenario_name": "a b"}]}, "scenarios[0].scenario_name"),
    ({"simulation_params": {"bad key;": 1}}, "simulation_params.bad key;"),
])
def test_unsafe_strings_are_dropped_and_reported(ov, dropped_path):
    dropped = []
    out = sb.strip_locked_overrides(ov, dropped)
    assert dropped_path in dropped, dropped
    assert "touch" not in json.dumps(out) and "$(" not in json.dumps(out) and "install-dir" not in json.dumps(out)


def test_safe_values_survive_sanitization():
    ov = {"postprocess": {"section_view_axes": ["x", "y", "z"], "deep_memory": "32G", "auto_deep": True,
                          "deep_extra_args": "--parts 100 200 --hotspot-clusters", "yield_stress_mpa": 250},
          "scenarios": [{"scenario_name": "낙하_Fib26", "tolerance": {"doe_type": "lhs", "doe_count": 10}}],
          "simulation_params": {"drop_surface": {"type": "PlanewithRoughness", "roughness_mode": "Random"}}}
    dropped = []
    out = sb.strip_locked_overrides(ov, dropped)
    assert dropped == []
    assert out["postprocess"]["deep_extra_args"] == ["--parts", "100", "200", "--hotspot-clusters"]
    assert out["scenarios"][0]["scenario_name"] == "낙하_Fib26"
    assert out["postprocess"]["section_view_axes"] == ["x", "y", "z"]


def test_list_with_one_bad_string_is_dropped_whole():
    dropped = []
    out = sb.strip_locked_overrides({"postprocess": {"section_view_fields": ["von_mises", "eps|id"]}}, dropped)
    assert "section_view_fields" not in out.get("postprocess", {})
    assert dropped == ["postprocess.section_view_fields"]


@pytest.mark.parametrize("bad", ["1.2.3.4; id", "localhost", "10.0.0.1 --env X=1"])
def test_mode_environment_rejects_non_ipv4(bad):
    with pytest.raises(ValueError):
        sb.mode_environment("drop_weight_impact", bad)
