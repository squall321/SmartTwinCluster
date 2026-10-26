# 레시피 등록소 — 효과를 본 도구 인자 틀을 판별로 저장하고, 매개변수로 펼치고, 근거 잡의 입력과 대조한다
"""recipes — recipe_save·recipe_list·recipe_get·recipe_run·recipe_retire 의 공통 모듈.

레시피 = 기존 카탈로그 도구 하나(kmm_*·kmm_chain·post_*)의 인자 틀 + 매개변수 정의 + 근거(효과를 본 잡).
코드가 아니라 데이터다 — 실행은 원래 도구 경로(stmc_tools)가 그대로 하므로 바이너리 재빌드가 필요 없다.

관문: 레시피를 근거 매개변수로 펼쳐 만든 입력 글(stmc_options.txt·stmc_config.yaml …)과 argv 가
근거 잡의 work/ 파일·stmc_result.json 과 같아야 저장한다 — "효과를 본 바로 그 실행" 임을 보증.

저장: $STMC_RECIPES_DIR(기본 /data/SmartTwinMCP/recipes)/<이름>/<판>.yaml. 판은 1 부터 늘고 덮어쓰지 않는다.
"""
from __future__ import annotations

import copy
import fcntl
import hashlib
import json
import os
import re
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

from stmc_exec import WORK, StmcError, find_owned_job, read_result

NAME_RE = re.compile(r"^[a-z][a-z0-9_]{2,47}$")
PARAM_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
TAG_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
SLOT_RE = re.compile(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}")
RUNTIME_KEYS = ("model_path", "target", "extra_inputs", "slurm", "dry_run", "wait_sec", "job_name")
FAMILIES = ("kmm", "kmm_chain", "post")
PARAM_TYPES = {"number": (int, float), "integer": (int,), "string": (str,), "boolean": (bool,)}
TOOLS_DIR = Path(__file__).resolve().parents[1]


def root() -> Path:
    return Path(os.environ.get("STMC_RECIPES_DIR") or "/data/SmartTwinMCP/recipes")


def _specs() -> dict:
    import stmc_tools
    return stmc_tools._specs()["tools"]


# ── 형식 검증 ─────────────────────────────────────────────────────────────────────

def _slots(obj) -> set[str]:
    if isinstance(obj, str):
        return set(SLOT_RE.findall(obj))
    if isinstance(obj, dict):
        return set().union(*(_slots(v) for v in obj.values())) if obj else set()
    if isinstance(obj, list):
        return set().union(*(_slots(v) for v in obj)) if obj else set()
    return set()


def _typed(name: str, ps: dict, value):
    t = ps["type"]
    if t == "integer" and isinstance(value, float) and value.is_integer():
        value = int(value)
    if (isinstance(value, bool) and t != "boolean") or not isinstance(value, PARAM_TYPES[t]):
        raise StmcError(f"매개변수 {name}: {t} 이어야 한다 — {value!r}")
    if t in ("number", "integer"):
        if "minimum" in ps and value < ps["minimum"]:
            raise StmcError(f"매개변수 {name}: {value} < minimum {ps['minimum']}")
        if "maximum" in ps and value > ps["maximum"]:
            raise StmcError(f"매개변수 {name}: {value} > maximum {ps['maximum']}")
    if t == "string" and ("\n" in value or "\r" in value or len(value) > 256):
        raise StmcError(f"매개변수 {name}: 줄바꿈 없는 256자 이하 글이어야 한다")
    if "enum" in ps and value not in ps["enum"]:
        raise StmcError(f"매개변수 {name}: {value!r} 는 허용 값 {ps['enum']} 이 아니다")
    return value


