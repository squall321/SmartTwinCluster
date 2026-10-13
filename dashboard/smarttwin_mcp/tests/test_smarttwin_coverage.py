# SmartTwin 생성 도구 시험 — 정본 대비 커버리지·벤더링 일치·패밀리별 렌더링·보안 거절·전 도구 dry_run
"""정본(pyKooCAE help 카탈로그, KooRemapper core, 후처리 --help)이 이 머신에 없으면 커버리지 비교는 skip 하고
생성물 자체(stmc_specs.json)만 검사한다 — 운영 머신에는 소스가 없다.

dry_run 은 PAT 없이 돈다(경로 검사 없음, 파일시스템을 보지 않음). PAT 가 있을 때의 경로 검사와 실제 제출은
e2e(scripts/e2e_smarttwin_tools.py)에서 본다.
"""
from __future__ import annotations

import hashlib
import importlib
import json
import os
import sys
from pathlib import Path

import pytest

from smarttwin_mcp.catalog import load_catalog
from smarttwin_mcp.runner import run as run_tool

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
SHARED = TOOLS / "_shared"
SPECS = json.loads((SHARED / "stmc_specs.json").read_text(encoding="utf-8"))
PYKOOCAE = Path(os.environ.get("PYKOOCAE_ROOT", "/home/koopark/serviceApptainers/appt313/opt/pyKooCAE"))
KOOREMAPPER_CORE = Path("/home/koopark/claude/KooRemapper/platform/core/kooremapper_core")

needs_pykoocae = pytest.mark.skipif(not (PYKOOCAE / "occProject/Generators/KooCLIHelp").is_dir(),
                                    reason="pyKooCAE 소스 없음(운영 머신)")


@pytest.fixture(autouse=True)
def _no_backend(monkeypatch):
    monkeypatch.delenv("STMC_CLUSTER_URL", raising=False)
    monkeypatch.delenv("STMC_CLUSTER_TOKEN", raising=False)


def _catalog(module):
    sys.path.insert(0, str(PYKOOCAE / "occProject" / "Generators"))
    try:
        m = importlib.import_module(module)
        return next(v for v in vars(m).values() if type(v).__name__ == "Catalog")
    finally:
        sys.path.pop(0)


def _run(tool, args):
    cat = load_catalog(TOOLS)
    entry = cat.resolve(tool)
    assert entry is not None, tool
    return run_tool(entry, args)


# ── 커버리지 ──────────────────────────────────────────────────────────────────────

@needs_pykoocae
def test_every_kmm_mode_has_a_tool():
    modes = {m.name for m in _catalog("KooCLIHelp.kmm_catalog").modes}
    tools = {s["mode"] for s in SPECS["tools"].values() if s["family"] == "kmm"}
    assert modes == tools and len(modes) >= 32


@needs_pykoocae
def test_every_kam_mode_has_a_tool():
    modes = {m.name for m in _catalog("KooCLIHelp.kam_catalog").modes}
    tools = {s["mode"] for s in SPECS["tools"].values() if s["family"] == "kam"}
    assert modes == tools and len(modes) >= 6


def test_every_kooremapper_op_has_a_tool():
    sys.path.insert(0, str(SHARED))
    from kooremapper_core import catalog
    ops = {o for o in catalog.operation_names() if catalog.get_operation(o).get("invocation") != "external"}
    tools = {s["op"] for s in SPECS["tools"].values() if s["family"] == "remap"}
    assert ops == tools and len(ops) >= 59


def test_every_postprocessor_binary_has_a_tool():
    expected = {"post_analyze", "unified_analyzer", "koo_deep_report", "koo_sphere_report", "koo_impact_report",
                "koo_federate_report", "koo_custom_report", "koo_scatter_report", "koo_dyna_diag", "make_stl"}
    tools = {s["binary"] for s in SPECS["tools"].values() if s["family"] == "post"}
    assert tools == expected


def test_specs_tools_all_exist_in_catalog():
    cat = load_catalog(TOOLS)
    missing = [t for t in SPECS["tools"] if cat.resolve(t) is None]
    assert not missing, missing


@pytest.mark.skipif(not KOOREMAPPER_CORE.is_dir(), reason="KooRemapper 리포 없음")
def test_vendored_kooremapper_core_matches_source():
    for name in ("__init__.py", "catalog.py", "argbuild.py", "catalog_data.json"):
        a = hashlib.sha256((SHARED / "kooremapper_core" / name).read_bytes()).hexdigest()
        b = hashlib.sha256((KOOREMAPPER_CORE / name).read_bytes()).hexdigest()
        assert a == b, f"{name} 가 원본과 다르다 — VENDORED.md 대로 다시 복사하고 생성기를 돌릴 것"


