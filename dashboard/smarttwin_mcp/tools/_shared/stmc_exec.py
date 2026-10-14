# SmartTwin 도구 공통 실행부 — 호출자 확인(/api/me)·backend 호출·입력 묶음·smarttwin-tool 잡 제출·결과 읽기
"""stmc_exec — SmartTwin 전처리·후처리 도구(kmm_*/kam_*/remap_*/post_*)와 backend 경유 도구가 같이 쓰는 실행부.

표준 라이브러리만 쓰고 모듈 상태를 두지 않는다(AGENT_GUIDE §9.5). 공개 API — §9.6 과 같게 유지할 것.

  StmcError(Exception)
      사용자에게 그대로 돌려줄 오류. fail-closed(토큰 없음·권한 없음)도 이것으로 낸다.

  backend_request(method, path, *, json_body=None, query=None, timeout=60) -> (status: int, data)
      STMC_CLUSTER_URL + `Authorization: Bearer $STMC_CLUSTER_TOKEN` 으로 backend_5010 호출.
      data = JSON 이면 파싱한 값, 아니면 {"raw": 본문 앞 2000자}. HTTP 오류 코드(4xx/5xx)는 예외가 아니라
      status 로 돌려준다. URL·토큰이 없거나 네트워크 오류면 StmcError(fail-closed).

  backend_multipart(path, fields, files, *, timeout=600) -> (status: int, data)
      같은 인증으로 multipart/form-data POST. files = {폼필드: (업로드 파일 이름, 로컬 경로)}.

  caller_identity(timeout=15) -> {"username": str, "role": str, "permissions": list, "groups": list, "raw": dict}
      GET /api/me. 토큰 없음·비 2xx·username 없음이면 StmcError(fail-closed).

  user_area(username) -> "/data/single/<username>"   (backend RESULT_DIR 규칙과 같다)
  input_roots(username) -> list[str]
      업로드해도 되는 입력의 루트. STMC_INPUT_ROOTS(콜론 구분, {user} 치환) — 기본
      "/data/single/{user}:/shared/uploads/users/{user}:/data/scenario".
  check_under(path, roots, *, kind="any") -> str
      realpath 가 roots 안이고 kind 에 맞으면 realpath, 아니면 StmcError.
      kind: "file"·"dir"·"any"(있어야 함) | "parent"(만들 파일 — 상위 폴더만 있으면 됨) | "new"(존재 검사 없음)
  work_roots(username) -> list[str]
      작업 폴더를 만들어도 되는 루트 — 호출자 영역 + STMC_WORK_ROOTS(콜론 구분, {user} 치환).
  prepare_model_workdir(work_dir, model_file, model_file_path, username) -> (작업 폴더, 모델, scenario.json)
      낙하 도구의 작업 폴더·모델 준비(경로 허용 루트, model_file 은 이름만, 심볼릭 링크 거절).

  Bundle(roots)                         업로드할 입력 묶음(roots=None 이면 파일시스템을 보지 않는 미리보기)
      .add_file(path) -> 묶음 안 이름     (이름 충돌·허용 범위 밖이면 StmcError)
      .add_text(name, text) -> name
      .rewrite_paths(obj) -> obj          문자열 중 파일을 가리키는 절대경로를 묶음에 넣고 이름으로 바꾼다
      .listing() -> [{"name", "source"|"text_bytes"}]
      .pack(dest_dir) -> inputs.tgz 경로 | None

  WORK = "@@WORK@@"  잡 안 작업 폴더 자리표시자(템플릿 디스패처가 치환). work(name) -> "@@WORK@@/<name>"

  submit_tool_job(*, tool, family, binary, argv, bundle, cwd="work", existing_dir=None,
                  slurm=None, job_name=None, dry_run=False, wait_sec=0) -> dict
      smarttwin-tool 템플릿으로 잡 하나를 제출(dry_run 이면 요청만 돌려준다). registry·audit 기록.

  read_result(result_dir, *, inline_limit=32768) -> dict
  wait_result(result_dir, wait_sec, *, poll=5) -> dict | None
  safe_job_name(text) -> str   backend RESULT_DIR 규칙과 어긋나지 않는 ASCII 잡 이름

  submit_scenario_job(*, tool, scenario, model_bundle, model_name, aux_bundle, workflow, job_name=None,
                      dry_run=False, identity=None, driver_mem=None) -> dict
      KooChainRun 캠페인 하나를 smarttwin-scenario(DWI 는 smarttwin-partial-impact) 드라이버 잡으로 제출.

  find_owned_job(args, username) -> (잡 폴더 realpath, registry 행 | None)
      args 의 registry_id·job_id·work_dir 로 찾고 호출자 영역 밖이면 StmcError.
  campaign_dir(job_dir, row=None) -> runner_config.json 이 있는 KooChainRun 테스트 폴더
  campaign_queue(test_dir) -> ({잡ID: {state, reason, command}}, [남의 잡 ID])
      jobs.json 의 잡 중 큐에 있는 것. command(배치 스크립트)가 test_dir 밖이면 남의 잡 — scontrol 전에 거른다.
"""
from __future__ import annotations