def validate(doc: dict) -> dict:
    """recipe_save 입력을 검사하고 저장할 꼴로 정리해 돌려준다(근거 확인 전)."""
    if not isinstance(doc, dict):
        raise StmcError("recipe 는 객체여야 한다")
    name, tool = str(doc.get("name", "")), str(doc.get("tool", ""))
    if not NAME_RE.fullmatch(name):
        raise StmcError(f"name 은 소문자로 시작하는 3~48자 [a-z0-9_] 여야 한다: {name!r}")
    spec = _specs().get(tool)
    if spec is None or spec.get("family") not in FAMILIES:
        ok = sorted(t for t, s in _specs().items() if s.get("family") in FAMILIES)
        raise StmcError(f"tool {tool!r} 는 레시피 대상이 아니다 — kmm_*·kmm_chain·post_* 중 하나({len(ok)}개)")
    summary = str(doc.get("summary", "")).strip()
    if not 5 <= len(summary) <= 200 or "\n" in summary:
        raise StmcError("summary 는 한 줄 5~200자여야 한다")
    description = str(doc.get("description", "")).strip()
    if len(description) > 4000:
        raise StmcError("description 은 4000자 이하여야 한다")
    tags = doc.get("tags") or []
    if not isinstance(tags, list) or len(tags) > 10 or any(not TAG_RE.fullmatch(str(t)) for t in tags):
        raise StmcError("tags 는 [a-z0-9_-] 낱말 10개 이하여야 한다")
    params = doc.get("params") or {}
    if not isinstance(params, dict) or len(params) > 32:
        raise StmcError("params 는 32개 이하의 객체여야 한다")
    clean_params = {}
    for pname, ps in params.items():
        if not PARAM_RE.fullmatch(str(pname)):
            raise StmcError(f"매개변수 이름은 소문자로 시작하는 [a-z0-9_] 여야 한다: {pname!r}")
        if not isinstance(ps, dict) or ps.get("type") not in PARAM_TYPES:
            raise StmcError(f"매개변수 {pname}: type 은 {', '.join(PARAM_TYPES)} 중 하나여야 한다")
        extra = set(ps) - {"type", "description", "default", "minimum", "maximum", "enum"}
        if extra:
            raise StmcError(f"매개변수 {pname}: 모르는 키 {sorted(extra)}")
        if not str(ps.get("description", "")).strip():
            raise StmcError(f"매개변수 {pname}: description 이 필요하다")
        if ("minimum" in ps or "maximum" in ps) and ps["type"] not in ("number", "integer"):
            raise StmcError(f"매개변수 {pname}: minimum·maximum 은 수 매개변수에만 쓴다")
        cp = dict(ps)
        if "enum" in cp:
            if not isinstance(cp["enum"], list) or not cp["enum"]:
                raise StmcError(f"매개변수 {pname}: enum 은 비지 않은 목록이어야 한다")
            cp["enum"] = [_typed(pname, {"type": ps["type"]}, v) for v in cp["enum"]]
        if "default" in cp:
            cp["default"] = _typed(pname, cp, cp["default"])
        clean_params[str(pname)] = cp
    args = doc.get("args")
    if not isinstance(args, dict) or not args:
        raise StmcError("args(원래 도구에 넘길 인자 틀)가 필요하다")
    runtime = sorted(set(args) & set(RUNTIME_KEYS))
    if runtime:
        raise StmcError(f"args 에 실행 때 정하는 키를 넣지 않는다(recipe_run 이 받는다): {runtime}")
    used = _slots(args)
    undeclared = sorted(used - set(clean_params))
    if undeclared:
        raise StmcError(f"args 안에 선언하지 않은 자리 {{{{…}}}}: {undeclared}")
    unused = sorted(set(clean_params) - used)
    if unused:
        raise StmcError(f"쓰지 않는 매개변수: {unused} — 지우거나 args 의 {{{{이름}}}} 자리에 쓸 것")
    return {"name": name, "tool": tool, "summary": summary, "description": description,
            "tags": [str(t) for t in tags], "params": clean_params, "args": copy.deepcopy(args)}


# ── 펼치기 ───────────────────────────────────────────────────────────────────────