# ── 패밀리별 렌더링 (dry_run, PAT 없음) ─────────────────────────────────────────────────

def test_kmm_option_file_rendering():
    r = _run("kmm_transform", {"model_path": "/data/single/u/case/model.k", "dry_run": True,
                               "options": {"Translation": [0, 0, 10.5], "Mirror": "XY"},
                               "lines": ["Rotation,0.0,0.0,90.0"]})
    assert r.ok, r.stdout + r.stderr
    out = r.parsed
    assert out["request"]["binary"] == "KooMeshModifier" and out["request"]["family"] == "kmm"
    assert out["request"]["argv"] == ["@@WORK@@/stmc_options.txt", "@@WORK@@"]
    assert out["texts"]["stmc_options.txt"] == (
        "*Inputfile\nmodel.k\n*Mode\nTRANSFORM,1\n**Transform,1\nTranslation,0,0,10.5\nMirror,XY\n"
        "Rotation,0.0,0.0,90.0\n**EndTransform\n*End\n")
    assert {"name": "model.k", "source": "/data/single/u/case/model.k"} in out["inputs"]


@pytest.mark.parametrize("bad", ["", "**EndTransform", "*Mode", "a\nb", "*End"])
def test_kmm_rejects_structure_breaking_lines(bad):
    r = _run("kmm_transform", {"model_path": "/data/single/u/model.k", "dry_run": True, "lines": [bad]})
    assert not r.ok


def test_kmm_chain_uses_each_mode_block():
    r = _run("kmm_chain", {"model_path": "/data/single/u/m.k", "dry_run": True,
                           "modes": [{"mode": "ELASTIC_TO_RIGID", "lines": ["*PIDExcept,5"]},
                                     {"mode": "TRANSFORM", "options": {"Translation": [1, 2, 3]}}]})
    assert r.ok, r.stdout
    text = r.parsed["texts"]["stmc_options.txt"]
    assert "ELASTIC_TO_RIGID,1\nTRANSFORM,2\n" in text
    assert "**ElastictoRigid,1\n*PIDExcept,5\n**EndElastictoRigid\n**Transform,2\nTranslation,1,2,3\n**EndTransform" in text


def test_kam_text_input_gets_end_and_argv():
    r = _run("kam_pkg", {"input_text": "*Layer,Die\nLength,6.0,5.0\nThickness,0.2", "dry_run": True})
    assert r.ok, r.stdout
    assert r.parsed["request"]["argv"] == ["PKG", "pkg_input.txt", "@@WORK@@", "False"]
    assert r.parsed["texts"]["pkg_input.txt"].rstrip().endswith("*End")


def test_kam_airmesh_json_paths_become_bundle_names():
    r = _run("kam_airmesh", {"config": {"step_file": "/data/single/u/case/part.step", "margin": 2.0},
                             "dry_run": True})
    assert r.ok, r.stdout
    body = json.loads(r.parsed["texts"]["airmesh.json"])
    assert body["step_file"] == "part.step"
    assert any(i["name"] == "part.step" for i in r.parsed["inputs"])


def test_remap_positional_and_yaml_ops():
    r = _run("remap_info", {"kfile": "/data/single/u/case/model.k", "dry_run": True})
    if not r.ok:  # info 의 인자 이름은 core 정본을 따른다 — 스키마에서 첫 file 인자를 찾아 다시
        schema = json.loads((TOOLS / "remap_info/1.0.0/args.schema.json").read_text())
        fname = next(k for k, v in schema["properties"].items() if v.get("x-kind") == "session_file")
        r = _run("remap_info", {fname: "/data/single/u/case/model.k", "dry_run": True})
    assert r.ok, r.stdout
    assert r.parsed["request"]["argv"][:2] == ["info", "model.k"]
    r = _run("remap_matdb", {"model": "/data/single/u/case/model.k", "output": "mapped.k",
                             "materials": [{"match": "*"}], "dry_run": True})
    assert r.ok, r.stdout
    assert r.parsed["request"]["argv"] == ["matdb", "@@WORK@@/config.yaml"]
    cfg = r.parsed["texts"]["config.yaml"]
    assert "model: model.k" in cfg and "/opt/kooremapper/materials/material_db.json" in cfg