import io
import json
import os
import re
import shutil
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

WORK = "@@WORK@@"
TOOL_TEMPLATE_ID = "smarttwin-tool"
DEFAULT_INPUT_ROOTS = "/data/single/{user}:/shared/uploads/users/{user}:/data/scenario"
_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_USER_RE = re.compile(r"^[A-Za-z0-9._-]{1,32}$")
_TEXT_SUFFIXES = (".json", ".txt", ".log", ".csv", ".yaml", ".yml", ".md", ".msg", ".out", ".dat")


class StmcError(Exception):
    """사용자에게 그대로 돌려줄 오류."""


def work(name: str) -> str:
    return f"{WORK}/{name}"


# ── backend 호출 ────────────────────────────────────────────────────────────────

def _base_and_token() -> tuple[str, str]:
    base = (os.environ.get("STMC_CLUSTER_URL") or "").rstrip("/")
    token = os.environ.get("STMC_CLUSTER_TOKEN") or ""
    if not base:
        raise StmcError("STMC_CLUSTER_URL 이 서버 env 에 없다 — backend 를 경유하는 도구라 실행할 수 없다(fail-closed).")
    if not token:
        raise StmcError("요청에 PAT(Authorization: Bearer kst_…)가 없다 — 이 작업은 호출자 권한으로만 실행된다(fail-closed).")
    return base, token


def _decode(raw: bytes):
    text = raw.decode("utf-8", "replace")
    try:
        return json.loads(text)
    except ValueError:
        return {"raw": text[:2000]}