def _text(v) -> str:
    if isinstance(v, bool):
        return "True" if v else "False"
    return repr(v) if isinstance(v, float) else str(v)


def resolve_params(params: dict, values: dict | None) -> dict:
    values = dict(values or {})
    unknown = sorted(set(values) - set(params))
    if unknown:
        raise StmcError(f"모르는 매개변수: {unknown} (이 레시피: {sorted(params) or '없음'})")
    out = {}
    for pname, ps in params.items():
        if pname in values:
            out[pname] = _typed(pname, ps, values[pname])
        elif "default" in ps:
            out[pname] = ps["default"]
        else:
            raise StmcError(f"매개변수 {pname} 의 값이 필요하다({ps.get('description', '')})")
    return out


def expand(template, values: dict):
    """{{이름}} 자리를 채운다. 값 전체가 자리 하나면 타입 그대로, 아니면 글로 끼운다(키는 바꾸지 않는다)."""
    if isinstance(template, str):
        m = SLOT_RE.fullmatch(template.strip())
        if m:
            return values[m.group(1)]
        return SLOT_RE.sub(lambda mm: _text(values[mm.group(1)]), template)
    if isinstance(template, dict):
        return {k: expand(v, values) for k, v in template.items()}
    if isinstance(template, list):
        return [expand(v, values) for v in template]
    return template


def run_args(recipe: dict, values: dict | None, runtime: dict) -> dict:
    """원래 도구에 넘길 인자 = 펼친 틀 + 실행 때 키. 원래 도구의 args.schema.json 으로 검사한다."""
    args = expand(recipe["args"], resolve_params(recipe["params"], values))
    for k in RUNTIME_KEYS:
        if runtime.get(k) is not None:
            args[k] = runtime[k]
    schema_path = TOOLS_DIR / recipe["tool"] / "latest" / "args.schema.json"
    try:
        import jsonschema
        with open(schema_path, encoding="utf-8") as f:
            jsonschema.validate(args, json.load(f))
    except FileNotFoundError:
        raise StmcError(f"도구 {recipe['tool']} 의 args.schema.json 이 없다 — 카탈로그에서 빠진 도구다")
    except jsonschema.ValidationError as e:
        where = "/".join(str(p) for p in e.absolute_path) or "(맨 위)"
        raise StmcError(f"펼친 인자가 {recipe['tool']} 스키마에 맞지 않는다 — {where}: {e.message}")
    return args


def capture(tool: str, args: dict) -> dict:
    """원래 도구 경로로 입력을 만들되 제출하지 않고 붙잡는다 → {argv, texts}. 검증 코드가 운영 경로와 같다."""
    import stmc_tools
    spec = stmc_tools._specs()["tools"][tool]
    got: dict = {}

    def fake_submit(_tool, _family, _binary, argv, bundle, _args, _ident, **_kw):
        got.update(argv=list(argv), texts=dict(bundle.texts))
        return {"ok": True}
    orig = stmc_tools._submit
    stmc_tools._submit = fake_submit
    try:
        stmc_tools.RUNNERS[spec["family"]](tool, spec, dict(args, dry_run=True))
    finally:
        stmc_tools._submit = orig
    return got


# ── 근거 확인 ─────────────────────────────────────────────────────────────────────