def test_post_argv_target_options_and_forced():
    r = _run("post_deep_report", {"target": "/data/single/u/run1", "dry_run": True,
                                  "options": {"yield_stress": 250, "no_render": True,
                                              "section_view_axes": ["x", "z"]}})
    assert r.ok, r.stdout
    req = r.parsed["request"]
    assert req["binary"] == "koo_deep_report" and req["cwd"] == "existing"
    assert req["existing_dir"] == "/data/single/u/run1"
    assert req["argv"] == ["/data/single/u/run1", "--yield-stress", "250", "--no-render",
                           "--section-view-axes", "x", "z"]
    r = _run("post_dyna_diag", {"target": "/data/single/u/run1", "dry_run": True})
    assert r.ok and r.parsed["request"]["argv"][-4:] == ["--index", "@@RESULT@@/koodyna_index.json",
                                                         "--output-dir", "@@RESULT@@/koodyna_reports"]


def test_post_requires_one_of():
    r = _run("post_sphere_report", {"dry_run": True})
    assert not r.ok and "target" in r.parsed["reason"]
    r = _run("post_sphere_report", {"dry_run": True, "options": {"from_json": "/data/single/u/r/report.json"}})
    assert r.ok, r.stdout


@pytest.mark.parametrize("tool,args", [
    ("post_deep_report", {"target": "/data/single/u/r", "argv_extra": ["--install-dir", "/tmp"]}),
    ("post_analyze", {"target": "/data/single/u/r", "options": {"deep_opts": "--parts 1 --install-dir /x"}}),
    ("post_unified_analyzer", {"config": {"render": {"lsprepost_path": "/bin/sh"}}}),
    ("post_custom_report", {"target": "/data/single/u/r", "argv_extra": ["--ua=/bin/sh"]}),
])
def test_post_rejects_executable_selection(tool, args):
    r = _run(tool, {**args, "dry_run": True})
    assert not r.ok, r.stdout


def test_post_install_dir_is_not_even_in_schema():
    schema = json.loads((TOOLS / "post_deep_report/1.0.0/args.schema.json").read_text())
    assert "install_dir" not in schema["properties"]["options"]["properties"]
    schema = json.loads((TOOLS / "post_custom_report/1.0.0/args.schema.json").read_text())
    assert "ua" not in schema["properties"]["options"]["properties"]


def test_non_dry_run_without_pat_fails_closed():
    r = _run("kmm_transform", {"model_path": "/data/single/u/model.k"})
    assert not r.ok and "fail-closed" in r.parsed["reason"]


# ── 전 생성 도구: 자기 예제(dry_run)가 실제로 렌더링되는가 ───────────────────────────────────

@pytest.mark.parametrize("tool", sorted(SPECS["tools"]))
def test_every_generated_tool_renders_its_dry_run_example(tool):
    cat = load_catalog(TOOLS)
    entry = cat.resolve(tool)
    ex = next(e for e in entry.meta.examples if e.args.get("dry_run") is True)
    r = run_tool(entry, ex.args)
    assert r.ok, (tool, r.stdout[-800:], r.stderr[-400:])
    assert r.parsed["dry_run"] is True
    if SPECS["tools"][tool]["family"] == "scenario":
        assert r.parsed["template_id"] in ("smarttwin-scenario", "smarttwin-partial-impact")
        assert r.parsed["scenario"]["environment"]          # 서버가 만든 environment
    else:
        assert r.parsed["request"]["schema"] == "stmc-tool/1"


# ── KooChainRun 시나리오 도구 ────────────────────────────────────────────────────────────

import subprocess  # noqa: E402

import yaml  # noqa: E402

SCENARIO_TEMPLATE = (ROOT.parent / "templates" / "official" / "simulation" / "smarttwin-scenario.yaml")


def _scenario_validator_source() -> str:
    t = yaml.safe_load(SCENARIO_TEMPLATE.read_text(encoding="utf-8"))
    return t["script"]["pre_exec"].split("<<'STMC_SCENARIO'\n", 1)[1].split("\nSTMC_SCENARIO\n", 1)[0]


def _template_validate(tmp_path, scenario: dict):
    work = tmp_path / "res"
    work.mkdir(exist_ok=True)
    (work / "scenario.json").write_text(json.dumps(scenario))
    env = {**os.environ, "RESULT_DIR": str(work), "MODEL_FILE": "model.k",
           "SLURM_JOB_NAME": "stmc_t", "SLURM_JOB_ID": "77"}
    env.pop("FILE_AUX_TGZ", None)
    proc = subprocess.run([sys.executable, "-c", _scenario_validator_source()], env=env, cwd=str(work),
                          capture_output=True, text=True)
    return proc, json.loads((work / "scenario.json").read_text())


@needs_pykoocae
def test_every_kcr_scenario_mode_has_a_tool():
    cat = _catalog_kcr()
    modes = {m.name for m in cat.modes if not m.category.startswith("명령")}
    tools = {s["mode"] for s in SPECS["tools"].values() if s["family"] == "scenario" and not s.get("generic")}
    assert modes == tools