def backend_request(method: str, path: str, *, json_body=None, query: dict | None = None,
                    timeout: int = 60):
    base, token = _base_and_token()
    url = base + path
    if query:
        url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
    data = None
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if json_body is not None:
        data = json.dumps(json_body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method.upper(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, _decode(r.read())
    except urllib.error.HTTPError as e:
        return e.code, _decode(e.read() if e.fp else b"")
    except Exception as e:  # noqa: BLE001
        raise StmcError(f"backend 요청 실패({method} {path}): {e}") from e


def backend_multipart(path: str, fields: dict, files: dict, *, timeout: int = 600):
    base, token = _base_and_token()
    boundary = "----stmc" + uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n'
                 f"{value}\r\n").encode("utf-8")
    for field, (filename, local_path) in files.items():
        with open(local_path, "rb") as f:
            payload = f.read()
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; '
                 f'filename="{filename}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode("utf-8")
        body += payload + b"\r\n"
    body += f"--{boundary}--\r\n".encode("utf-8")
    req = urllib.request.Request(base + path, data=bytes(body), method="POST", headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, _decode(r.read())
    except urllib.error.HTTPError as e:
        return e.code, _decode(e.read() if e.fp else b"")
    except Exception as e:  # noqa: BLE001
        raise StmcError(f"backend 요청 실패(POST {path}): {e}") from e


def caller_identity(timeout: int = 15) -> dict:
    status, data = backend_request("GET", "/api/me", timeout=timeout)
    if not (200 <= status < 300) or not isinstance(data, dict):
        raise StmcError(f"호출자 확인 실패(/api/me http={status}) — PAT 가 유효한지 확인할 것(fail-closed).")
    username = data.get("username")
    if not username or not _USER_RE.fullmatch(str(username)):
        raise StmcError("호출자 확인 실패 — /api/me 응답에 쓸 수 있는 username 이 없다(fail-closed).")
    return {"username": str(username), "role": data.get("role") or "user",
            "permissions": list(data.get("permissions") or []),
            "groups": list(data.get("groups") or []), "raw": data}


# ── 경로 정책 ───────────────────────────────────────────────────────────────────

def user_area(username: str) -> str:
    return f"/data/single/{username}"


def input_roots(username: str) -> list[str]:
    spec = os.environ.get("STMC_INPUT_ROOTS", DEFAULT_INPUT_ROOTS)
    return [r.replace("{user}", username) for r in spec.split(":") if r.strip()]


def work_roots(username: str) -> list[str]:
    """작업 폴더(쓰기)를 만들어도 되는 루트 — 호출자 영역 + STMC_WORK_ROOTS(콜론 구분, {user} 치환)."""
    extra = os.environ.get("STMC_WORK_ROOTS", "")
    return [user_area(username)] + [r.replace("{user}", username) for r in extra.split(":") if r.strip()]


def prepare_model_workdir(work_dir: str, model_file: str, model_file_path: str | None,
                          username: str) -> tuple[str, str, str]:
    """낙하 도구(fullangle·single)의 작업 폴더와 모델을 준비한다 → (작업 폴더, 모델 경로, scenario.json 경로).

    작업 폴더는 work_roots 안, 모델 원본(model_file_path)은 input_roots 안, model_file 은 파일 이름만.
    작업 폴더에 모델이 이미 있으면 그대로 쓴다(예전 동작). 모델·scenario.json 자리가 심볼릭 링크면 거절한다 —
    링크를 따라 허용 범위 밖을 읽거나 쓰지 않게."""
    if not isinstance(model_file, str) or not _NAME_RE.fullmatch(model_file):
        raise StmcError(f"model_file 은 파일 이름만 쓸 수 있다(영문·숫자·._-): {model_file!r}")
    wd = check_under(work_dir, work_roots(username), kind="new")
    os.makedirs(wd, exist_ok=True)
    target, scenario_path = os.path.join(wd, model_file), os.path.join(wd, "scenario.json")
    for p in (target, scenario_path):
        if os.path.islink(p):
            raise StmcError(f"작업 폴더 안의 심볼릭 링크는 쓰지 않는다: {p}")
    if not os.path.isfile(target):
        if not model_file_path:
            raise StmcError(f"모델이 없다: {target} — 업로드한 파일 경로를 model_file_path 로 줄 것")
        shutil.copyfile(check_under(model_file_path, input_roots(username), kind="file"), target)
    return wd, target, scenario_path


def _inside(path: str, roots: list[str]) -> bool:
    for r in roots:
        rr = os.path.realpath(r)
        if path == rr or path.startswith(rr.rstrip("/") + "/"):
            return True
    return False


def check_under(path: str, roots: list[str], *, kind: str = "any") -> str:
    if not isinstance(path, str) or not path.startswith("/"):
        raise StmcError(f"절대경로가 아니다: {path!r}")
    real = os.path.realpath(path)
    if not _inside(real, roots):
        raise StmcError(f"허용 범위 밖의 경로다: {path} (허용: {', '.join(roots)})")
    if kind == "file" and not os.path.isfile(real):
        raise StmcError(f"파일이 없다: {path}")
    if kind == "dir" and not os.path.isdir(real):
        raise StmcError(f"폴더가 없다: {path}")
    if kind == "any" and not os.path.exists(real):
        raise StmcError(f"경로가 없다: {path}")
    if kind == "parent" and not os.path.isdir(os.path.dirname(real)):
        raise StmcError(f"상위 폴더가 없다: {path}")
    return real


# ── 입력 묶음 ───────────────────────────────────────────────────────────────────

class Bundle:
    """잡 work/ 폴더로 올라갈 입력. roots=None 이면 파일시스템을 보지 않는 미리보기(dry_run, PAT 없음)."""

    def __init__(self, roots: list[str] | None):
        self.roots = roots
        self.files: dict[str, str] = {}
        self.texts: dict[str, str] = {}

    def _claim(self, name: str, source: str | None) -> None:
        if not _NAME_RE.fullmatch(name):
            raise StmcError(f"입력 파일 이름을 쓸 수 없다: {name!r} (영문·숫자·._- 만)")
        if name in self.texts or (name in self.files and self.files[name] != source):
            raise StmcError(f"입력 파일 이름이 겹친다: {name} — 다른 이름으로 바꿔서 줄 것")

    def add_file(self, path: str) -> str:
        if self.roots is None:
            real = os.path.normpath(path)
        else:
            real = check_under(path, self.roots, kind="file")
        name = os.path.basename(real)
        self._claim(name, real)
        self.files[name] = real
        return name

    def add_text(self, name: str, text: str) -> str:
        self._claim(name, None)
        self.texts[name] = text
        return name

    def _looks_like_file(self, s: str) -> bool:
        if self.roots is None:
            return "." in os.path.basename(s)
        return os.path.isfile(os.path.realpath(s))

    def rewrite_paths(self, obj, *, prefix: str = ""):
        """obj(dict/list/str) 안에서 실제 파일을 가리키는 절대경로를 묶음에 넣고 `prefix+이름` 으로 바꾼다.
        파일이 아닌 절대경로(폴더 등)는 그대로 둔다 — 디스패처가 허용 범위를 다시 검사한다."""
        if isinstance(obj, dict):
            return {k: self.rewrite_paths(v, prefix=prefix) for k, v in obj.items()}
        if isinstance(obj, list):
            return [self.rewrite_paths(v, prefix=prefix) for v in obj]
        if isinstance(obj, str) and obj.startswith("/") and not obj.startswith(("/opt/",)) \
                and self._looks_like_file(obj):
            return prefix + self.add_file(obj)
        return obj

    def listing(self) -> list[dict]:
        out = [{"name": n, "source": p} for n, p in sorted(self.files.items())]
        out += [{"name": n, "text_bytes": len(t.encode("utf-8"))} for n, t in sorted(self.texts.items())]
        return out

    def pack(self, dest_dir: str) -> str | None:
        if not self.files and not self.texts:
            return None
        out = os.path.join(dest_dir, "inputs.tgz")
        with tarfile.open(out, "w:gz") as tf:
            for name, src in sorted(self.files.items()):
                tf.add(src, arcname=name, recursive=False)
            for name, text in sorted(self.texts.items()):
                data = text.encode("utf-8")
                ti = tarfile.TarInfo(name)
                ti.size = len(data)
                ti.mtime = int(time.time())
                ti.mode = 0o644
                tf.addfile(ti, io.BytesIO(data))
        return out


# ── 제출·결과 ───────────────────────────────────────────────────────────────────

def safe_job_name(text: str) -> str:
    """backend 의 두 정규화(job_name, RESULT_DIR)가 같은 결과를 내도록 ASCII 만 남긴다."""
    name = re.sub(r"[^A-Za-z0-9._-]", "_", str(text or "stmc"))[:48].strip("._-")
    return name or "stmc"


# 패밀리별 기본 자원 — 클러스터의 가장 큰 노드에 맞춰 줄인다(_fit_to_cluster).
FAMILY_SLURM_DEFAULTS = {"kmm": {"cpus_per_task": 2, "mem": "8G"}, "kam": {"cpus_per_task": 2, "mem": "8G"},
                         "remap": {"cpus_per_task": 2, "mem": "8G"}, "post": {"cpus_per_task": 4, "mem": "16G"}}


def _mem_mb(v: str) -> int:
    return int(v[:-1]) * (1024 if v.endswith("G") else 1)


def _cluster_limits(partition: str | None) -> tuple[int, int] | None:
    """sinfo 로 (노드당 최대 CPU, 최대 메모리 MB) — 지정 파티션, 없으면 기본 파티션. 못 읽으면 None."""
    import subprocess
    cmd = ["sinfo", "-h", "-o", "%P %c %m"] + (["-p", partition] if partition else [])
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except Exception:  # noqa: BLE001
        return None
    best = None
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3 or not parts[1].rstrip("+").isdigit() or not parts[2].rstrip("+").isdigit():
            continue
        # 파티션을 안 주면 잡은 기본 파티션(sinfo 에 '*' 표시)으로 간다 — 그 노드 크기만 본다.
        if not partition and not parts[0].endswith("*"):
            continue
        cpu, mem = int(parts[1].rstrip("+")), int(parts[2].rstrip("+"))
        best = (cpu, mem) if best is None else (max(best[0], cpu), max(best[1], mem))
    return best


def _fit_to_cluster(overrides: dict, family: str, notes: list) -> dict:
    out = {**FAMILY_SLURM_DEFAULTS.get(family, {}), **overrides}
    lim = _cluster_limits(out.get("partition"))
    if lim:
        cpu, mem = lim
        if int(out.get("cpus_per_task", 1)) > cpu:
            notes.append(f"cpus_per_task {out['cpus_per_task']} → {cpu} (노드 최대)")
            out["cpus_per_task"] = cpu
        if "mem" in out and _mem_mb(out["mem"]) > mem:
            notes.append(f"mem {out['mem']} → {mem}M (노드 최대)")
            out["mem"] = f"{mem}M"
    return out


def _slurm_overrides(slurm: dict | None) -> dict:
    out = {}
    for key, pattern in (("cpus_per_task", r"^[0-9]{1,3}$"), ("mem", r"^[0-9]{1,6}[MG]$"),
                         ("time", r"^[0-9]{1,3}:[0-5][0-9]:[0-5][0-9]$"),
                         ("partition", r"^[A-Za-z0-9_-]{1,32}$")):
        if slurm and slurm.get(key) not in (None, ""):
            v = str(slurm[key])
            if not re.fullmatch(pattern, v):
                raise StmcError(f"slurm.{key} 값이 형식에 맞지 않는다: {v!r}")
            out[key] = int(v) if key == "cpus_per_task" else v
    return out


def submit_tool_job(*, tool: str, family: str, binary: str, argv: list[str], bundle: Bundle,
                    cwd: str = "work", existing_dir: str | None = None, slurm: dict | None = None,
                    job_name: str | None = None, dry_run: bool = False, wait_sec: int = 0,
                    identity: dict | None = None) -> dict:
    request = {"schema": "stmc-tool/1", "tool": tool, "family": family, "binary": binary,
               "argv": list(argv), "cwd": cwd, "existing_dir": existing_dir,
               "texts": sorted(bundle.texts)}
    slurm_notes: list[str] = []
    overrides = _fit_to_cluster(_slurm_overrides(slurm), family, slurm_notes)
    name = safe_job_name(job_name or f"stmc_{tool}")
    if dry_run:
        return {"ok": True, "dry_run": True, "tool": tool, "request": request,
                "inputs": bundle.listing(),
                "texts": {n: (t if len(t) <= 20000 else t[:20000] + "\n…(잘림)") for n, t in bundle.texts.items()},
                "slurm_overrides": overrides, "slurm_notes": slurm_notes, "job_name": name,
                "note": ("제출하지 않았다. dry_run=false 로 다시 부르면 smarttwin-tool 잡 하나가 backend 를 거쳐 "
                         "호출자 권한으로 제출된다." + ("" if bundle.roots is not None else
                         " PAT 가 없어 경로는 아직 검사하지 않았다 — 제출 때 사용자 영역 기준으로 검사한다."))}

    ident = identity or caller_identity()
    user = ident["username"]
    if cwd == "existing":
        existing_dir = check_under(existing_dir or "", [user_area(user)], kind="dir")
        request["existing_dir"] = existing_dir
    with tempfile.TemporaryDirectory(prefix="stmc_") as td:
        req_path = os.path.join(td, "request.json")
        with open(req_path, "w", encoding="utf-8") as f:
            json.dump(request, f, ensure_ascii=False)
        files = {"file_request_json": ("request.json", req_path)}
        tgz = bundle.pack(td)
        if tgz:
            files["file_inputs_tgz"] = ("inputs.tgz", tgz)
        status, data = backend_multipart("/api/jobs/submit", {
            "template_id": TOOL_TEMPLATE_ID, "job_name": name,
            "slurm_overrides": json.dumps(overrides)}, files)
    job_id = data.get("job_id") if isinstance(data, dict) else None
    if not (200 <= status < 300 and job_id):
        return {"ok": False, "tool": tool, "http": status, "error": "backend 제출 실패", "response": data}

    result_dir = f"{user_area(user)}/{name}_{job_id}"
    out = {"ok": True, "tool": tool, "job_id": str(job_id), "result_dir": result_dir,
           "slurm_overrides": overrides, "slurm_notes": slurm_notes,
           "work_dir": existing_dir if cwd == "existing" else result_dir + "/work",
           "submitted_by": user, "registry_id": None}
    try:  # registry·audit 는 제출을 막지 않는다(실패해도 잡은 이미 나갔다)
        import registry
        out["registry_id"] = registry.record_submission(
            tool_name=tool, work_dir=result_dir, output_dir=out["work_dir"], project_name=tool,
            slurm_job_ids=[str(job_id)],
            extra={"kind": TOOL_TEMPLATE_ID, "family": family, "binary": binary, "web_user": user})
    except Exception:  # noqa: BLE001
        pass
    try:
        import audit
        audit.record_event(actor=user, tool=tool, action="submit",
                           summary=f"{tool}: {binary} via {TOOL_TEMPLATE_ID} -> job {job_id}",
                           target_kind="job", target_id=str(out["registry_id"] or job_id),
                           detail={"family": family, "binary": binary, "argv": argv[:40],
                                   "result_dir": result_dir})
    except Exception:  # noqa: BLE001
        pass
    if wait_sec and wait_sec > 0:
        res = wait_result(result_dir, int(wait_sec))
        out["result"] = res if res is not None else {"state": "pending",
                                                     "note": f"{wait_sec}초 안에 끝나지 않았다 — tool_result 로 다시 볼 것"}
    out["follow_up_hint"] = (f"tool_result(job_id={job_id}) 로 상태·산출물을 본다. 결과 폴더 {result_dir} "
                             f"(stmc_result.json · work/ · stmc_stdout.log).")
    return out


def _tail(path: str, n: int = 4000) -> str:
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - n))
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def read_result(result_dir: str, *, inline_limit: int = 32768) -> dict:
    path = os.path.join(result_dir, "stmc_result.json")
    if not os.path.isfile(path):
        return {"state": "pending", "result_dir": result_dir,
                "note": "아직 시작 전이거나 큐 대기 중이다(stmc_result.json 없음)."}
    try:
        with open(path, encoding="utf-8") as f:
            res = json.load(f)
    except ValueError:
        return {"state": "unknown", "result_dir": result_dir, "note": "stmc_result.json 을 읽지 못했다."}
    res["result_dir"] = result_dir
    res["stdout_tail"] = _tail(os.path.join(result_dir, "stmc_stdout.log"))
    res["stderr_tail"] = _tail(os.path.join(result_dir, "stmc_stderr.log"), 2000)
    inline = {}
    for o in res.get("outputs") or []:
        p, size = o.get("path", ""), o.get("size", 0)
        if len(inline) >= 8 or not p.lower().endswith(_TEXT_SUFFIXES) or size > inline_limit:
            continue
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                inline[p] = f.read()
        except OSError:
            continue
    res["inline_outputs"] = inline
    return res


