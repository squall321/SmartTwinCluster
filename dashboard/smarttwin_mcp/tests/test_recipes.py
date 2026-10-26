# 레시피 등록소 시험 — 저장 관문(근거 잡과 같은 입력)·판·펼치기·실행·내리기·거절 꼴
"""근거 잡은 운영 경로와 같은 코드(stmc_tools 의 옵션 파일·후처리 인자 생성)로 만든 work/·stmc_result.json 을 쓴다.
레시피 저장소는 STMC_RECIPES_DIR 로 시험마다 임시 폴더를 쓴다. 가짜 backend·임시 DB·사용자 영역은 conftest.py.
"""
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

import pytest

from conftest import OTHER, USER

SHARED = Path(__file__).resolve().parent.parent / "tools" / "_shared"
DECK = "*KEYWORD\n*NODE\n       1     0.0     0.0     0.0\n*END\n"
MODES = [{"mode": "ELASTIC_TO_RIGID", "lines": ["*PIDExcept,5"]},
         {"mode": "TRANSFORM", "options": {"Translation": "{{dx}},0,0"}}]
RECIPE = {"name": "shift_rigid", "tool": "kmm_chain", "summary": "파트 5 를 빼고 강체로 둔 뒤 x 로 옮긴다",
          "tags": ["transform", "rigid"],
          "params": {"dx": {"type": "number", "description": "x 이동량", "default": 0.0, "minimum": -1000, "maximum": 1000}},
          "args": {"modes": MODES}}


@pytest.fixture
def store(tmp_path, monkeypatch):
    d = tmp_path / "recipes"
    monkeypatch.setenv("STMC_RECIPES_DIR", str(d))
    return d


@pytest.fixture
def mod():
    """같은 프로세스에서 recipes·stmc_tools 를 쓴다(근거 잡 만들기·펼친 입력 확인)."""
    sys.path.insert(0, str(SHARED))
    try:
        st = importlib.reload(importlib.import_module("stmc_tools"))
        rc = importlib.reload(importlib.import_module("recipes"))
        yield st, rc
    finally:
        sys.path.remove(str(SHARED))


def _expand_modes(dx):
    return [{"mode": "ELASTIC_TO_RIGID", "lines": ["*PIDExcept,5"]},
            {"mode": "TRANSFORM", "options": {"Translation": f"{dx!r},0,0"}}]


def _chain_job(reg, st, d: Path, modes, *, job_id="900101", rc=0, tool="kmm_chain") -> int:
    """운영 kmm_chain 이 만들었을 근거 잡 — work/model.k·stmc_options.txt·stmc_result.json + registry 행."""
    from stmc_exec import Bundle
    (d / "work").mkdir(parents=True)
    (d / "work" / "model.k").write_text(DECK)
    index = st._specs()["kmm_blocks"]
    b = Bundle(None)
    blocks = [(m["mode"], index[m["mode"]], st._kmm_block_lines(m, b, m["mode"])) for m in modes]
    (d / "work" / "stmc_options.txt").write_text(st._kmm_option_file("model.k", blocks))
    (d / "stmc_result.json").write_text(json.dumps({
        "schema": "stmc-result/1", "state": "done", "rc": rc, "tool": tool,
        "argv": [str(d / "work" / "stmc_options.txt"), str(d / "work")], "outputs": []}))
    return reg.record_submission(tool_name=tool, work_dir=str(d), output_dir=str(d / "work"), slurm_job_ids=[job_id],
                                 extra={"kind": "smarttwin-tool", "web_user": USER})


def _save(run_as, rid, dx=5.0, recipe=None, token="kst_user"):
    return run_as("recipe_save", {"recipe": recipe or RECIPE,
                                  "evidence": {"registry_id": rid, "params": {"dx": dx}, "note": "옮긴 뒤 초기 관통이 사라졌다"}},
                  token=token)