def _catalog_kcr():
    sys.path.insert(0, str(PYKOOCAE))
    try:
        m = importlib.import_module("Runner.cli_help_kcr")
        return next(v for v in vars(m).values() if type(v).__name__ == "Catalog")
    finally:
        sys.path.pop(0)


@pytest.mark.parametrize("tool", ["scenario_drop", "scenario_impact", "scenario_vibration", "scenario_therm",
                                  "scenario_remap", "scenario_part_validation"])
def test_mcp_built_scenario_passes_template_validation(tmp_path, tool):
    r = _run(tool, {"model_path": "/data/single/u/case/model.k", "lstc_license_ip": "192.168.122.1", "dry_run": True})
    assert r.ok, r.stdout
    out = r.parsed
    assert out["template_id"] == "smarttwin-scenario"
    proc, normalized = _template_validate(tmp_path, out["scenario"])
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert normalized["project_name"] == "stmc_t_77"
    if tool == "scenario_part_validation":
        assert normalized["mode"] == "part_validation" and normalized["model_file"] == "model.k"
    else:
        assert normalized["base_dir"] == str((tmp_path / "res").resolve())
        assert all(s["template"] == "model.k" for s in normalized["scenarios"])


def test_dwi_routes_to_partial_impact_template():
    r = _run("scenario_drop_weight_impact", {"model_path": "/data/single/u/m.k", "lstc_license_ip": "10.1.2.3",
                                             "dry_run": True})
    assert r.ok, r.stdout
    assert r.parsed["template_id"] == "smarttwin-partial-impact"
    sc = r.parsed["scenario"]
    assert sc["mode"] == "drop_weight_impact" and sc["model_file"] == "m.k"
    assert "LSTC_LICENSE_SERVER=10.1.2.3" in sc["environment"]["solver_command"]


def test_scenario_tool_locks_environment_and_unsafe_strings(tmp_path):
    r = _run("scenario_drop", {"model_path": "/data/single/u/m.k", "lstc_license_ip": "192.168.122.1", "dry_run": True,
                               "scenario": {"environment": {"solver_command": "id", "timeout_per_step_seconds": 900},
                                            "postprocess": {"section_view_axes": ["x;id"]},
                                            "simulation_params": {"height": 777}}})
    assert r.ok, r.stdout
    sc = r.parsed["scenario"]
    assert sc["simulation_params"]["height"] == 777
    assert sc["environment"]["timeout_per_step_seconds"] == 900 and "solver_command" not in sc["environment"]
    assert "environment.solver_command" in r.parsed["locked_overrides_dropped"]
    assert "postprocess.section_view_axes" in r.parsed["locked_overrides_dropped"]
    proc, _ = _template_validate(tmp_path, sc)
    assert proc.returncode == 0, proc.stdout


@pytest.mark.parametrize("bad_env", [{"solver_command": "id; curl x"}, {"lsdyna_apptainer_sif": "/data/x.sif"},
                                     {"koomeshmodifier_path": "/tmp/evil"}, {"unknown_key": 1},
                                     {"lsdyna_apptainer_env": {"LSTC_LICENSE_SERVER": "1.2.3.4;id"}}])
def test_template_rejects_crafted_environment(tmp_path, bad_env):
    r = _run("scenario_drop", {"model_path": "/data/single/u/m.k", "lstc_license_ip": "192.168.122.1", "dry_run": True})
    sc = r.parsed["scenario"]
    sc["environment"].update(bad_env)   # backend 에 직접 제출한 경우를 흉내
    proc, _ = _template_validate(tmp_path, sc)
    assert proc.returncode == 1 and "ERROR" in proc.stdout


def test_template_rejects_unsafe_string_and_dwi(tmp_path):
    r = _run("scenario_drop", {"model_path": "/data/single/u/m.k", "lstc_license_ip": "192.168.122.1", "dry_run": True})
    sc = r.parsed["scenario"]
    sc["postprocess"] = {"deep_memory": "8G\nid"}
    proc, _ = _template_validate(tmp_path, sc)
    assert proc.returncode == 1 and "안전하지 않은 문자열" in proc.stdout
    sc2 = dict(r.parsed["scenario"], mode="drop_weight_impact")
    proc, _ = _template_validate(tmp_path, sc2)
    assert proc.returncode == 1 and "smarttwin-partial-impact" in proc.stdout


def test_scenario_requires_license_ip(monkeypatch):
    monkeypatch.delenv("STMC_LSTC_LICENSE_IP", raising=False)
    r = _run("scenario_drop", {"model_path": "/data/single/u/m.k", "dry_run": True})
    assert not r.ok and "lstc_license_ip" in r.parsed["reason"]