def wait_result(result_dir: str, wait_sec: int, *, poll: int = 5) -> dict | None:
    deadline = time.time() + max(0, int(wait_sec))
    while True:
        res = read_result(result_dir)
        if res.get("state") == "done":
            return res
        if time.time() >= deadline:
            return None
        time.sleep(poll)


# ── KooChainRun 시나리오 잡 (smarttwin-scenario / smarttwin-partial-impact 드라이버) ──────────────

SCENARIO_TEMPLATE_ID = "smarttwin-scenario"
DWI_TEMPLATE_ID = "smarttwin-partial-impact"


def submit_scenario_job(*, tool: str, scenario: dict, model_bundle: Bundle, model_name: str,
                        aux_bundle: Bundle, workflow: str | None, job_name: str | None = None,
                        dry_run: bool = False, identity: dict | None = None, driver_mem: str | None = None) -> dict:
    """KooChainRun 캠페인 하나를 드라이버 잡으로 제출한다. DWI 는 smarttwin-partial-impact(보조 입력 없음)."""
    template_id = DWI_TEMPLATE_ID if workflow == "drop_weight_impact" else SCENARIO_TEMPLATE_ID
    if template_id == DWI_TEMPLATE_ID and (aux_bundle.files or aux_bundle.texts):
        raise StmcError("drop_weight_impact 는 보조 입력(aux_inputs)을 받지 않는다")
    name = safe_job_name(job_name or f"stmc_{tool}")
    if dry_run:
        return {"ok": True, "dry_run": True, "tool": tool, "template_id": template_id, "job_name": name,
                "scenario": scenario, "inputs": model_bundle.listing() + aux_bundle.listing(),
                "note": ("제출하지 않았다. dry_run=false 면 드라이버 잡 하나가 prepare→submit→자식 잡 대기→collect"
                         "→(postprocess) 를 호출자 권한으로 돈다." + ("" if model_bundle.roots is not None else
                         " PAT 가 없어 경로는 아직 검사하지 않았다."))}
    ident = identity or caller_identity()
    user = ident["username"]
    with tempfile.TemporaryDirectory(prefix="stmc_sc_") as td:
        sp = os.path.join(td, "scenario.json")
        with open(sp, "w", encoding="utf-8") as f:
            json.dump(scenario, f, indent=2, ensure_ascii=False)
        files = {"file_model_k": (model_name, model_bundle.files[model_name]),
                 "file_scenario_json": ("scenario.json", sp)}
        tgz = aux_bundle.pack(td)
        if tgz:
            files["file_aux_tgz"] = ("aux.tgz", tgz)
        drv = {"mem": driver_mem} if driver_mem and template_id == SCENARIO_TEMPLATE_ID else {}
        status, data = backend_multipart("/api/jobs/submit", {"template_id": template_id, "job_name": name,
                                                              "slurm_overrides": json.dumps(drv)}, files)
    job_id = data.get("job_id") if isinstance(data, dict) else None
    if not (200 <= status < 300 and job_id):
        return {"ok": False, "tool": tool, "http": status, "error": "backend 제출 실패", "response": data}
    result_dir = f"{user_area(user)}/{name}_{job_id}"
    out = {"ok": True, "tool": tool, "template_id": template_id, "job_id": str(job_id), "result_dir": result_dir,
           "submitted_by": user, "registry_id": None}
    try:
        import registry
        out["registry_id"] = registry.record_submission(
            tool_name=tool, work_dir=result_dir, output_dir=result_dir + "/output", project_name=name,
            runner_config_path=result_dir + "/runner_config.json", slurm_job_ids=[str(job_id)],
            extra={"kind": template_id, "workflow": workflow or "cumulative", "web_user": user})
    except Exception:  # noqa: BLE001
        pass
    try:
        import audit
        audit.record_event(actor=user, tool=tool, action="submit",
                           summary=f"{tool}: KooChainRun 캠페인 via {template_id} -> job {job_id}",
                           target_kind="job", target_id=str(out["registry_id"] or job_id),
                           detail={"workflow": workflow or "cumulative", "result_dir": result_dir})
    except Exception:  # noqa: BLE001
        pass
    out["follow_up_hint"] = (f"드라이버 잡 {job_id} 이 자식 잡들을 낸다. job_status·job_collect·job_diagnose·job_stop 에 "
                             f"registry_id={out['registry_id']} 를 쓰고, 끝나면 post_* 도구를 {result_dir} 에 쓸 수 있다.")
    return out