def test_save_list_get_run_roundtrip(registry, area, run_as, store, mod):
    st, rc = mod
    mine, _ = area
    rid = _chain_job(registry, st, mine / "ev1", _expand_modes(5.0))
    r = _save(run_as, rid)
    assert r["ok"] and r["saved"] and r["version"] == 1, r
    assert r["evidence"]["compared"] == ["argv", "stmc_options.txt"] or set(r["evidence"]["compared"]) == {"argv", "stmc_options.txt"}
    again = _save(run_as, rid)
    assert again["ok"] and not again["saved"] and again["unchanged"] and again["version"] == 1, again
    lst = run_as("recipe_list", {"query": "강체 shift"})
    assert lst["ok"] and lst["count"] == 1 and lst["recipes"][0]["created_by"] == USER, lst
    got = run_as("recipe_get", {"name": "shift_rigid"})
    assert got["recipe"]["version"] == 1 and got["recipe"]["evidence"][0]["result_dir"] == str(mine / "ev1"), got
    model = mine / "case" / "model.k"
    model.parent.mkdir()
    model.write_text(DECK)
    dry = run_as("recipe_run", {"name": "shift_rigid", "params": {"dx": 7.5}, "model_path": str(model), "dry_run": True})
    assert dry["ok"] and dry["dry_run"] and dry["recipe"]["version"] == 1, dry
    args = rc.run_args(rc.load("shift_rigid"), {"dx": 7.5}, {"model_path": str(model)})
    text = rc.capture("kmm_chain", args)["texts"]["stmc_options.txt"]
    assert "Translation,7.5,0,0" in text and "*PIDExcept,5" in text, text
    real = run_as("recipe_run", {"name": "shift_rigid", "params": {"dx": 1.0}, "model_path": str(model)})
    assert real["ok"] and str(real.get("job_id")) == "4242" and real["recipe"]["name"] == "shift_rigid", real


@pytest.mark.parametrize("change, needle", [
    ({"args": {"modes": [{"mode": "TRANSFORM", "options": {"Translation": "{{dy}},0,0"}}]}}, "선언하지 않은 자리"),
    ({"params": {"dx": {"type": "number", "description": "x"}, "dz": {"type": "number", "description": "z"}}}, "쓰지 않는 매개변수"),
    ({"tool": "job_status"}, "레시피 대상이 아니다"),
    ({"args": {"modes": MODES, "model_path": "/data/x.k"}}, "실행 때 정하는 키"),
    ({"name": "Bad-Name"}, "name"),
])
def test_save_rejects_malformed_recipes(registry, area, run_as, store, mod, change, needle):
    st, _ = mod
    mine, _ = area
    rid = _chain_job(registry, st, mine / "ev", _expand_modes(5.0))
    r = _save(run_as, rid, recipe={**RECIPE, **change})
    assert not r["ok"] and needle in r["reason"], r


def test_evidence_gate_refuses_jobs_that_did_not_run_this_recipe(registry, area, run_as, store, mod):
    st, _ = mod
    mine, theirs = area
    other = _chain_job(registry, st, theirs / "ev", _expand_modes(5.0), job_id="900201")
    r = _save(run_as, other)
    assert not r["ok"], r                                   # 남의 잡은 근거가 아니다
    failed = _chain_job(registry, st, mine / "ev_rc1", _expand_modes(5.0), job_id="900202", rc=1)
    r = _save(run_as, failed)
    assert not r["ok"] and "rc" in r["reason"], r
    wrong_tool = _chain_job(registry, st, mine / "ev_tool", _expand_modes(5.0), job_id="900203", tool="kmm_transform")
    r = _save(run_as, wrong_tool)
    assert not r["ok"] and "도구" in r["reason"], r
    rid = _chain_job(registry, st, mine / "ev_ok", _expand_modes(5.0), job_id="900204")
    r = _save(run_as, rid, dx=6.0)                          # 그 잡은 dx=5 로 돌았다
    assert not r["ok"] and "다르다" in r["reason"] and "stmc_options.txt" in r["reason"], r
    assert not list(store.glob("*/*.yaml")), "거절된 레시피가 저장됐다"


