# SmartTwin 생성 도구(kmm_*/kam_*/remap_*/post_*)의 공통 진입점 — 패밀리별 입력 렌더링 후 stmc_exec 로 제출
"""stmc_tools — 생성된 도구의 script.sh 가 `python3 stmc_tools.py <도구이름>` 으로 부른다.

도구별 고정 정보(KMM 블록 이름, 후처리 대상 인자 형태 등)는 생성기가 만든 stmc_specs.json 에 있다.
인자는 STMC_ARGS_JSON(JSON 객체). 결과는 표준출력 JSON 한 개(AGENT_GUIDE §4.3).

패밀리
  kmm        KooMeshModifier 모드 하나 — 옵션 파일(*Inputfile/*Mode/**Block) 생성
  kmm_chain  KooMeshModifier 여러 모드를 한 옵션 파일에 순서대로
  kam        KooAutomatedModeller 모드 — 입력 텍스트(PKG·CAPACITOR·PCB·ArrayPCB·PBA) 또는 JSON(AIRMESH)
  remap      KooRemapper op — kooremapper_core.build_command 로 argv·config.yaml 생성
  post       KooD3plotReader 후처리 실행 파일 — 기존 결과 폴더를 그대로 가리킨다(업로드 없음)
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from stmc_exec import (WORK, Bundle, StmcError, caller_identity, check_under, input_roots,  # noqa: E402
                       submit_tool_job, user_area, work)

COMMON_KEYS = ("slurm", "dry_run", "wait_sec", "job_name")
FORBIDDEN_FLAGS = ("install-dir", "ua")                 # 템플릿 디스패처와 같은 목록
FORBIDDEN_KEYS = ("lsprepost_path", "install_dir", "ua_path")
_KMM_KEY_RE = re.compile(r"^\*?[A-Za-z][A-Za-z0-9_.]*$")
_KMM_STRUCTURE_RE = re.compile(r"^\s*(\*\*|\*(Inputfile|Mode|End)\b)", re.I)
_ABS_IN_TEXT_RE = re.compile(r"(?:(?<=[\s,:=\"'\[(])|^)(/[^\s,\"'\]\)]+)", re.M)


def _specs() -> dict:
    with open(HERE / "stmc_specs.json", encoding="utf-8") as f:
        return json.load(f)


def _out(obj: dict, code: int = 0) -> None:
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.exit(code)


def _context(args: dict):
    """(dry_run, identity, roots). PAT 가 있으면 dry_run 이어도 경로를 실제로 검사한다."""
    dry = bool(args.get("dry_run", False))
    try:
        ident = caller_identity()
    except StmcError:
        if not dry:
            raise
        ident = None
    roots = input_roots(ident["username"]) if ident else None
    return dry, ident, roots


def _submit(tool, family, binary, argv, bundle, args, ident, **kw):
    return submit_tool_job(tool=tool, family=family, binary=binary, argv=argv, bundle=bundle,
                           slurm=args.get("slurm"), job_name=args.get("job_name"),
                           dry_run=bool(args.get("dry_run", False)), wait_sec=int(args.get("wait_sec") or 0),
                           identity=ident, **kw)


def _rewrite_text_paths(text: str, bundle: Bundle) -> str:
    """텍스트 안 절대경로 중 파일을 가리키는 것을 묶음에 넣고 이름으로 바꾼다(옵션 줄·KAM 입력용)."""
    def sub(m):
        return bundle.rewrite_paths(m.group(1))
    return _ABS_IN_TEXT_RE.sub(sub, text)


def _scan_forbidden_keys(obj, where: str) -> None:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if str(k) in FORBIDDEN_KEYS:
                raise StmcError(f"{where} 에 실행 경로를 바꾸는 키 '{k}' 가 있다 — 허용하지 않는다")
            _scan_forbidden_keys(v, where)
    elif isinstance(obj, list):
        for v in obj:
            _scan_forbidden_keys(v, where)


# ── KooMeshModifier ──────────────────────────────────────────────────────────────

def _kmm_value(v) -> str:
    if isinstance(v, bool):
        return "True" if v else "False"
    if isinstance(v, (list, tuple)):
        return ",".join(_kmm_value(x) for x in v)
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    s = str(v)
    if "\n" in s or "\r" in s:
        raise StmcError(f"옵션 값에 줄바꿈이 있다: {s[:40]!r}")
    return s


def _kmm_block_lines(block: dict, bundle: Bundle, label: str) -> list[str]:
    out = []
    opts = bundle.rewrite_paths(block.get("options") or {})
    for k, v in opts.items():
        if not _KMM_KEY_RE.fullmatch(str(k)):
            raise StmcError(f"{label}: 옵션 키를 쓸 수 없다: {k!r} — 이런 줄은 lines 로 그대로 줄 것")
        out.append(f"{k},{_kmm_value(v)}")
    for line in block.get("lines") or []:
        if not isinstance(line, str) or not line.strip() or "\n" in line or "\r" in line:
            raise StmcError(f"{label}: lines 에 빈 줄·줄바꿈을 넣을 수 없다(블록이 그 자리에서 끝난다): {line!r}")
        if _KMM_STRUCTURE_RE.match(line):
            raise StmcError(f"{label}: lines 에 블록 구조 줄(**…, *Inputfile, *Mode, *End)을 넣을 수 없다: {line!r}")
        out.append(_rewrite_text_paths(line, bundle))
    return out


def _kmm_option_file(model_name: str, blocks: list[tuple[str, str, list[str]]]) -> str:
    text = ["*Inputfile", model_name, "*Mode"]
    text += [f"{mode},{i}" for i, (mode, _b, _l) in enumerate(blocks, start=1)]
    for i, (_mode, block, lines) in enumerate(blocks, start=1):
        text.append(f"**{block},{i}")
        text += lines
        text.append(f"**End{block}")
    text.append("*End")
    return "\n".join(text) + "\n"


def run_kmm(tool: str, spec: dict, args: dict) -> dict:
    dry, ident, roots = _context(args)
    bundle = Bundle(roots)
    model = bundle.add_file(args["model_path"])
    for p in args.get("extra_inputs") or []:
        bundle.add_file(p)
    if spec["family"] == "kmm_chain":
        index = _specs()["kmm_blocks"]
        blocks = []
        for i, step in enumerate(args.get("modes") or [], start=1):
            mode = str(step.get("mode", "")).upper()
            if mode not in index:
                raise StmcError(f"modes[{i}]: 모르는 KooMeshModifier 모드 {mode!r} (가능: {', '.join(sorted(index))})")
            blocks.append((mode, index[mode], _kmm_block_lines(step, bundle, f"modes[{i}] {mode}")))
        if not blocks:
            raise StmcError("modes 가 비어 있다")
    else:
        blocks = [(spec["mode"], spec["block"], _kmm_block_lines(args, bundle, spec["mode"]))]
    bundle.add_text("stmc_options.txt", _kmm_option_file(model, blocks))
    return _submit(tool, "kmm", "KooMeshModifier", [work("stmc_options.txt"), WORK], bundle, args, ident)


# ── KooAutomatedModeller ─────────────────────────────────────────────────────────

def run_kam(tool: str, spec: dict, args: dict) -> dict:
    dry, ident, roots = _context(args)
    bundle = Bundle(roots)
    for p in args.get("extra_inputs") or []:
        bundle.add_file(p)
    name = spec["input_name"]
    if spec["input_kind"] == "json":
        cfg = args.get("config")
        if args.get("input_path"):
            name = bundle.add_file(args["input_path"])
        elif isinstance(cfg, dict):
            bundle.add_text(name, json.dumps(bundle.rewrite_paths(cfg), ensure_ascii=False, indent=1) + "\n")
        else:
            raise StmcError("config(객체) 또는 input_path 중 하나가 필요하다")
    else:
        if args.get("input_path"):
            name = bundle.add_file(args["input_path"])
        else:
            text = args.get("input_text")
            if not isinstance(text, str) or not text.strip():
                raise StmcError("input_text 또는 input_path 중 하나가 필요하다")
            text = _rewrite_text_paths(text.replace("\r\n", "\n"), bundle).rstrip("\n")
            # PCB·ArrayPCB 파서는 *End 가 없으면 EOF 에서 멈추지 않는다(카탈로그 cli 주제).
            if not re.search(r"(?mi)^\*End\s*$", text):
                text += "\n*End"
            bundle.add_text(name, text + "\n")
    return _submit(tool, "kam", "KooAutomatedModeller", [spec["mode"], name, WORK, "False"], bundle, args, ident)


# ── KooRemapper ─────────────────────────────────────────────────────────────────

def run_remap(tool: str, spec: dict, args: dict) -> dict:
    from kooremapper_core import build_command
    dry, ident, roots = _context(args)
    bundle = Bundle(roots)
    for p in args.get("extra_inputs") or []:
        bundle.add_file(p)
    op_args = {k: v for k, v in args.items() if k not in COMMON_KEYS + ("extra_inputs",)}
    op_args = bundle.rewrite_paths(op_args)
    with tempfile.TemporaryDirectory(prefix="stmc_remap_") as td:
        built = build_command(spec["op"], op_args, Path(td),
                              material_db_default="/opt/kooremapper/materials/material_db.json")
        if built.error:
            raise StmcError(f"{spec['op']} 인자 오류: {built.error}")
        for fname, text in built.written_files.items():
            bundle.add_text(fname, text)
        argv = [a.replace(td, WORK) for a in built.argv]
    return _submit(tool, "remap", "KooRemapper", argv, bundle, args, ident)


# ── 후처리 ───────────────────────────────────────────────────────────────────────

def _flag_tokens(key: str, value, bundle: Bundle, roots, where: str) -> list[str]:
    name = key.lstrip("-").replace("_", "-")
    if name in FORBIDDEN_FLAGS:
        raise StmcError(f"--{name} 는 실행 파일 위치를 바꾸는 옵션이라 허용하지 않는다")
    flag = "--" + name
    if value is None or value is False:
        return []
    if value is True:
        return [flag]
    if isinstance(value, dict):
        _scan_forbidden_keys(value, where)
        fname = bundle.add_text(f"stmc_{name.replace('-', '_')}.yaml", _yaml(value))
        return [flag, work(fname)]
    if isinstance(value, list):
        return [flag] + [_post_token(v, roots) for v in value]
    return [flag, _post_token(value, roots)]


def _post_token(v, roots) -> str:
    s = str(v)
    if "\n" in s:
        raise StmcError(f"인자 값에 줄바꿈이 있다: {s[:40]!r}")
    if s.startswith("/") and roots is not None:
        check_under(s, roots, kind="parent")   # 옵션 값은 입력일 수도 출력일 수도 있다 — 범위만 확실히
    for piece in s.split():
        if piece.lstrip("-").split("=", 1)[0] in FORBIDDEN_FLAGS and piece.startswith("--"):
            raise StmcError(f"{piece} 는 허용하지 않는 옵션이다")
    return s


def _yaml(obj) -> str:
    import yaml
    return yaml.safe_dump(obj, allow_unicode=True, sort_keys=False, default_flow_style=False)


def run_post(tool: str, spec: dict, args: dict) -> dict:
    need = spec.get("requires_one_of") or []
    if need:
        have = [n for n in need if (args.get(n) if "." not in n else
                                    (args.get(n.split(".")[0]) or {}).get(n.split(".", 1)[1]))]
        if not have:
            raise StmcError(f"다음 중 하나는 있어야 한다: {', '.join(need)}")
    dry, ident, roots = _context(args)
    bundle = Bundle(roots)
    target = args.get("target")
    user_roots = [user_area(ident["username"])] if ident else None
    argv: list[str] = []
    tgt = spec.get("target") or {}
    if target is not None:
        if user_roots is not None:
            check_under(target, user_roots, kind=tgt.get("kind", "any"))
        if tgt.get("mode") == "flag":
            argv += [tgt["flag"], target]
        elif tgt.get("mode") == "positional":
            argv.append(target)
    elif tgt.get("required"):
        raise StmcError("target(분석할 결과 폴더 또는 파일의 절대경로)이 필요하다")
    for name in spec.get("positionals_after_target") or []:
        if args.get(name) is not None:
            argv.append(_post_token(args[name], roots))
    cfg_flag = spec.get("config_flag")
    if cfg_flag:
        cfg = args.get("config")
        if isinstance(cfg, dict):
            _scan_forbidden_keys(cfg, "config")
            argv += [cfg_flag, work(bundle.add_text("stmc_config.yaml", _yaml(cfg)))]
        elif isinstance(cfg, str):
            if user_roots is not None:
                check_under(cfg, user_roots, kind="file")
            argv += [cfg_flag, cfg]
        elif spec.get("config_required"):
            raise StmcError(f"config(객체 또는 {cfg_flag} 로 넘길 YAML 파일 절대경로)가 필요하다")
    for key, value in (args.get("options") or {}).items():
        argv += _flag_tokens(key, value, bundle, user_roots, f"options.{key}")
    for tok in args.get("argv_extra") or []:
        argv.append(_post_token(tok, user_roots))
    for forced in spec.get("forced_args") or []:
        argv.append(forced)
    in_place = bool(args.get("in_place", spec.get("in_place_default", True)))
    cwd, existing = "work", None
    if in_place and target:
        existing = target if (ident is None or os.path.isdir(target)) else os.path.dirname(target)
        cwd = "existing"
    return _submit(tool, "post", spec["binary"], argv, bundle, args, ident, cwd=cwd, existing_dir=existing)


RUNNERS = {"kmm": run_kmm, "kmm_chain": run_kmm, "kam": run_kam, "remap": run_remap, "post": run_post}


def main(argv: list[str]) -> None:
    tool = argv[1] if len(argv) > 1 else ""
    spec = _specs()["tools"].get(tool)
    if spec is None:
        _out({"ok": False, "reason": f"stmc_specs.json 에 없는 도구: {tool}"}, 1)
    try:
        args = json.loads(os.environ.get("STMC_ARGS_JSON") or "{}")
        res = RUNNERS[spec["family"]](tool, spec, args)
    except StmcError as e:
        _out({"ok": False, "tool": tool, "reason": str(e)}, 1)
    except Exception as e:  # noqa: BLE001
        _out({"ok": False, "tool": tool, "reason": f"{type(e).__name__}: {e}"}, 1)
    _out(res, 0 if res.get("ok") else 1)


if __name__ == "__main__":
    main(sys.argv)