# ── 후속 도구 (tool_result · job_reprioritize · job_harvest) ───────────────────────────────────

def find_owned_job(args: dict, username: str) -> tuple[str, dict | None]:
    """registry_id·job_id·work_dir 중 하나로 잡 폴더를 찾는다. 폴더는 호출자 영역(/data/single/<사용자>) 안이어야 한다.
    registry 로 찾은 폴더는 아직 없을 수 있다(큐 대기) — 그때는 상위 폴더만 확인한다."""
    import registry
    row = None
    if args.get("registry_id") is not None:
        row = registry.get_by_id(int(args["registry_id"]))
        if not row:
            raise StmcError(f"registry_id {args['registry_id']} 가 없다")
    elif args.get("job_id"):
        jid = str(args["job_id"])
        row = next((r for r in registry.list_recent(limit=5000) if jid in (r.get("slurm_job_ids") or [])), None)
        if not row:
            raise StmcError(f"job_id {jid} 를 registry 에서 못 찾았다 — work_dir 로 줄 것")
    elif not args.get("work_dir"):
        raise StmcError("registry_id·job_id·work_dir 중 하나가 필요하다")
    path = row["work_dir"] if row else args["work_dir"]
    return check_under(path, [user_area(username)], kind="parent" if row else "dir"), row