def test_versions_and_retire(registry, area, run_as, store, mod):
    st, _ = mod
    mine, _ = area
    rid = _chain_job(registry, st, mine / "ev", _expand_modes(5.0))
    assert _save(run_as, rid)["version"] == 1
    v2 = _save(run_as, rid, recipe={**RECIPE, "summary": "파트 5 를 빼고 강체로 둔 뒤 x 로 옮긴다(설명 고침)"})
    assert v2["ok"] and v2["saved"] and v2["version"] == 2, v2
    r = run_as("recipe_retire", {"name": "shift_rigid", "version": 1, "reason": "설명을 고친 판 2 로"}, token="kst_other")
    assert not r["ok"] and "만든 사람만" in r["reason"], r
    r = run_as("recipe_retire", {"name": "shift_rigid", "version": 1, "reason": "설명을 고친 판 2 로"})
    assert r["ok"] and r["retired"], r
    lst = run_as("recipe_list", {})
    assert lst["recipes"][0]["versions"] == [2], lst
    assert run_as("recipe_list", {"include_retired": True})["recipes"][0]["versions"] == [1, 2]
    assert run_as("recipe_get", {"name": "shift_rigid"})["recipe"]["version"] == 2
    model = mine / "model.k"
    model.write_text(DECK)
    old = run_as("recipe_run", {"name": "shift_rigid", "version": 1, "model_path": str(model), "dry_run": True})
    assert old["ok"] and "warning" in old["recipe"], old


def test_run_checks_params_against_the_recipe(registry, area, run_as, store, mod):
    st, _ = mod
    mine, _ = area
    rid = _chain_job(registry, st, mine / "ev", _expand_modes(5.0))
    _save(run_as, rid)
    model = mine / "model.k"
    model.write_text(DECK)
    for params, needle in (({"dx": 5000}, "maximum"), ({"dx": "far"}, "number"), ({"dy": 1}, "모르는 매개변수")):
        r = run_as("recipe_run", {"name": "shift_rigid", "params": params, "model_path": str(model), "dry_run": True})
        assert not r["ok"] and needle in r["reason"], (params, r)


def test_post_recipe_roundtrip(registry, area, run_as, store, mod):
    """후처리(post_custom_report) 레시피 — config 안 값이 매개변수, 근거는 운영 경로로 만든 입력과 같은 잡."""
    st, rc = mod
    mine, _ = area
    target = mine / "results"
    target.mkdir()
    recipe = {"name": "peak_vm_table", "tool": "post_custom_report", "summary": "파트별 최대 von Mises 표를 낸다",
              "params": {"top": {"type": "integer", "description": "위에서 몇 개", "default": 10, "minimum": 1}},
              "args": {"config": {"sections": [{"kind": "table", "metric": "von_mises", "top": "{{top}}"}]}}}
    ev = mine / "ev_post"
    (ev / "work").mkdir(parents=True)
    got = rc.capture("post_custom_report", rc.run_args(rc.validate(recipe), {"top": 5}, {"target": str(target)}))
    for name, text in got["texts"].items():
        (ev / "work" / name).write_text(text)
    (ev / "stmc_result.json").write_text(json.dumps({
        "state": "done", "rc": 0, "tool": "post_custom_report",
        "argv": [a.replace("@@WORK@@", str(ev / "work")) for a in got["argv"]], "outputs": []}))
    rid = registry.record_submission(tool_name="post_custom_report", work_dir=str(ev), output_dir=str(ev / "work"),
                                     slurm_job_ids=["900301"], extra={"kind": "smarttwin-tool", "web_user": USER})
    r = run_as("recipe_save", {"recipe": recipe, "evidence": {"registry_id": rid, "params": {"top": 5},
                                                              "target": str(target), "note": "상위 5개만 보면 충분했다"}})
    assert r["ok"] and r["version"] == 1, r
    bad = run_as("recipe_save", {"recipe": {**recipe, "name": "peak_vm_table2"},
                                 "evidence": {"registry_id": rid, "params": {"top": 7}, "target": str(target), "note": "다른 값"}})
    assert not bad["ok"] and "stmc_config.yaml" in bad["reason"], bad
    assert OTHER != USER