def verify_evidence(recipe: dict, evidence: dict, username: str) -> dict:
    """근거 잡이 호출자 것이고 끝났고 rc 0 이고 같은 도구이며, 레시피를 근거 매개변수로 펼친 입력이 그 잡과 같은지."""
    if not isinstance(evidence, dict):
        raise StmcError("evidence(효과를 본 잡: job_id·registry_id·work_dir 중 하나 + 그때의 params + note)가 필요하다")
    ref = {k: evidence[k] for k in ("registry_id", "job_id", "work_dir") if evidence.get(k) is not None}
    if len(ref) != 1:
        raise StmcError("evidence 에 job_id·registry_id·work_dir 중 정확히 하나를 줄 것")
    note = str(evidence.get("note", "")).strip()
    if not note:
        raise StmcError("evidence.note 에 무엇이 효과였는지 적을 것")
    job_dir, row = find_owned_job(ref, username)
    res = read_result(job_dir)
    if res.get("state") != "done":
        raise StmcError(f"근거 잡이 아직 끝나지 않았다(state={res.get('state')}) — 끝난 뒤 저장할 것")
    if res.get("rc") != 0:
        raise StmcError(f"근거 잡의 rc 가 {res.get('rc')} 이다 — 성공한 잡만 근거가 된다")
    if res.get("tool") != recipe["tool"]:
        raise StmcError(f"근거 잡의 도구 {res.get('tool')!r} 가 레시피 도구 {recipe['tool']!r} 와 다르다")
    wdir = os.path.join(job_dir, "work")
    runtime = {k: evidence.get(k) for k in ("target", "extra_inputs")}
    family = _specs()[recipe["tool"]]["family"]
    if family in ("kmm", "kmm_chain"):
        model = evidence.get("model_path")
        if not model:
            try:
                with open(os.path.join(wdir, "stmc_options.txt"), encoding="utf-8") as f:
                    lines = f.read().splitlines()
                model = os.path.join(wdir, lines[lines.index("*Inputfile") + 1].strip())
            except (OSError, ValueError, IndexError):
                raise StmcError("근거 잡 work/stmc_options.txt 에서 모델 이름을 못 읽었다 — evidence.model_path 를 줄 것")
        runtime["model_path"] = model
    elif family == "post" and not evidence.get("target") and _specs()[recipe["tool"]].get("target", {}).get("required"):
        raise StmcError("후처리 레시피의 evidence 에는 그 잡의 target(분석한 결과 경로)을 줄 것")
    args = run_args(recipe, evidence.get("params"), runtime)
    got = capture(recipe["tool"], args)
    mismatched = []
    for name, text in sorted(got["texts"].items()):
        try:
            with open(os.path.join(wdir, name), encoding="utf-8") as f:
                if f.read() != text:
                    mismatched.append(name)
        except OSError:
            mismatched.append(name + " (근거 잡에 없음)")
    argv = [a.replace(WORK, wdir) for a in got["argv"]]
    if argv != list(res.get("argv") or []):
        mismatched.append("argv")
    if mismatched:
        raise StmcError(f"레시피를 근거 매개변수로 펼친 입력이 근거 잡과 다르다: {', '.join(mismatched)} — "
                        f"그 잡의 인자를 그대로 틀로 옮기고 바뀌는 값만 {{{{이름}}}} 자리로 둘 것")
    return {"result_dir": job_dir, "registry_id": (row or {}).get("id"), "tool": res.get("tool"), "rc": 0,
            "params": resolve_params(recipe["params"], evidence.get("params")), "note": note,
            "compared": sorted(got["texts"]) + ["argv"]}


# ── 저장소 ───────────────────────────────────────────────────────────────────────

