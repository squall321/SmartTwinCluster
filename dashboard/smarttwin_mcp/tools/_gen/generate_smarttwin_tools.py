#!/usr/bin/env python3
# SmartTwin 정본 카탈로그(KMM·KAM help, kooremapper_core, 후처리 --help)에서 kmm_*/kam_*/remap_*/post_* MCP 도구를 생성
"""SmartTwin 전처리·후처리 기능 전부를 카탈로그 도구로 만든다.

정본(이것만 고치고 이 스크립트를 다시 돌린다)
  KooMeshModifier      <pyKooCAE>/occProject/Generators/KooCLIHelp/kmm_catalog.py
  KooAutomatedModeller <pyKooCAE>/occProject/Generators/KooCLIHelp/kam_catalog.py
  KooRemapper          tools/_shared/kooremapper_core/catalog_data.json (KooRemapper 리포 벤더링 사본)
  후처리               $STMC_POST_BIN/<도구> --help (argparse) + 이 파일의 POST_TOOLS 표

실행
  PYKOOCAE_ROOT=/home/koopark/serviceApptainers/appt313/opt/pyKooCAE \\
  STMC_POST_BIN=/data/SmartTwinPostprocessor/bin \\
  python3 tools/_gen/generate_smarttwin_tools.py

쓰는 것
  tools/<도구>/1.0.0/{meta.yaml,args.schema.json,script.sh} + latest  (생성 도구는 제자리 재생성 — §26)
  tools/_shared/stmc_specs.json   도구별 고정 정보(블록 이름·대상 인자 형태) + 기능 색인
  docs/smarttwin_coverage/COVERAGE.md
손으로 만든 도구는 건드리지 않는다(meta.yaml 에 생성 표식이 있는 것만 덮어쓴다).
"""
from __future__ import annotations

import importlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

TOOLS = Path(__file__).resolve().parents[1]
SHARED = TOOLS / "_shared"
REPO_MCP = TOOLS.parent
PYKOOCAE = Path(os.environ.get("PYKOOCAE_ROOT", "/home/koopark/serviceApptainers/appt313/opt/pyKooCAE"))
POST_BIN = Path(os.environ.get("STMC_POST_BIN", "/data/SmartTwinPostprocessor/bin"))
GEN_TAG = "generated"
GEN_NOTE = "생성됨: tools/_gen/generate_smarttwin_tools.py — 직접 고치지 말고 정본을 고친 뒤 다시 생성할 것."
VERSION = "1.0.0"
USER_EX = "/data/single/USER/case"   # 예제 경로 — 실제로는 호출자 영역

COMMON_PROPS = {
    "slurm": {
        "type": "object", "additionalProperties": False,
        "description": "잡 자원(선택). 생략하면 도구 종류별 기본(전처리 2 CPU·8G, 후처리 4 CPU·16G, 24시간)을 클러스터에서 가장 큰 노드에 맞춰 줄여 쓴다.",
        "properties": {
            "cpus_per_task": {"type": "integer", "minimum": 1, "maximum": 128, "description": "CPU 수"},
            "mem": {"type": "string", "pattern": "^[0-9]{1,6}[MG]$", "description": "메모리 (예: 32G)"},
            "time": {"type": "string", "pattern": "^[0-9]{1,3}:[0-5][0-9]:[0-5][0-9]$",
                     "description": "시간 상한 HH:MM:SS"},
            "partition": {"type": "string", "pattern": "^[A-Za-z0-9_-]{1,32}$",
                          "description": "파티션 이름 (생략 = 클러스터 기본)"},
        },
    },
    "dry_run": {"type": "boolean", "default": False,
                "description": "true 면 제출하지 않고 생성될 입력 파일·명령만 돌려준다(PAT 없이도 된다). 먼저 이걸로 확인할 것."},
    "wait_sec": {"type": "integer", "minimum": 0, "maximum": 1800, "default": 0,
                 "description": "제출 후 이 시간(초) 안에 끝나면 결과(rc·로그 꼬리·작은 산출물)를 함께 돌려준다. 0 = job_id 만."},
    "job_name": {"type": "string", "pattern": "^[A-Za-z0-9._-]{1,48}$",
                 "description": "잡 이름(결과 폴더 이름이 된다). 생략하면 stmc_<도구이름>."},
}
EXTRA_INPUTS = {"type": "array", "items": {"type": "string", "pattern": "^/.+"}, "maxItems": 64,
                "description": "옵션이 가리키는 보조 파일의 절대경로. 잡 work/ 폴더로 같이 올라가므로 옵션 값에는 파일 이름만 쓰면 된다. "
                               "허용 범위: /data/single/<사용자>/, /shared/uploads/users/<사용자>/, /data/scenario/."}

MCP_HOW_COMMON = """\
# 결과 받기
- 제출 응답의 job_id 로 `tool_result` 를 부르면 상태·rc·산출물 목록·로그 꼬리·작은 텍스트 산출물이 온다.
- 결과 폴더는 /data/single/<사용자>/<job_name>_<job_id>/ — work/(입력·산출물), stmc_result.json, stmc_stdout.log.
- 계산은 호출자 권한으로 Slurm 잡 하나로 돈다(backend_5010 경유, SIF 안에서 실행). 실제 제출에는 PAT 가 필요하다."""


# ── 공통 ─────────────────────────────────────────────────────────────────────────

def _catalog(module: str, path: Path):
    sys.path.insert(0, str(path))
    try:
        m = importlib.import_module(module)
        return next(v for v in vars(m).values() if type(v).__name__ == "Catalog")
    finally:
        sys.path.pop(0)


def _tool_dir_is_generated(d: Path) -> bool:
    meta = d / VERSION / "meta.yaml"
    if not meta.exists():
        return not d.exists()
    try:
        return GEN_TAG in (yaml.safe_load(meta.read_text(encoding="utf-8")) or {}).get("tags", [])
    except Exception:  # noqa: BLE001
        return False


class _Dumper(yaml.SafeDumper):
    """여러 줄 문자열은 `|` 블록으로 — 사람이 meta.yaml 을 읽을 수 있게."""


