#!/usr/bin/env bash
# 실 backend_5010 /api/jobs/submit 에 템플릿 기반 멀티파트 제출 (요청 PAT 패스스루)
# (C) 하이브리드: 제출은 backend(권한/감사) → 받은 job_id 를 로컬 registry 에 기록(다리).
set -euo pipefail
export SHARED_DIR="$(cd "$(dirname "$0")"/../../_shared && pwd)"
python3 - <<'PY'
import json, os, sys, uuid, urllib.request, urllib.error

sys.path.insert(0, os.environ.get("SHARED_DIR", ""))
try:
    import registry as _registry
except Exception:
    _registry = None


def fail(msg, **extra):
    print(json.dumps({"ok": False, "error": msg, **extra}, ensure_ascii=False))
    sys.exit(1)


args = json.loads(os.environ.get("STMC_ARGS_JSON") or "{}")
base = (os.environ.get("STMC_CLUSTER_URL") or "").rstrip("/")
token = os.environ.get("STMC_CLUSTER_TOKEN") or ""
if not base:
    fail("STMC_CLUSTER_URL 미설정(서버 env).")
if not token:
    fail("인증 토큰 없음 — 요청에 PAT(Authorization: Bearer kst_...) 가 필요합니다.")

tid = str(args.get("template_id") or "").strip()
if not tid:
    fail("template_id 는 필수입니다 (list_templates 로 확인).")
files = args.get("files") or {}
if not isinstance(files, dict):
    fail("files 는 {file_key: 절대경로} object 여야 합니다.")
job_name = str(args.get("job_name") or "")
overrides = args.get("slurm_overrides") or {}
image = str(args.get("image") or "").strip()
dry_run = bool(args.get("dry_run", True))

# ── 파일 경로 하드닝 (mcp_slurm _validate_shared_path 이식) ──
ALLOWED = ("/data", "/shared", "/mnt/gluster", "/home")
resolved = {}
for k, p in files.items():
    key = "".join(c for c in str(k) if c.isalnum() or c == "_")
    if not key:
        fail(f"file_key 형식 부적절: {k!r} (영숫자/_ 만).")
    if not p or not os.path.isabs(str(p)):
        fail(f"files['{k}'] 는 서버측 절대경로여야 합니다: {p!r}")
    real = os.path.realpath(str(p))
    if not any(real == b or real.startswith(b + "/") for b in ALLOWED):
        fail(f"files['{k}'] 는 공유 저장소({', '.join(ALLOWED)}) 하위여야 합니다: {real}")
    if not os.path.isfile(real):
        fail(f"files['{k}'] 파일이 없습니다: {real}")
    resolved[key] = real

# ── multipart/form-data 조립 (stdlib) ──
boundary = "----stmc" + uuid.uuid4().hex


def field(name, value):
    return (f'--{boundary}\r\n'
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode()


def filepart(name, filename, data):
    return ((f'--{boundary}\r\n'
             f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
             f'Content-Type: application/octet-stream\r\n\r\n').encode() + data + b'\r\n')


body = bytearray()
body += field("template_id", tid)
body += field("slurm_overrides", json.dumps(overrides))
if job_name:
    body += field("job_name", job_name)
if image:
    body += field("apptainer_image_id", image)

path = "/api/jobs/preview" if dry_run else "/api/jobs/submit"
if not dry_run:
    for key, real in resolved.items():
        with open(real, "rb") as fh:
            body += filepart(f"file_{key}", os.path.basename(real), fh.read())
body += (f'--{boundary}--\r\n').encode()

req = urllib.request.Request(
    base + path, data=bytes(body), method="POST",
    headers={"Authorization": f"Bearer {token}",
             "Content-Type": f"multipart/form-data; boundary={boundary}"},
)
try:
    with urllib.request.urlopen(req, timeout=590) as r:
        raw, code = r.read().decode("utf-8", "replace"), r.status
except urllib.error.HTTPError as e:
    raw, code = e.read().decode("utf-8", "replace"), e.code
except Exception as e:  # noqa: BLE001
    fail(f"backend 요청 실패: {e}")

try:
    data = json.loads(raw)
except ValueError:
    data = {"raw": raw[:500]}

if dry_run:
    script = (data.get("script") or "") if isinstance(data, dict) else ""
    sbatch = "\n".join(l for l in script.splitlines() if l.startswith("#SBATCH"))
    print(json.dumps({"ok": 200 <= code < 300, "dry_run": True, "http": code,
                      "template_id": tid, "sbatch_preview": sbatch or data},
                     ensure_ascii=False))
else:
    job_id = data.get("job_id") if isinstance(data, dict) else None
    reg_id = None
    reg_note = None
    if job_id and _registry is not None:
        # (C) 다리: backend 제출 잡을 로컬 registry 에 기록 → job_status/job_logs/job_stop 이 찾음.
        try:
            user = "unknown"
            mreq = urllib.request.Request(base + "/api/me",
                                          headers={"Authorization": f"Bearer {token}"})
            with urllib.request.urlopen(mreq, timeout=15) as mr:
                user = json.loads(mr.read().decode("utf-8", "replace")).get("username") or "unknown"
            name = job_name or tid
            wd = f"/data/single/{user}/{name}_{job_id}"
            reg_id = _registry.record_submission(
                tool_name="submit_job", work_dir=wd, output_dir=wd + "/output",
                project_name=name, runner_config_path=wd + "/output/runner_config.json",
                slurm_job_ids=[str(job_id)])
        except Exception as e:  # noqa: BLE001
            reg_note = f"registry 기록 실패(추적엔 job_id 사용): {e}"
    print(json.dumps({"ok": bool(200 <= code < 300 and job_id), "http": code,
                      "job_id": job_id, "registry_id": reg_id, "registry_note": reg_note,
                      "template_id": tid, "response": data,
                      "next": "job_status/job_logs/job_stop 에 registry_id 또는 job_id 사용"},
                     ensure_ascii=False))
PY