def _sha(recipe: dict) -> str:
    """판의 내용 해시 — 실행 내용(도구·매개변수·인자 틀)과 설명(요약·설명·태그). 근거·만든 이·시각은 뺀다."""
    core = {k: recipe[k] for k in ("tool", "params", "args", "summary", "description", "tags")}
    return hashlib.sha256(json.dumps(core, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


@contextmanager
def _locked(name: str):
    d = root() / name
    d.mkdir(parents=True, exist_ok=True)
    with open(d / ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            yield d
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)


def _versions(d: Path) -> list[int]:
    return sorted(int(p.stem) for p in d.glob("*.yaml") if p.stem.isdigit())


def _read(path: Path) -> dict:
    import yaml
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _write(path: Path, doc: dict) -> None:
    import yaml
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp_", suffix=".yaml")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False, default_flow_style=False)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def save(recipe: dict, evidence: dict, username: str) -> dict:
    """새 판으로 저장(내용이 마지막 판과 같으면 새 판을 만들지 않는다)."""
    sha = _sha(recipe)
    with _locked(recipe["name"]) as d:
        vers = _versions(d)
        if vers:
            last = _read(d / f"{vers[-1]}.yaml")
            if last.get("sha256") == sha and last.get("status") == "active":
                return {"saved": False, "unchanged": True, "version": vers[-1], "sha256": sha}
        ver = (vers[-1] + 1) if vers else 1
        doc = {"name": recipe["name"], "version": ver, "status": "active", "tool": recipe["tool"],
               "summary": recipe["summary"], "description": recipe["description"], "tags": recipe["tags"],
               "params": recipe["params"], "args": recipe["args"], "evidence": [evidence], "sha256": sha,
               "created_by": username, "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        _write(d / f"{ver}.yaml", doc)
    return {"saved": True, "version": ver, "sha256": sha}


def load(name: str, version: int | None = None) -> dict:
    if not NAME_RE.fullmatch(str(name)):
        raise StmcError(f"레시피 이름이 아니다: {name!r}")
    d = root() / name
    vers = _versions(d) if d.is_dir() else []
    if not vers:
        raise StmcError(f"레시피 {name} 가 없다 — recipe_list 로 찾을 것")
    if version is None:
        active = [v for v in vers if _read(d / f"{v}.yaml").get("status") == "active"]
        if not active:
            raise StmcError(f"레시피 {name} 의 쓸 수 있는 판이 없다(모두 내려졌다) — version 을 주면 옛 판을 본다")
        version = active[-1]
    p = d / f"{int(version)}.yaml"
    if not p.is_file():
        raise StmcError(f"레시피 {name} 에 판 {version} 이 없다(있는 판: {vers})")
    return _read(p)


def list_all(query: str | None = None, tool: str | None = None, include_retired: bool = False) -> list[dict]:
    out = []
    base = root()
    if not base.is_dir():
        return out
    words = [w for w in (query or "").lower().split() if w]
    for d in sorted(p for p in base.iterdir() if p.is_dir() and NAME_RE.fullmatch(p.name)):
        docs = [_read(d / f"{v}.yaml") for v in _versions(d)]
        if not include_retired:
            docs = [x for x in docs if x.get("status") == "active"]
        if not docs:
            continue
        last = docs[-1]
        if tool and last.get("tool") != tool:
            continue
        hay = " ".join([last.get("name", ""), last.get("summary", ""), last.get("description", ""), last.get("tool", ""),
                        " ".join(last.get("tags") or [])]).lower()
        if words and not all(w in hay for w in words):
            continue
        out.append({"name": last["name"], "version": last["version"], "status": last.get("status"),
                    "tool": last["tool"], "summary": last.get("summary"), "tags": last.get("tags") or [],
                    "params": {k: {kk: vv for kk, vv in v.items() if kk in ("type", "default", "description")}
                               for k, v in (last.get("params") or {}).items()},
                    "versions": [x["version"] for x in docs], "created_by": last.get("created_by")})
    return out


def retire(name: str, version: int, reason: str, username: str) -> dict:
    if not str(reason or "").strip():
        raise StmcError("reason(왜 내리는지)이 필요하다")
    with _locked(name) as d:
        p = d / f"{int(version)}.yaml"
        if not p.is_file():
            raise StmcError(f"레시피 {name} 에 판 {version} 이 없다")
        doc = _read(p)
        if doc.get("created_by") != username:
            raise StmcError(f"레시피 {name} 판 {version} 은 {doc.get('created_by')} 가 만들었다 — 만든 사람만 내릴 수 있다")
        if doc.get("status") == "retired":
            return {"retired": False, "already": True, "version": int(version)}
        doc.update(status="retired", retired_by=username, retired_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                   retired_reason=str(reason).strip())
        _write(p, doc)
    return {"retired": True, "version": int(version)}
