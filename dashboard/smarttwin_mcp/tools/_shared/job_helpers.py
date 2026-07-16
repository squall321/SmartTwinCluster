#!/usr/bin/env python3
"""Shared helpers for follow-up MCP tools (job_status, job_stop, etc).

Pattern: resolve registry_id|work_dir → runner_config_path → call KooChainRun subcommand.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Any

import registry


KOOCHAINRUN = "/data/SmartTwinPreprocessor/bin/KooChainRun"


def backend_submit(template_id, files, tool_name, project_name,
                   job_name=None, slurm_overrides=None, image=None,
                   num_angles=None, dry_run=False):
    """(C) 하이브리드: 입력은 로컬에서 준비하고, 최종 제출은 backend_5010 /api/jobs/submit 로.

    요청 PAT(STMC_CLUSTER_TOKEN, 프레임워크가 주입)로 권한/감사를 지나고, backend 드라이버가
    sinfo+DOE 로 병렬도 auto-tune(클러스터 인식) 하므로 도구가 네이티브 auto-tune 을 중복할
    필요가 없다. 받은 job_id 를 로컬 registry 에 기록해 job_status/job_stop 이 찾게 한다.

    Args:
        files: {file_key: 절대경로}. 템플릿 input_schema 의 키 (예: {"model_k": ...,
               "scenario_json": ...} 또는 {"input_k": ...}). 폼필드는 file_<key>.
        image: apptainer 이미지 id(이미지 필요 템플릿). slurm_overrides: #SBATCH 오버라이드.
    반환 dict: {ok, http, job_id, registry_id, response} (dry_run 이면 sbatch_preview).
    """
    import uuid
    import urllib.request
    import urllib.error

    base = (os.environ.get("STMC_CLUSTER_URL") or "").rstrip("/")
    token = os.environ.get("STMC_CLUSTER_TOKEN") or ""
    if not base or not token:
        return {"ok": False, "error": "제출은 backend 를 경유합니다 — STMC_CLUSTER_URL(서버 env) 과 "
                                      "요청 PAT(Authorization) 가 필요합니다(fail-closed)."}

    boundary = "----stmc" + uuid.uuid4().hex

    def _field(n, v):
        return (f'--{boundary}\r\nContent-Disposition: form-data; name="{n}"\r\n\r\n{v}\r\n').encode()

    def _filep(n, fn, data):
        return ((f'--{boundary}\r\nContent-Disposition: form-data; name="{n}"; filename="{fn}"\r\n'
                 f'Content-Type: application/octet-stream\r\n\r\n').encode() + data + b"\r\n")

    body = bytearray()
    body += _field("template_id", template_id)
    body += _field("slurm_overrides", json.dumps(slurm_overrides or {}))
    if job_name:
        body += _field("job_name", job_name)
    if image:
        body += _field("apptainer_image_id", str(image))
    path = "/api/jobs/preview" if dry_run else "/api/jobs/submit"
    if not dry_run:
        for key, fpath in (files or {}).items():
            safe = "".join(c for c in str(key) if c.isalnum() or c == "_")
            with open(fpath, "rb") as f:
                fname = "scenario.json" if safe == "scenario_json" else os.path.basename(fpath)
                body += _filep(f"file_{safe}", fname, f.read())
    body += (f'--{boundary}--\r\n').encode()

    req = urllib.request.Request(
        base + path, data=bytes(body), method="POST",
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw, code = r.read().decode("utf-8", "replace"), r.status
    except urllib.error.HTTPError as e:
        raw, code = e.read().decode("utf-8", "replace"), e.code
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"backend 요청 실패: {e}"}

    try:
        data = json.loads(raw)
    except ValueError:
        data = {"raw": raw[:500]}

    if dry_run:
        script = (data.get("script") or "") if isinstance(data, dict) else ""
        sbatch = "\n".join(l for l in script.splitlines() if l.startswith("#SBATCH"))
        return {"ok": 200 <= code < 300, "dry_run": True, "http": code, "sbatch_preview": sbatch or data}

    job_id = data.get("job_id") if isinstance(data, dict) else None
    if not (200 <= code < 300 and job_id):
        return {"ok": False, "http": code, "error": "제출 실패", "response": data}

    reg_id = None
    try:
        user = "unknown"
        mreq = urllib.request.Request(base + "/api/me", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(mreq, timeout=15) as mr:
            user = json.loads(mr.read().decode("utf-8", "replace")).get("username") or "unknown"
        name = job_name or project_name
        wd = f"/data/single/{user}/{name}_{job_id}"
        reg_id = registry.record_submission(
            tool_name=tool_name, work_dir=wd, output_dir=wd + "/output",
            project_name=project_name, runner_config_path=wd + "/output/runner_config.json",
            slurm_job_ids=[str(job_id)], num_angles=num_angles)
    except Exception:  # noqa: BLE001
        pass
    return {"ok": True, "http": code, "job_id": job_id, "registry_id": reg_id, "response": data}


def resolve_job(args: dict) -> dict | None:
    """Look up job by registry_id or work_dir.

    Returns the registry row dict on success, or None if not found.

    Ambiguous work_dir: if more than one row matches the exact work_dir,
    the FIRST (newest by submitted_at DESC) is returned silently. Callers
    that care about ambiguity should query `registry.list_recent` directly
    and decide policy.
    """
    if "registry_id" in args:
        return registry.get_by_id(int(args["registry_id"]))
    if "work_dir" in args:
        wd = args["work_dir"].rstrip("/")
        rows = [r for r in registry.list_recent(limit=500)
                if r.get("work_dir", "").rstrip("/") == wd]
        if rows:
            return rows[0]
    return None


def fail(reason: str, **extra):
    print(json.dumps({"ok": False, "reason": reason, **extra}, ensure_ascii=False))
    sys.exit(1)


def run_koochainrun(subcommand: str, *extra_args: str, timeout: int = 300) -> tuple[int, str, str]:
    """Run KooChainRun subcommand, return (rc, stdout, stderr)."""
    if not os.path.exists(KOOCHAINRUN):
        fail(f"KooChainRun not found at {KOOCHAINRUN}")
    cmd = [KOOCHAINRUN, subcommand, *extra_args]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        fail(f"KooChainRun {subcommand} timed out after {timeout}s")


def slurm_queue_for(slurm_job_ids: list[str]) -> dict:
    """Query squeue for the given Slurm job IDs."""
    if not slurm_job_ids:
        return {}
    try:
        r = subprocess.run(
            ["squeue", "-h", "-o", "%i %T %j %R", "-j", ",".join(slurm_job_ids)],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return {}
    out = {}
    for line in r.stdout.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) >= 2:
            out[parts[0]] = {
                "state": parts[1],
                "name": parts[2] if len(parts) > 2 else None,
                "reason": parts[3] if len(parts) > 3 else None,
            }
    return out