def campaign_dir(job_dir: str, row: dict | None = None) -> str:
    """runner_config.json 이 있는 KooChainRun 테스트 폴더(잡 폴더 자신 또는 그 output/)."""
    cands = [os.path.dirname(row["runner_config_path"])] if row and row.get("runner_config_path") else []
    for c in cands + [job_dir, os.path.join(job_dir, "output")]:
        real = os.path.realpath(c)
        if _inside(real, [job_dir]) and os.path.isfile(os.path.join(real, "runner_config.json")):
            return real
    raise StmcError(f"KooChainRun 캠페인 폴더가 아니다(runner_config.json 없음): {job_dir}")


def parse_squeue(text: str) -> dict:
    """`squeue -h -o %i|%T|%r|%o` 출력 → {잡ID: {state, reason, command}}."""
    out = {}
    for line in text.splitlines():
        parts = line.strip().split("|", 3)
        if len(parts) == 4 and parts[0].isdigit():
            out[parts[0]] = {"state": parts[1], "reason": parts[2], "command": parts[3]}
    return out


def campaign_queue(test_dir: str) -> tuple[dict, list[str]]:
    """jobs.json 의 잡 중 아직 큐에 있는 것과, 그중 이 캠페인 스크립트로 제출되지 않은 잡(남의 잡)을 돌려준다.
    jobs.json 은 사용자 폴더에 있어 손댈 수 있으므로 scontrol 을 걸기 전에 반드시 이것으로 걸러야 한다."""
    try:
        with open(os.path.join(test_dir, "jobs.json"), encoding="utf-8") as f:
            jobs = json.load(f).get("jobs", {})
    except (OSError, ValueError, AttributeError) as e:
        raise StmcError(f"jobs.json 을 읽지 못했다({test_dir}): {e}")
    ids = {str(j.get("job_id")) for j in (jobs.values() if isinstance(jobs, dict) else jobs)
           if isinstance(j, dict) and str(j.get("job_id", "")).isdigit()}
    import subprocess
    r = subprocess.run(["squeue", "-h", "-o", "%i|%T|%r|%o"], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise StmcError(f"squeue 실패: {r.stderr.strip()[:300]}")
    queued = {j: q for j, q in parse_squeue(r.stdout).items() if j in ids}
    foreign = sorted(j for j, q in queued.items()
                     if not _inside(os.path.realpath(q["command"]), [test_dir]))
    return queued, foreign
