#!/usr/bin/env python3
# SmartTwin 생성 도구 실잡 e2e — 카탈로그 러너로 backend_5010·Slurm·SIF 를 거쳐 실제 실행하고 결과를 확인
"""사용법
  STMC_E2E_PAT=$(cat pat.txt) STMC_E2E_ROOT=/data/single/<사용자>/stmc_e2e \\
    venv/bin/python scripts/e2e_smarttwin_tools.py [사례이름 ...]

STMC_E2E_ROOT 아래에 model.k(작은 덱)와 run1/(끝난 LS-DYNA 실행, Output/d3plot)이 있어야 한다.
각 사례는 wait_sec 안에 끝나기를 기다리고 rc·산출물·표준출력으로 판정한다. 마지막 줄은 요약 JSON.
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from smarttwin_mcp.catalog import load_catalog  # noqa: E402
from smarttwin_mcp.runner import run as run_tool  # noqa: E402

E = os.environ.get("STMC_E2E_ROOT", "/data/single/admin/stmc_e2e")
RUN = f"{E}/run1/Output"


def _has(res, needle):
    return needle in (res.get("stdout_tail") or "")


def _out(res, suffix):
    return any(o["path"].endswith(suffix) for o in res.get("outputs") or [])


def _mats_of(res, suffix):
    """산출 덱의 (파트→MID, MID→*MAT 키워드). rc·파일 존재만으로는 재질 소실을 못 잡는다(2026-10-13 KMM 결함)."""
    path = next((o["path"] for o in res.get("outputs") or [] if o["path"].endswith(suffix)), None)
    if not path:
        return {}, {}
    t = Path(path).read_text(errors="replace").splitlines()
    parts, mats = {}, {}
    for i, line in enumerate(t):
        key = line.strip().upper()
        if key.startswith("*MAT"):
            j = i + 1 + (1 if key.endswith("_TITLE") else 0)
            while j < len(t) and t[j].startswith("$"):
                j += 1
            mats[int(t[j][:10])] = key
        elif key == "*PART":
            j = i + 2
            while j < len(t) and t[j].startswith("$"):
                j += 1
            parts[int(t[j][:10])] = int(t[j][20:30])
    return parts, mats


def _etor_except_ok(res, suffix):
    """*PIDExcept,2 — 파트 2 는 원래 재질, 파트 1 은 강체, 참조 누락 0."""
    parts, mats = _mats_of(res, suffix)
    return (bool(parts) and set(parts.values()) <= set(mats)
            and "VISCOELASTIC" in mats.get(parts.get(2), "") and "RIGID" in mats.get(parts.get(1), ""))


CASES = {
    "remap_info": ({"mesh_file": f"{E}/model.k", "wait_sec": 300},
                   lambda r: r.get("rc") == 0 and _has(r, "Nodes:")),
    "remap_matdb": ({"model": f"{E}/model.k", "output": "mapped.k", "materials": [{"match": "*"}], "wait_sec": 300},
                    lambda r: r.get("rc") == 0 and _out(r, "mapped.k")),
    "kmm_transform": ({"model_path": f"{E}/model.k", "options": {"Translation": [0, 0, 10]}, "wait_sec": 900},
                      lambda r: r.get("rc") == 0 and _out(r, "_trans.k")),
    "kmm_chain": ({"model_path": f"{E}/model.k", "wait_sec": 900,
                   "modes": [{"mode": "ELASTIC_TO_RIGID", "lines": ["*PIDExcept,2"]},
                             {"mode": "TRANSFORM", "options": {"Translation": [0, 0, 5]}}]},
                  lambda r: r.get("rc") == 0 and _etor_except_ok(r, "_etor_trans.k")),
    "kam_pkg": ({"input_text": "*Translation,0.0,0.0,0.0\n*Rotation,0\n*Mirror,False\n*IsTop,True\n"
                               "*Layer,Substrate\nLocation,0,0,0\nLength,10.0,8.0\nThickness,0.3\n"
                               "*Layer,Die\nLocation,0,0\nLength,6.0,5.0\nThickness,0.2\n*End",
                 "wait_sec": 900},
                lambda r: r.get("rc") == 0 and _out(r, ".step")),
    "post_dyna_diag": ({"target": RUN, "options": {"output": f"{RUN}/stmc_koodyna.json"}, "wait_sec": 600},
                       lambda r: r.get("rc") == 0),
    "post_make_stl": ({"target": f"{RUN}/d3plot", "out_prefix": "stmc_preview", "wait_sec": 900},
                      lambda r: r.get("rc") == 0 and _out(r, ".stl")),
    "post_deep_report": ({"target": RUN, "options": {"no_render": True, "output": f"{RUN}/stmc_deep"},
                          "slurm": {"cpus_per_task": 4, "mem": "16G"}, "wait_sec": 1800},
                         lambda r: r.get("rc") == 0),
}


def main(names: list[str]) -> int:
    pat = os.environ.get("STMC_E2E_PAT") or ""
    if not pat:
        print("STMC_E2E_PAT 가 필요하다", file=sys.stderr)
        return 2
    os.environ.setdefault("STMC_CLUSTER_URL", "http://127.0.0.1:5010")
    os.environ["STMC_CLUSTER_TOKEN"] = pat
    cat = load_catalog(ROOT / "tools")
    summary = {}
    for name in names or list(CASES):
        args, check = CASES[name]
        t0 = time.time()
        r = run_tool(cat.resolve(name), args)
        out = r.parsed or {}
        res = out.get("result") or {}
        ok = bool(out.get("ok")) and res.get("state") == "done" and check(res)
        summary[name] = {"ok": ok, "job_id": out.get("job_id"), "rc": res.get("rc"), "state": res.get("state"),
                         "secs": round(time.time() - t0), "outputs": [o["path"].rsplit("/", 1)[-1]
                                                                      for o in (res.get("outputs") or [])][:6],
                         "error": out.get("reason") or out.get("error") or res.get("error")}
        print(json.dumps({name: summary[name]}, ensure_ascii=False), flush=True)
        if not ok:
            print("  stdout_tail:", (res.get("stdout_tail") or r.stdout)[-1500:], flush=True)
            print("  stderr_tail:", (res.get("stderr_tail") or r.stderr)[-800:], flush=True)
    print(json.dumps({"passed": sum(v["ok"] for v in summary.values()), "total": len(summary)}))
    return 0 if all(v["ok"] for v in summary.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