def _block_str(dumper, data):
    if "\n" in data:
        clean = "\n".join(line.rstrip().replace("\t", "    ") for line in data.splitlines()) + "\n"
        return dumper.represent_scalar("tag:yaml.org,2002:str", clean, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


_Dumper.add_representer(str, _block_str)


def _write_tool(name: str, summary: str, description: str, tags: list[str], schema: dict,
                examples: list[dict], written: list[str], skipped: list[str]) -> None:
    d = TOOLS / name
    if d.exists() and not _tool_dir_is_generated(d):
        skipped.append(name)
        return
    v = d / VERSION
    v.mkdir(parents=True, exist_ok=True)
    meta = {
        "name": name, "version": VERSION, "summary": summary,
        "description": description.rstrip() + "\n\n" + GEN_NOTE + "\n",
        "tags": tags + [GEN_TAG, "smarttwin", "mode-own"],
        "transport": {"kind": "local", "shell": "/bin/bash", "timeout_sec": 1950},
        "expose": "catalog",
        "examples": examples,
    }
    (v / "meta.yaml").write_text(yaml.dump(meta, Dumper=_Dumper, allow_unicode=True, sort_keys=False, width=100),
                                 encoding="utf-8")
    (v / "args.schema.json").write_text(json.dumps(schema, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    script = (
        "#!/usr/bin/env bash\n"
        f"# {name} — {summary} ({GEN_NOTE.split(' — ')[0]})\n"
        "# 성공 제출마다 _shared/stmc_exec.py 가 audit.record_event(...) 로 감사 기록을 남긴다(§25.3).\n"
        "set -euo pipefail\n"
        'SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"\n'
        f'exec python3 "$SHARED_DIR/stmc_tools.py" {name}\n'
    )
    sp = v / "script.sh"
    sp.write_text(script, encoding="utf-8")
    sp.chmod(0o755)
    latest = d / "latest"
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(VERSION)
    written.append(name)


def _schema(title: str, props: dict, required: list[str], any_of: list | None = None) -> dict:
    s = {"$schema": "https://json-schema.org/draft/2020-12/schema", "title": f"{title} args",
         "type": "object", "additionalProperties": False, "required": required,
         "properties": {**props, **COMMON_PROPS}}
    if any_of:
        s["anyOf"] = any_of
    return s


def _md_table(keys) -> str:
    rows = ["| 키 | 형식 | 기본 | 설명 |", "|---|---|---|---|"]
    for k in keys:
        cell = lambda x: str(x).replace("|", "\\|").replace("\n", " ")  # noqa: E731
        rows.append(f"| `{cell(k.name)}`{' (필수)' if getattr(k, 'required', False) else ''} | {cell(k.type)} "
                    f"| {cell(k.default)} | {cell(k.desc)} |")
    return "\n".join(rows)


def _ascii_tokens(*texts: str) -> list[str]:
    out = []
    for t in texts:
        for tok in re.findall(r"[a-z0-9]+", str(t).lower()):
            if len(tok) > 1 and tok not in out:
                out.append(tok)
    return out


# ── KooMeshModifier ──────────────────────────────────────────────────────────────

_KMM_KEY_RE = re.compile(r"^\*?[A-Za-z][A-Za-z0-9_.]*$")


def _kmm_value_schema(ktype: str) -> dict:
    t = (ktype or "").strip()
    if t == "실수":
        return {"type": ["number", "string"]}
    if t == "정수":
        return {"type": ["integer", "string"]}
    if t in ("True/False", "bool", "True|False"):
        return {"type": ["boolean", "string"]}
    return {"type": ["string", "number", "integer", "boolean", "array"]}


def _kmm_example_lines(text: str) -> list[str]:
    lines, inside = [], False
    for raw in text.splitlines():
        line = raw.rstrip()
        if line.startswith("**"):
            if inside:
                break
            inside = True
            continue
        if inside and line.strip():
            lines.append(line)
    return lines


def gen_kmm(written, skipped, specs, index):
    cat = _catalog("KooCLIHelp.kmm_catalog", PYKOOCAE / "occProject" / "Generators")
    fmt = next((t for t in cat.topics if t.name == "format"), None)
    blocks = {}
    for md in cat.modes:
        hdr = next((s for s in md.syntax if s.strip().startswith("**")), "")
        m = re.match(r"\*\*([A-Za-z_]+),", hdr.strip())
        if not m:
            raise SystemExit(f"KMM {md.name}: syntax 에 **블록,<ID> 줄이 없다")
        blocks[md.name] = m.group(1)
    for md in cat.modes:
        name = "kmm_" + md.name.lower()
        opt_props = {}
        for k in md.keys:
            if _KMM_KEY_RE.fullmatch(k.name):
                opt_props[k.name] = {**_kmm_value_schema(k.type),
                                     "description": f"{k.type} · 기본 {k.default} — {k.desc}"}
        props = {
            "model_path": {"type": "string", "pattern": "^/.+",
                           "description": "입력 LS-DYNA 모델(.k) 절대경로. 잡 work/ 폴더로 복사돼 *Inputfile 이 된다."},
            "options": {"type": "object", "properties": opt_props,
                        "additionalProperties": {"type": ["string", "number", "integer", "boolean", "array"]},
                        "description": "블록 안 `키,값` 줄. 값이 배열이면 쉼표로 잇는다(예: [0,0,10] → 0,0,10). "
                                       "아래 키 표에 없는 키(DropContact.<필드> 등)도 그대로 쓸 수 있다."},
            "lines": {"type": "array", "items": {"type": "string", "minLength": 1}, "maxItems": 2000,
                      "description": "블록에 그대로 넣을 원문 줄(같은 키 반복·*로 시작하는 줄·표). 사례 블록을 그대로 옮기면 된다. "
                                     "빈 줄·**/*Mode/*End 줄은 넣을 수 없다."},
            "extra_inputs": EXTRA_INPUTS,
        }
        ex_lines = _kmm_example_lines(md.examples[0].text) if md.examples else []
        ex1 = {"model_path": f"{USER_EX}/model.k", "dry_run": True}
        if ex_lines:
            ex1["lines"] = ex_lines
        ex2 = {**ex1, "dry_run": False, "wait_sec": 300, "slurm": {"cpus_per_task": 4, "mem": "16G"}}
        desc = [md.summary, ""]
        if md.when:
            desc += ["# 언제 쓰나"] + [f"- {w}" for w in md.when] + [""]
        desc += ["# 옵션 블록 문법 (KooMeshModifier --help " + md.name + ")", "```text", *md.syntax, "```", ""]
        if md.keys:
            desc += ["# 키", _md_table(md.keys), ""]
        for ex in md.examples:
            desc += [f"# 사례 — {ex.title}", "```text", ex.text, "```"] + [f"- {e}" for e in ex.explain] + [""]
        if md.notes:
            desc += ["# 주의"] + [f"- {n}" for n in md.notes] + [""]
        if md.related:
            desc += ["관련 모드: " + ", ".join(md.related), ""]
        desc += ["# MCP 로 부르는 법",
                 "- model_path 를 주면 옵션 파일 `*Inputfile` / `*Mode " + md.name + ",1` / `**" + blocks[md.name]
                 + ",1` … `**End" + blocks[md.name] + "` 을 만들어 준다.",
                 "- options 의 `키: 값` 과 lines 의 원문 줄이 블록 안에 들어간다(options 먼저).",
                 "- 키는 부분 문자열로 찾는 모드가 많고 모르는 키는 조용히 무시된다 — 위 표의 키 이름을 그대로 쓸 것.",
                 "- 단위는 모델 .k 를 따른다(KooMeshModifier 는 변환하지 않는다).",
                 "- 여러 모드를 한 번에: `kmm_chain`.", "", MCP_HOW_COMMON]
        if fmt:
            desc += ["", "# 옵션 파일 형식 (요약)"] + [f"    {b}" for b in fmt.body[:14]]
        tags = ["koomeshmodifier", "kmm", "preprocess", "lsdyna"] + _ascii_tokens(md.name, *md.aliases)
        _write_tool(name, f"KooMeshModifier {md.name} — {md.summary}"[:180], "\n".join(desc), tags,
                    _schema(name, props, ["model_path"]),
                    [{"title": "dry_run 으로 옵션 파일 확인", "args": ex1},
                     {"title": "제출하고 5분까지 기다리기", "args": ex2}], written, skipped)
        specs[name] = {"family": "kmm", "mode": md.name, "block": blocks[md.name]}
        index.append({"family": "KooMeshModifier", "category": md.category, "capability": md.name,
                      "tool": name, "summary": md.summary})
    # 여러 모드 체인
    name = "kmm_chain"
    props = {
        "model_path": {"type": "string", "pattern": "^/.+", "description": "입력 LS-DYNA 모델(.k) 절대경로"},
        "modes": {"type": "array", "minItems": 1, "maxItems": 20,
                  "items": {"type": "object", "additionalProperties": False, "required": ["mode"],
                            "properties": {"mode": {"type": "string", "enum": sorted(blocks),
                                                    "description": "KooMeshModifier 모드 이름"},
                                           "options": {"type": "object", "description": "그 모드 블록의 `키,값`"},
                                           "lines": {"type": "array", "items": {"type": "string", "minLength": 1},
                                                     "description": "그 모드 블록의 원문 줄"}}},
                  "description": "적용 순서대로. 같은 모델에 차례로 적용하고 마지막에 한 번 저장한다(출력 이름에 접미사가 순서대로 붙는다)."},
        "extra_inputs": EXTRA_INPUTS,
    }
    chain = next((t for t in cat.topics if t.name == "chain"), None)
    desc = ["KooMeshModifier 여러 모드를 한 옵션 파일에 순서대로 적용한다 (--help chain).", ""]
    if chain:
        desc += ["```text", *chain.body, "```", ""]
    desc += ["모드별 키·문법은 `kmm_<모드>` 도구의 설명을 볼 것(catalog_describe).", "", MCP_HOW_COMMON]
    ex = {"model_path": f"{USER_EX}/model.k", "dry_run": True,
          "modes": [{"mode": "ELASTIC_TO_RIGID", "lines": ["*PIDExcept,5"]},
                    {"mode": "TRANSFORM", "options": {"Translation": [0, 0, 10]}}]}
    _write_tool(name, "KooMeshModifier 여러 모드를 한 번에 순서대로 적용 (체인)", "\n".join(desc),
                ["koomeshmodifier", "kmm", "chain", "preprocess"], _schema(name, props, ["model_path", "modes"]),
                [{"title": "강체화 후 이동 (dry_run)", "args": ex},
                 {"title": "제출", "args": {**ex, "dry_run": False, "wait_sec": 300}}], written, skipped)
    specs[name] = {"family": "kmm_chain"}
    index.append({"family": "KooMeshModifier", "category": "체인", "capability": "chain", "tool": name,
                  "summary": "여러 모드를 한 옵션 파일에 순서대로"})
    return blocks


# ── KooAutomatedModeller ─────────────────────────────────────────────────────────

def gen_kam(written, skipped, specs, index):
    cat = _catalog("KooCLIHelp.kam_catalog", PYKOOCAE / "occProject" / "Generators")
    cli = next((t for t in cat.topics if t.name == "cli"), None)
    outs = next((t for t in cat.topics if t.name == "outputs"), None)
    for md in cat.modes:
        name = "kam_" + md.name.lower()
        is_json = md.name == "AIRMESH"
        input_name = "airmesh.json" if is_json else f"{md.name.lower()}_input.txt"
        props = {"input_path": {"type": "string", "pattern": "^/.+",
                                "description": "이미 있는 입력 파일 절대경로(이걸 주면 그대로 올린다)."},
                 "extra_inputs": EXTRA_INPUTS}
        if is_json:
            props["config"] = {"type": "object", "description": "AIRMESH JSON 설정(아래 키 표). 파일 경로 값은 절대경로로 주면 같이 올라간다."}
            any_of = [{"required": ["config"]}, {"required": ["input_path"]}]
        else:
            props["input_text"] = {"type": "string", "minLength": 1,
                                   "description": "입력 파일 본문(`키,값` 줄·*블록). 끝에 *End 가 없으면 붙인다. "
                                                  "참조 파일(재료·ODB 등)은 절대경로로 쓰면 같이 올라가고 이름으로 바뀐다."}
            any_of = [{"required": ["input_text"]}, {"required": ["input_path"]}]
        ex_text = md.examples[0].text if md.examples else ""
        if is_json:
            try:
                ex_cfg = json.loads(ex_text) if ex_text.strip().startswith("{") else {}
            except ValueError:
                ex_cfg = {}
            ex1 = {"config": ex_cfg or {"step_file": f"{USER_EX}/part.step"}, "dry_run": True}
        else:
            ex1 = {"input_text": ex_text or "*Layer,Body\nLength,1,1\nThickness,0.1\n*End", "dry_run": True}
        desc = [md.summary, ""]
        if md.when:
            desc += ["# 언제 쓰나"] + [f"- {w}" for w in md.when] + [""]
        desc += ["# 입력 파일 문법 (KooAutomatedModeller --help " + md.name + ")", "```text", *md.syntax, "```", ""]
        if md.keys:
            desc += ["# 키", _md_table(md.keys), ""]
        for ex in md.examples:
            desc += [f"# 사례 — {ex.title}", "```text", ex.text, "```"] + [f"- {e}" for e in ex.explain] + [""]
        if md.notes:
            desc += ["# 주의"] + [f"- {n}" for n in md.notes] + [""]
        if cli:
            desc += ["# 명령 형식"] + [f"    {b}" for b in cli.body] + [""]
        if outs:
            desc += ["# 산출물"] + [f"    {b}" for b in outs.body] + [""]
        desc += ["# MCP 로 부르는 법",
                 f"- {'config(JSON 객체)' if is_json else 'input_text(입력 본문)'} 또는 input_path 를 준다. "
                 f"`KooAutomatedModeller {md.name} {input_name} <work> False` 로 실행된다.",
                 "- 성공 여부는 종료 코드와 로그의 Complete/FAILED, 산출물로 확인한다(AIRMESH 는 report.json 의 status).",
                 "", MCP_HOW_COMMON]
        tags = ["kooautomatedmodeller", "kam", "preprocess", "geometry", "step"] + _ascii_tokens(md.name, *md.aliases)
        _write_tool(name, f"KooAutomatedModeller {md.name} — {md.summary}"[:180], "\n".join(desc), tags,
                    _schema(name, props, [], any_of),
                    [{"title": "dry_run 으로 입력 확인", "args": ex1},
                     {"title": "제출하고 10분까지 기다리기", "args": {**ex1, "dry_run": False, "wait_sec": 600}}],
                    written, skipped)
        specs[name] = {"family": "kam", "mode": md.name, "input_kind": "json" if is_json else "text",
                       "input_name": input_name}
        index.append({"family": "KooAutomatedModeller", "category": md.category, "capability": md.name,
                      "tool": name, "summary": md.summary})


# ── KooRemapper ─────────────────────────────────────────────────────────────────

_FILE_EXT = (".k", ".key", ".dyn", ".dat", ".json", ".yaml", ".yml", ".csv", ".txt", ".inc", ".step", ".stp")


def _remap_example(op: dict) -> tuple[dict, list[str]]:
    ex = dict((op.get("example") or {}).get("args") or {})
    files = []

    def walk(v):
        if isinstance(v, dict):
            return {k: walk(x) for k, x in v.items()}
        if isinstance(v, list):
            return [walk(x) for x in v]
        if isinstance(v, str) and v.lower().endswith(_FILE_EXT) and "/" not in v and not v.startswith("@"):
            files.append(v)
        return v
    walk(ex)
    outs = {p["name"] for p in op.get("params", []) if p.get("type") == "output" or p.get("role") == "output"}
    for k in ("output", "output_prefix"):
        outs.add(k)
    inputs = [f for f in dict.fromkeys(files) if f not in {str(ex.get(o)) for o in outs}]
    return ex, inputs


def gen_remap(written, skipped, specs, index):
    sys.path.insert(0, str(SHARED))
    from kooremapper_core import catalog
    for opname in sorted(catalog.operation_names()):
        op = catalog.get_operation(opname)
        if op.get("invocation") == "external":
            continue
        name = "remap_" + opname.replace("-", "_")
        base = catalog.args_json_schema(opname) or {"properties": {}, "required": []}
        props = dict(base.get("properties") or {})
        clash = set(props) & (set(COMMON_PROPS) | {"extra_inputs"})
        if clash:
            raise SystemExit(f"remap {opname}: op 인자 이름이 공통 인자와 겹친다: {clash}")
        for k, v in props.items():
            v.setdefault("description", k)
        props["extra_inputs"] = EXTRA_INPUTS
        ex, ex_inputs = _remap_example(op)
        ex1 = {**ex, "dry_run": True}
        if ex_inputs:
            ex1["extra_inputs"] = [f"{USER_EX}/{f}" for f in ex_inputs]
        desc = [op.get("summary") or opname, "", op.get("description") or ""]
        params = op.get("params") or []
        if params:
            desc += ["", "# 인자", "| 이름 | 형식 | 필수 | 설명 |", "|---|---|---|---|"]
            for p in params:
                d = str(p.get("description", "")).replace("|", "\\|").replace("\n", " ")
                desc.append(f"| `{p['name']}` | {p['type']} | {'예' if p.get('required') else ''} | {d} |")
        keys = op.get("keys") or []
        if keys:
            desc += ["", "# config 키 (YAML)"]
            for k in keys[:150]:
                if isinstance(k, dict):
                    desc.append(f"- `{k.get('name')}` ({k.get('type', '')}): {str(k.get('desc', '')).strip()}")
            if len(keys) > 150:
                desc.append(f"- … 외 {len(keys) - 150}개 (KooRemapper help {opname})")
        if op.get("presets"):
            desc += ["", "# 프리셋", "```json", json.dumps(op["presets"], ensure_ascii=False, indent=1)[:4000], "```"]
        if op.get("notes"):
            notes = op["notes"] if isinstance(op["notes"], list) else [op["notes"]]
            desc += ["", "# 주의"] + [f"- {n}" for n in notes]
        if (op.get("example") or {}).get("note"):
            desc += ["", "사례 메모: " + op["example"]["note"]]
        desc += ["", "# MCP 로 부르는 법",
                 f"- 인자는 `KooRemapper {opname}` 의 인자 그대로다(kooremapper_core 가 argv·config.yaml 을 만든다).",
                 "- 입력 파일은 절대경로로 주면 같이 올라가고 파일 이름으로 바뀐다. 이름만 쓰려면 extra_inputs 에 절대경로를 둔다.",
                 "- 출력(output 등)은 파일 이름만 — 잡 work/ 폴더에 생긴다.",
                 f"- gmsh 필요: {'예' if op.get('requires_gmsh') else '아니오'} (SIF 에 포함).", "", MCP_HOW_COMMON]
        tags = ["kooremapper", "remap", "preprocess", "lsdyna", str(op.get("category") or "")] + _ascii_tokens(opname)
        _write_tool(name, f"KooRemapper {opname} — {op.get('summary') or ''}"[:180], "\n".join(desc),
                    [t for t in tags if t], _schema(name, props, list(base.get("required") or [])),
                    [{"title": "dry_run 으로 argv·config 확인", "args": ex1},
                     {"title": "제출하고 5분까지 기다리기", "args": {**ex1, "dry_run": False, "wait_sec": 300}}],
                    written, skipped)
        specs[name] = {"family": "remap", "op": opname}
        index.append({"family": "KooRemapper", "category": op.get("category") or "", "capability": opname,
                      "tool": name, "summary": op.get("summary") or ""})


# ── 후처리 ───────────────────────────────────────────────────────────────────────

POST_TOOLS = {
    # 도구: binary, 요약, target(대상 인자 형태), config_flag, 손으로 적은 옵션(argparse 가 아닌 것)
    "post_analyze": dict(binary="post_analyze", argparse=False, target=dict(mode="positional", kind="dir", required=True),
                         summary="통합 후처리 — unified_analyzer → sphere/impact report → deep report (기존 결과 자동 스킵)",
                         config_flag=None),
    "post_unified_analyzer": dict(binary="unified_analyzer", argparse=False,
                                  target=dict(mode="flag", flag="--recursive", kind="dir", required=False),
                                  summary="d3plot 분석 엔진 — YAML 작업(응력·변형률·운동·표면·핫스팟·렌더) 단일/재귀 실행",
                                  config_flag="--config", config_required=True, in_place_default=False),
    "post_deep_report": dict(binary="koo_deep_report", argparse=True, target=dict(mode="positional", kind="any", required=True),
                             summary="단일 시뮬 깊은 분석 HTML 리포트 — 파트별 응력·변형률·핫스팟 군집·단면뷰",
                             config_flag="--config"),
    "post_sphere_report": dict(binary="koo_sphere_report", argparse=True,
                               target=dict(mode="flag", flag="--test-dir", kind="dir", required=False),
                               requires_one_of=["target", "options.from_json"],
                               summary="전각도 낙하 통합 리포트 — Mollweide 구면 지도·방향별 위험도 (또는 --from-json 재생성)"),
    "post_impact_report": dict(binary="koo_impact_report", argparse=True,
                               target=dict(mode="flag", flag="--test-dir", kind="dir", required=False),
                               requires_one_of=["target", "options.from_json"],
                               summary="부분충격(DWI) 다면 DOE 리포트 — 면별 위치 격자 위험도 (또는 --from-json 재생성)"),
    "post_federate_report": dict(binary="koo_federate_report", argparse=True, target=dict(mode="none"),
                                 summary="여러 리비전 sidecar(impact/sphere)를 하나의 비교 리포트로 연합",
                                 config_flag="--config", config_required=True, in_place_default=False),
    "post_custom_report": dict(binary="koo_custom_report", argparse=True, target=dict(mode="positional", kind="any", required=True),
                               summary="*SET_ 정의 기반 커스텀 후처리 리포트 — 세트별 응력·변형률·영상",
                               config_flag="--config"),
    "post_scatter_report": dict(binary="koo_scatter_report", argparse=True, target=dict(mode="positional", kind="dir", required=True),
                                summary="각도 산포 캠페인 리포트 — 편차각 산포·방향도·회수율"),
    "post_dyna_diag": dict(binary="koo_dyna_diag", argparse=True, target=dict(mode="positional", kind="dir", required=False),
                           # 기본 색인·보고서 위치가 ~/.koodyna 라 잡 결과 폴더로 고정한다.
                           forced_args=["--index", "@@RESULT@@/koodyna_index.json",
                                        "--output-dir", "@@RESULT@@/koodyna_reports"],
                           requires_one_of=["target", "options.scan", "options.list_index", "options.analyze"],
                           summary="LS-DYNA 결과 진단 — 에러·경고·성능 프로파일 JSON/HTML (단일 폴더 또는 일괄 색인)"),
    "post_make_stl": dict(binary="make_stl", argparse=False, target=dict(mode="positional", kind="file", required=True),
                          summary="d3plot·모델 .k 에서 미리보기 STL 생성 (리포트 실형상 미리보기용)",
                          positionals_after_target=["out_prefix", "target_tris", "voxel_res", "parts"],
                          in_place_default=False),
}

POST_ANALYZE_FLAGS = [
    ("deep-only", 0, "deep report 만"), ("sphere-only", 0, "sphere report 만 (DROP 전각도 강제)"),
    ("impact-only", 0, "impact report 만 (IMPACT 부분충격 DOE 강제)"), ("force", 0, "기존 결과 무시하고 전체 재계산"),
    ("no-schema-check", 0, "산출물이 낡아도 재분석하지 않음"), ("config", 1, "unified_analyzer 용 YAML 경로(객체를 주면 YAML 로 만들어 올린다)"),
    ("deep-config", 1, "koo_deep_report 용 YAML"), ("threads", 1, "병렬 스레드 수 (기본 4)"), ("yield-stress", 1, "항복응력 MPa"),
    ("no-render", 0, "렌더 끔"), ("per-part-render", 0, "파트별 렌더"), ("element-quality", 0, "요소 품질 분석"),
    ("render-threads", 1, "렌더 스레드"), ("ua-threads", 1, "unified_analyzer 스레드"), ("parts", "+", "파트 ID 목록"),
    ("part-pattern", 1, "파트 패턴"), ("strain-limit", 1, "변형률 한계"), ("design-overrides", 1, "설계 기준 JSON"),
    ("material-overrides", 1, "재료 기준 JSON"), ("section-view", 0, "단면뷰"), ("section-view-backend", 1, "lsprepost|software"),
    ("section-view-mode", 1, "section|section_3d"), ("section-view-per-part", 0, "파트별 단면뷰"),
    ("section-view-axes", "+", "x y z"), ("section-view-fields", "+", "von_mises eps strain …"),
    ("section-view-target-ids", "+", "대상 파트 ID"), ("section-view-target-patterns", "+", "대상 파트 패턴"),
    ("section-view-fade", 1, "페이드 거리"), ("sv-threads", 1, "단면뷰 스레드"),
    ("deep-opts", 1, "koo_deep_report 추가 옵션 문자열"), ("sphere-opts", 1, "koo_sphere_report 추가 옵션 문자열"),
    ("scatter", 0, "각도 산포 리포트도 생성"), ("scatter-opts", 1, "koo_scatter_report 옵션 문자열"),
    ("impact-opts", 1, "koo_impact_report 옵션 문자열"),
]
UNIFIED_FLAGS = [("output", 1, "재귀 모드 결과 폴더 (기본 ./analysis_results)"),
                 ("skip-existing", 0, "완료 표식이 같은 실행은 건너뜀 (증분)"), ("threads", 1, "OpenMP 스레드 (0=자동)"),
                 ("analysis-only", 0, "분석만 (렌더 생략)"), ("render-only", 0, "렌더만")]
_SKIP_FLAGS = {"help", "version", "install-dir", "ua"}


def _parse_argparse_help(text: str) -> tuple[list[dict], list[dict]]:
    flags, positionals, section = [], [], None
    cur = None
    for raw in text.splitlines():
        if re.match(r"^(options|optional arguments):\s*$", raw):
            section, cur = "opt", None
            continue
        if re.match(r"^positional arguments:\s*$", raw):
            section, cur = "pos", None
            continue
        if not raw.strip():
            cur = None
            continue
        if section == "opt" and re.match(r"^  -", raw):
            line = raw.strip()
            gap = re.search(r"\s{2,}", line)
            head, help1 = (line[:gap.start()], line[gap.end():]) if gap else (line, "")
            parts = [p.strip() for p in head.split(", ")]
            longs = [p for p in parts if p.startswith("--")]
            if not longs:
                cur = None
                continue
            lp = longs[0].split(" ", 1)
            meta = lp[1] if len(lp) > 1 else next((p.split(" ", 1)[1] for p in parts if " " in p), "")
            fname = lp[0][2:]
            choices = None
            m = re.match(r"^\{([^}]*)\}", meta)
            if m:
                choices = m.group(1).split(",")
            nargs = 0 if not meta else ("+" if "..." in meta else 1)
            cur = {"name": fname, "nargs": nargs, "choices": choices, "metavar": meta, "help": help1.strip()}
            if fname not in _SKIP_FLAGS:
                flags.append(cur)
            continue
        if section == "pos" and re.match(r"^  \S", raw):
            bits = re.split(r"\s{2,}", raw.strip(), maxsplit=1)
            cur = {"name": bits[0], "help": bits[1] if len(bits) > 1 else ""}
            positionals.append(cur)
            continue
        if cur is not None and raw.startswith("    "):
            cur["help"] = (cur["help"] + " " + raw.strip()).strip()
    return flags, positionals


def _flag_schema(f) -> dict:
    d = f"--{f['name']}" + (f" {f['metavar']}" if f.get("metavar") else "") + f" — {f.get('help', '')}"
    if f["nargs"] == 0:
        return {"type": "boolean", "description": d}
    if f.get("choices"):
        s = {"type": "string", "enum": f["choices"], "description": d}
        return {"anyOf": [s, {"type": "array", "items": s}], "description": d} if f["nargs"] == "+" else s
    if f["nargs"] == "+":
        return {"type": ["array", "string", "number"], "items": {"type": ["string", "number"]}, "description": d}
    return {"type": ["string", "number", "integer", "object"], "description": d + " (객체를 주면 YAML 파일로 만들어 넘긴다)"}


def gen_post(written, skipped, specs, index):
    for name, cfg in POST_TOOLS.items():
        binp = POST_BIN / cfg["binary"]
        helptext = subprocess.run([str(binp), "--help"], capture_output=True, text=True, timeout=120).stdout \
            if binp.exists() else ""
        if cfg["argparse"]:
            flags, positionals = _parse_argparse_help(helptext)
        elif name == "post_analyze":
            flags = [{"name": n, "nargs": a, "choices": None, "metavar": "" if a == 0 else "X", "help": h}
                     for n, a, h in POST_ANALYZE_FLAGS]
            positionals = [{"name": "test_dir", "help": "후처리할 시험 폴더"}]
        elif name == "post_unified_analyzer":
            flags = [{"name": n, "nargs": a, "choices": None, "metavar": "" if a == 0 else "X", "help": h}
                     for n, a, h in UNIFIED_FLAGS]
            positionals = []
        else:
            flags, positionals = [], []
        tgt = cfg.get("target") or {}
        tflag = tgt.get("flag", "").lstrip("-")
        cfg_flag = (cfg.get("config_flag") or "").lstrip("-")
        forced = cfg.get("forced_args") or []
        forced_names = {a.lstrip("-") for a in forced if a.startswith("--")}
        opt_flags = [f for f in flags if f["name"] not in ({tflag, cfg_flag} | forced_names) - {""}]
        opt_props = {f["name"].replace("-", "_"): _flag_schema(f) for f in opt_flags}
        props = {
            "options": {"type": "object", "properties": opt_props, "additionalProperties": False,
                        "description": "명령줄 옵션. 키는 --옵션 이름(밑줄·하이픈 모두 됨), 켜는 옵션은 true. "
                                       "--install-dir·--ua 처럼 실행 파일 위치를 바꾸는 옵션은 받지 않는다."},
            "argv_extra": {"type": "array", "items": {"type": "string"}, "maxItems": 64,
                           "description": "그대로 덧붙일 인자(드물게). 같은 금지 규칙과 경로 검사를 받는다."},
            "in_place": {"type": "boolean", "default": cfg.get("in_place_default", True),
                         "description": "true 면 target 폴더(파일이면 그 폴더)에서 실행해 산출물이 결과 옆에 생긴다. "
                                        "false 면 잡 결과 폴더 work/ 에서 실행."},
        }
        required = []
        if tgt.get("mode") in ("positional", "flag"):
            what = {"dir": "폴더", "file": "파일", "any": "폴더 또는 파일"}[tgt.get("kind", "any")]
            props["target"] = {"type": "string", "pattern": "^/.+",
                               "description": f"분석할 {what} 절대경로 — /data/single/<사용자>/ 아래만"
                                              + (f" ({tgt['flag']} 로 넘어간다)" if tgt.get("mode") == "flag" else "")}
            if tgt.get("required"):
                required.append("target")
        if cfg.get("config_flag"):
            props["config"] = {"type": ["object", "string"],
                               "description": f"{cfg['config_flag']} 로 넘길 설정 — 객체면 YAML 로 만들어 올리고, 문자열이면 "
                                              "/data/single/<사용자>/ 아래 YAML 절대경로."}
            if cfg.get("config_required"):
                required.append("config")
        for pname in cfg.get("positionals_after_target") or []:
            props[pname] = {"type": ["string", "integer", "number"], "description": f"make_stl 위치 인자 {pname}"}
        ex1 = {"dry_run": True}
        if "target" in props:
            ex1["target"] = f"{USER_EX}/run1" if tgt.get("kind") != "file" else f"{USER_EX}/run1/d3plot"
        if cfg.get("config_required"):
            ex1["config"] = {"d3plot": f"{USER_EX}/run1/d3plot"} if name == "post_unified_analyzer" else \
                {"revisions": [{"name": "rev1", "sidecar": f"{USER_EX}/rev1/impact_payload.json"}]}
        if name == "post_make_stl":
            ex1["out_prefix"] = "preview"
        ex2 = {**ex1, "dry_run": False, "wait_sec": 900, "slurm": {"cpus_per_task": 8, "mem": "32G"}}
        desc = [cfg["summary"], "", "# 명령 도움말 (" + cfg["binary"] + " --help)", "```text", helptext.strip()[:12000], "```", "",
                "# MCP 로 부르는 법",
                "- target 은 기존 결과(d3plot 이 있는 폴더 등)의 절대경로. 업로드하지 않고 그 자리에서 읽는다 — "
                "/data/single/<사용자>/ 아래만 된다(전각도·부분충격 잡의 결과 폴더가 거기 있다).",
                "- options 의 키는 위 도움말의 --옵션 이름. 값이 객체면 YAML 파일로 만들어 넘긴다.",
                "- --install-dir·--ua 와 설정의 lsprepost_path 처럼 실행 파일을 고르는 항목은 거절된다(보안).",
                "- 후처리 SIF(/opt/apptainers/SmartTwinPostprocessor.sif) 안에서 돈다. 큰 캠페인은 slurm.mem·time 을 넉넉히.",
                "", MCP_HOW_COMMON]
        tags = ["postprocess", "kood3plot", "report", "d3plot"] + _ascii_tokens(name, cfg["binary"])
        _write_tool(name, cfg["summary"][:180], "\n".join(desc), tags, _schema(name, props, required),
                    [{"title": "dry_run 으로 명령 확인", "args": ex1}, {"title": "제출하고 15분까지 기다리기", "args": ex2}],
                    written, skipped)
        specs[name] = {"family": "post", "binary": cfg["binary"], "target": tgt,
                       "config_flag": cfg.get("config_flag"), "config_required": bool(cfg.get("config_required")),
                       "positionals_after_target": cfg.get("positionals_after_target") or [],
                       "requires_one_of": cfg.get("requires_one_of") or [], "forced_args": forced,
                       "in_place_default": cfg.get("in_place_default", True)}
        index.append({"family": "SmartTwinPostprocessor", "category": "후처리", "capability": cfg["binary"],
                      "tool": name, "summary": cfg["summary"]})


# ── KooChainRun 시나리오 ─────────────────────────────────────────────────────────

SCENARIO_TOOLS = {"DROP": "scenario_drop", "IMPACT": "scenario_impact", "VIBRATION": "scenario_vibration",
                  "THERM": "scenario_therm", "REMAP": "scenario_remap",
                  "part_validation": "scenario_part_validation", "drop_weight_impact": "scenario_drop_weight_impact"}
# KooChainRun 명령 → 손으로 쓴 도구. 새 명령이 생기면 생성이 멈춘다(대응 도구를 정할 것).
KCR_COMMAND_TOOLS = {"prepare": "scenario_submit", "submit": "scenario_submit", "status": "job_status",
                     "collect": "job_collect", "postprocess": "job_postprocess", "diagnose": "job_diagnose",
                     "rerun": "job_rerun", "stop": "job_stop", "reprioritize": "job_reprioritize",
                     "harvest": "job_harvest"}
KCR_INTERNAL_COMMANDS = {"run"}  # 계산 노드에서 submit 이 부르는 내부 명령
ONE_CLICK_TOOLS = {"fullangle_drop_simulation": "전각도 낙하 원클릭 — 모델 하나로 피보나치 N 방향 낙하 + 자동 후처리",
                   "single_drop_simulation": "지정 각도(roll/pitch/yaw) 1방향 낙하 원클릭"}
_IPV4 = "^([0-9]{1,3}\\.){3}[0-9]{1,3}$"


def _scenario_props(workflow: str | None, precision_default: str, generic: bool = False) -> dict:
    props = {
        "model_path": {"type": "string", "pattern": "^/.+",
                       "description": "입력 LS-DYNA 모델(.k) 절대경로 — 캠페인 결과 폴더로 올라가 template/model_file 이 된다."},
        "lstc_license_ip": {"type": "string", "pattern": _IPV4,
                            "description": "계산 노드에서 보이는 LS-DYNA 라이선스 서버 IPv4(localhost 금지). 생략하면 서버 env STMC_LSTC_LICENSE_IP."},
        "scenario": {"type": "object",
                     "description": "사례 시나리오 위에 덮어쓸 값(딥머지, 목록은 통째 교체). environment·mode·model_file·output_dir·"
                                    "project_name 은 서버 고정이라 무시되고, 문자열은 공백·셸 메타문자 없는 토큰만 받는다. "
                                    "받지 않은 값은 응답 locked_overrides_dropped 에 나온다."},
        "ncpu": {"type": "integer", "minimum": 1, "maximum": 256, "default": 2, "description": "자식 잡(LS-DYNA) CPU 수"},
        "memory": {"type": "string", "pattern": "^[0-9]+[GM]$", "default": "4G", "description": "자식 잡 메모리"},
        "time_limit": {"type": "string", "pattern": "^[0-9]{1,3}:[0-5][0-9]:[0-5][0-9]$", "default": "12:00:00",
                       "description": "자식 잡 시간 상한"},
        "solver_precision": {"type": "string", "enum": ["single", "double"], "default": precision_default,
                             "description": "LS-DYNA 정밀도 — /opt/apptainers 의 _mpp_s / _mpp_d SIF. 열(ICPower)은 double 필수."},
        "partition": {"type": "string", "pattern": "^[A-Za-z0-9_-]{1,32}$", "description": "자식 잡 파티션(생략 = 클러스터 기본)"},
        "dry_run": COMMON_PROPS["dry_run"], "job_name": COMMON_PROPS["job_name"],
    }
    if workflow != "drop_weight_impact":
        props["driver_mem"] = {"type": "string", "pattern": "^[0-9]{1,5}[MG]$",
                               "description": "드라이버 잡 메모리(기본 1G). DOE 수천 개 캠페인은 4G~8G 로."}
        props["aux_inputs"] = {**EXTRA_INPUTS, "description": "시나리오가 이름으로 가리키는 보조 파일(각도 케이스 .txt·곡선 등) 절대경로. "
                                                              "결과 폴더의 scenario.json 옆에 놓인다. scenario 안에 절대경로를 써도 같이 올라간다."}
    if workflow is None:
        props["postprocess"] = {"type": "boolean",
                                "description": "끝난 뒤 KooChainRun postprocess(deep·sphere/impact 리포트) 실행 여부. 생략 = 사례 설정"}
    if generic:
        props["mode"] = {"type": "string", "enum": ["cumulative", "part_validation", "drop_weight_impact"],
                         "default": "cumulative", "description": "cumulative = scenarios[].cumulative.mode_sequence 의 DROP/IMPACT/VIBRATION/THERM/REMAP 조합"}
        props["scenario"]["description"] = ("전체 scenario.json(필수). 형식은 scenario_<모드> 도구 설명의 사례를 볼 것. "
                                            + props["scenario"]["description"])
    return props


def gen_scenario(written, skipped, specs, index):
    cat = _catalog("Runner.cli_help_kcr", PYKOOCAE)
    for md in cat.modes:
        if md.name not in SCENARIO_TOOLS:
            continue
        name = SCENARIO_TOOLS[md.name]
        workflow = md.name if md.name in ("part_validation", "drop_weight_impact") else None
        precision = "double" if md.name == "THERM" else "single"
        skeleton = json.loads(md.examples[0].text)
        props = _scenario_props(workflow, precision)
        ex1 = {"model_path": f"{USER_EX}/model.k", "lstc_license_ip": "192.168.122.1", "dry_run": True}
        ex2 = {**ex1, "scenario": {"simulation_params": {"tFinal": 0.002}}, "ncpu": 4, "memory": "8G"}
        desc = [md.summary, ""]
        if md.when:
            desc += ["# 언제 쓰나"] + [f"- {w}" for w in md.when] + [""]
        if md.keys:
            desc += ["# 시나리오 키 (KooChainRun --help " + md.name + ")", _md_table(md.keys), ""]
        for ex in md.examples:
            desc += [f"# 사례 — {ex.title}", "```json", ex.text, "```"] + [f"- {e}" for e in ex.explain] + [""]
        if md.notes:
            desc += ["# 주의"] + [f"- {n}" for n in md.notes] + [""]
        desc += ["# MCP 로 부르는 법",
                 "- 위 첫 사례가 기본 시나리오다. 바꿀 부분만 `scenario` 로 준다(딥머지, 목록은 통째 교체 — scenarios 를 주면 사례의 "
                 "scenarios 가 통째로 바뀌므로 사례 형식을 그대로 따를 것).",
                 "- environment(경로·SIF·솔버 명령)는 서버가 만든다 — ncpu·memory·time_limit·solver_precision·partition·"
                 "lstc_license_ip 인자로만 조정한다. 시간 상한(environment.timeout_*_seconds 정수)은 scenario 로 줄 수 있다.",
                 "- 드라이버 잡 하나(1 CPU)가 KooChainRun prepare→submit→자식 잡 대기→collect→(postprocess) 를 돈다. "
                 "진행·결과는 job_status·job_collect·job_diagnose·job_postprocess·post_* 도구로.",
                 "- dry_run=true 로 먼저 최종 scenario.json 을 확인할 것(PAT 없이 된다)."]
        if workflow == "drop_weight_impact":
            desc += ["- smarttwin-partial-impact 템플릿으로 나간다(보조 입력 없음)."]
        _write_tool(name, f"KooChainRun {md.name} — {md.summary}"[:180], "\n".join(desc),
                    ["koochainrun", "scenario", "campaign", "lsdyna", "doe"] + _ascii_tokens(md.name, *md.aliases),
                    _schema_plain(name, props, ["model_path"]),
                    [{"title": "dry_run 으로 최종 scenario.json 확인", "args": ex1},
                     {"title": "시간·자원을 바꿔 제출", "args": {**ex2, "dry_run": False}}], written, skipped)
        specs[name] = {"family": "scenario", "mode": md.name, "workflow": workflow, "skeleton": skeleton,
                       "precision_default": precision}
        index.append({"family": "KooChainRun", "category": md.category, "capability": md.name, "tool": name,
                      "summary": md.summary})
    # 범용
    name = "scenario_submit"
    props = _scenario_props(None, "single", generic=True)
    props["aux_inputs"] = {**EXTRA_INPUTS, "description": "시나리오가 이름으로 가리키는 보조 파일 절대경로(DWI 는 불가)."}
    ex = {"model_path": f"{USER_EX}/model.k", "lstc_license_ip": "192.168.122.1", "dry_run": True,
          "scenario": json.loads(next(m for m in cat.modes if m.name == "DROP").examples[0].text)}
    desc = ["임의의 KooChainRun scenario.json 을 그대로 제출한다(모드 조합 자유). 모드별 기본값이 필요하면 scenario_<모드> 를 쓸 것.", "",
            "- mode=cumulative 면 scenarios[].cumulative.mode_sequence 로 DROP/IMPACT/VIBRATION/THERM/REMAP 를 섞는다.",
            "- 잠금·문자열 규칙·environment 생성은 scenario_<모드> 와 같다.", "", MCP_HOW_COMMON.split("\n# 결과 받기")[0]]
    _write_tool(name, "KooChainRun 임의 scenario.json 제출 (모드 조합 자유)", "\n".join(desc),
                ["koochainrun", "scenario", "campaign", "submit", "generic"],
                _schema_plain(name, props, ["model_path", "scenario"]),
                [{"title": "전체 시나리오 dry_run", "args": ex}, {"title": "제출", "args": {**ex, "dry_run": False}}],
                written, skipped)
    specs[name] = {"family": "scenario", "generic": True}
    index.append({"family": "KooChainRun", "category": "범용", "capability": "scenario.json", "tool": name,
                  "summary": "임의 scenario.json 제출"})
    for md in cat.modes:
        if md.category != "명령" or md.name in KCR_INTERNAL_COMMANDS:
            continue
        if md.name not in KCR_COMMAND_TOOLS:
            raise SystemExit(f"KooChainRun 명령 {md.name} 에 대응 도구가 없다 — KCR_COMMAND_TOOLS 에 정할 것")
        index.append({"family": "KooChainRun", "category": "명령", "capability": md.name,
                      "tool": KCR_COMMAND_TOOLS[md.name], "summary": md.summary})
    for tool, summary in ONE_CLICK_TOOLS.items():
        index.append({"family": "KooChainRun", "category": "원클릭", "capability": tool, "tool": tool, "summary": summary})


def _schema_plain(title: str, props: dict, required: list[str]) -> dict:
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "title": f"{title} args", "type": "object",
            "additionalProperties": False, "required": required, "properties": props}


def main() -> int:
    written, skipped, specs, index = [], [], {}, []
    blocks = gen_kmm(written, skipped, specs, index)
    gen_kam(written, skipped, specs, index)
    gen_remap(written, skipped, specs, index)
    gen_post(written, skipped, specs, index)
    gen_scenario(written, skipped, specs, index)
    rev = lambda p: subprocess.run(["git", "-C", str(p), "rev-parse", "--short", "HEAD"],  # noqa: E731
                                   capture_output=True, text=True).stdout.strip() or "?"
    out = {"version": 1, "sources": {"pykoocae": rev(PYKOOCAE), "post_bin": str(POST_BIN)},
           "kmm_blocks": blocks, "tools": specs, "index": index}
    (SHARED / "stmc_specs.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    cov = ["<!-- 생성됨: tools/_gen/generate_smarttwin_tools.py — SmartTwin 기능 ↔ MCP/REST 도구 대응표 -->",
           "# SmartTwin 기능 커버리지", "",
           f"정본 pyKooCAE `{out['sources']['pykoocae']}` · 후처리 `{POST_BIN}` 기준. "
           f"기능 {len(index)}개 → 도구 {len({r['tool'] for r in index})}개.", "",
           "| 제품 | 분류 | 기능 | MCP 도구 (REST: POST /smarttwin-api/v1/tools/<도구>/run) | 요약 |", "|---|---|---|---|---|"]
    for r in index:
        cov.append(f"| {r['family']} | {r['category']} | {r['capability']} | `{r['tool']}` | {str(r['summary'])[:80]} |")
    (REPO_MCP / "docs" / "smarttwin_coverage" / "COVERAGE.md").write_text("\n".join(cov) + "\n", encoding="utf-8")
    print(json.dumps({"written": len(written), "skipped_handwritten": skipped, "index": len(index)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
