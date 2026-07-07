#!/usr/bin/env python3
"""
Slurm MCP 서버 — 읽기전용 직접호출 + 변경계 REST 프록시 (HTTP/stdio 양용)

LLM 클라이언트(Claude Desktop, Claude Code 등)가 Slurm 클러스터를
조회(읽기) 및 제어(변경)할 수 있게 해주는 MCP 서버입니다.

transport (env MCP_TRANSPORT):
- 기본 'streamable-http'  — 원격 Claude Desktop/Code 가 mcp-remote 브리지로 접속(127.0.0.1:5012/mcp).
                            사용자별 PAT(kst_)를 Authorization 헤더로 받아 그 사용자 권한으로 동작.
- 'stdio'                 — 기존 동작(클라이언트가 로컬에서 spawn). 단일 사용자, SLURM_MCP_TOKEN env 사용.

인증 모델(★ReportArchive 방식★):
- MCP 서버는 인증을 스스로 판단하지 않는다. 들어온 요청의 Authorization 헤더를 그대로
  backend_5010 으로 전달하고, backend 가 PAT/JWT 를 검증해 **그 사용자 권한**으로 처리한다.
- 읽기 도구: slurm_commands 직접호출(빠르고 결합 적음)이지만, 먼저 backend `/api/me` 로
  토큰을 검증(게이트)한다. SSO off 모드면 backend 가 200(admin)을 주므로 자동 통과.
- 변경 도구: backend 의 변경계 REST(JWT/permission/감사 경계)를 HTTP 로 프록시. dry_run 기본 True.

실행:
    MCP_TRANSPORT=streamable-http ./venv/bin/python server.py   # 기본
    MCP_TRANSPORT=stdio          ./venv/bin/python server.py

환경변수:
    SLURM_BIN_DIR     - Slurm 바이너리 경로 (slurm_commands.py, 기본 /usr/local/slurm/bin)
    SLURM_MCP_BACKEND - backend REST 베이스 URL (기본 http://127.0.0.1:5010)
    SLURM_MCP_TOKEN   - stdio 모드 폴백 토큰(HTTP 모드는 요청 헤더 우선). 자세한 내용 README.
    MCP_TRANSPORT     - 'streamable-http'(기본) | 'stdio'
    MCP_HOST/MCP_PORT - HTTP 바인딩 (기본 127.0.0.1:5012)
    MCP_ALLOWED_HOSTS - 비-localhost 바인딩 시 허용 Host (쉼표구분). README 참고.
"""

import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, Optional

# ---------------------------------------------------------------------------
# 1) mcp 패키지 import 가드 (오프라인 환경에서 미설치일 수 있음)
# ---------------------------------------------------------------------------
try:
    from mcp.server.fastmcp import Context, FastMCP
except ImportError:
    sys.stderr.write(
        "[mcp_slurm] 'mcp' 패키지를 찾을 수 없습니다.\n"
        "  이 서버는 공식 MCP Python SDK 가 필요합니다.\n"
        "  설치: pip install mcp   (requirements.txt / install_offline.sh 참고)\n"
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2) backend_5010 의 slurm_commands.py 직접 import (검증된 래퍼 재사용)
# ---------------------------------------------------------------------------
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_BACKEND_DIR = os.path.normpath(os.path.join(_THIS_DIR, "..", "backend_5010"))
sys.path.insert(0, _BACKEND_DIR)

try:
    from slurm_commands import (
        get_squeue,
        get_sinfo,
        get_sacct,
        get_scontrol,
        get_sdiag,
        get_sshare,
        get_sprio,
        get_sstat,
        check_slurm_installation,
    )
except ImportError as exc:
    sys.stderr.write(
        f"[mcp_slurm] slurm_commands import 실패: {exc}\n"
        f"  탐색 경로: {_BACKEND_DIR}\n"
        "  backend_5010/slurm_commands.py 가 존재하는지 확인하세요.\n"
    )
    sys.exit(1)


mcp = FastMCP("slurm-readonly")

# ---------------------------------------------------------------------------
# 3) backend REST 설정 + 인증 전달
# ---------------------------------------------------------------------------
_BACKEND_URL = os.getenv("SLURM_MCP_BACKEND", "http://127.0.0.1:5010").rstrip("/")
_ENV_TOKEN = os.getenv("SLURM_MCP_TOKEN", "").strip()
_HTTP_TIMEOUT = 15  # seconds


def _auth_header(ctx) -> str:
    """이 호출에 쓸 Authorization 헤더 값('Bearer ...' 전체)을 결정.

    HTTP 모드: 들어온 MCP 요청의 Authorization 을 그대로 전달(사용자별 PAT/JWT).
    폴백(stdio 등): SLURM_MCP_TOKEN env. 둘 다 없으면 '' 반환.
    """
    try:
        req = getattr(getattr(ctx, "request_context", None), "request", None)
        if req is not None:
            v = req.headers.get("authorization")
            if v:
                return v
    except Exception:
        pass
    if _ENV_TOKEN:
        return f"Bearer {_ENV_TOKEN}"
    return ""


def _backend_request(method: str, path: str, body, auth_header: str):
    """backend REST 호출. (ok: bool, text: str, status: int|None) 반환.
    절대 예외를 raise 하지 않는다 — tool 이 죽으면 안 됨."""
    url = f"{_BACKEND_URL}{path}"
    data = json.dumps(body or {}).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"}
    if auth_header:
        headers["Authorization"] = auth_header
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT) as resp:
            raw = resp.read().decode("utf-8", "replace")
        return True, raw, getattr(resp, "status", 200)
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read().decode("utf-8", "replace")
        except Exception:
            pass
        return False, detail, e.code
    except urllib.error.URLError as e:
        return False, (
            f"error: backend({_BACKEND_URL}) 에 연결할 수 없습니다: {e.reason}. "
            "dashboard backend_5010 이 실행 중인지, SLURM_MCP_BACKEND 가 맞는지 확인하세요."
        ), None
    except Exception as e:  # noqa: BLE001
        return False, f"error: 예기치 못한 오류: {e}", None


def _require_user(ctx):
    """읽기 도구 인증 게이트. backend `/api/me` 로 토큰을 검증한다.
    통과면 None, 실패면 도구가 그대로 돌려줄 에러 문자열을 반환한다(fail-closed).
    SSO off 모드면 backend 가 토큰 없이도 200(admin)을 주므로 자동 통과한다."""
    auth = _auth_header(ctx)
    ok, body, status = _backend_request("GET", "/api/me", None, auth)
    if ok:
        return None
    if status in (401, 403):
        return (
            "error: 인증 실패 — 유효한 MCP 토큰이 필요합니다. 웹 대시보드의 "
            "'MCP 토큰' 메뉴에서 발급한 kst_ 토큰을 Authorization: Bearer 헤더"
            "(또는 stdio 모드면 SLURM_MCP_TOKEN)로 전달하세요."
        )
    # 백엔드 연결 불가 등 — 인증을 확인할 수 없으므로 안전하게 거부.
    return body if isinstance(body, str) and body else "error: 인증 확인 불가(backend 응답 없음)."


def _proxy_write(ctx, method, path, body, supports_dry_run, dry_run, label):
    """변경 도구 공통: 토큰 전달해 backend 변경계 REST 호출. dry_run 미지원 REST 면 경고 부착."""
    auth = _auth_header(ctx)
    ok, text, status = _backend_request(method, path, body, auth)
    if not ok and status in (401, 403):
        return (
            f"error: 인증/권한 실패(HTTP {status}) — '{label}' 는 인증된 권한이 필요합니다. "
            "MCP 토큰(kst_)이 유효한지, 해당 역할에 권한이 있는지 확인하세요.\n" + (text or "")
        ).strip()
    if not ok:
        return text if isinstance(text, str) else f"error: HTTP {status}"
    prefix = ""
    if not auth:
        prefix = (
            "[warning] 인증 토큰 없음 — backend SSO_ENABLED=false 가 아니면 거부될 수 있음.\n"
        )
    if not supports_dry_run and dry_run:
        prefix += (
            f"[warning] '{label}' REST 는 dry_run 을 지원하지 않아 서버에서 "
            "즉시 실행되었습니다(미리보기 아님).\n"
        )
    return prefix + text


def _stdout(result) -> str:
    """CompletedProcess → LLM 텍스트. 실패면 stderr 도 보여 디버깅 가능."""
    out = (result.stdout or "").strip()
    if result.returncode != 0:
        err = (result.stderr or "").strip()
        return f"[exit {result.returncode}]\n{out}\n{err}".strip()
    return out if out else "(no output)"


# ---------------------------------------------------------------------------
# 읽기전용 tools (인증 게이트 후 slurm_commands 직접호출)
# ---------------------------------------------------------------------------

@mcp.tool()
def slurm_list_jobs(ctx: Context) -> str:
    """현재 큐에 있는 Slurm 잡 목록을 반환합니다 (squeue).

    실행 중(R)/대기 중(PD) 잡의 JobID, 파티션, 사용자, 상태, 시간, 노드를
    한눈에 보여줍니다. 클러스터에 어떤 작업이 돌고 있는지 파악할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_squeue(check=False))


@mcp.tool()
def slurm_list_nodes(ctx: Context) -> str:
    """클러스터 노드/파티션 요약을 반환합니다 (sinfo).

    파티션별 노드 상태(idle/alloc/mix/down 등)와 가용 노드 수를 보여줍니다.
    어떤 자원이 비어 있는지, 다운된 노드가 있는지 확인할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_sinfo(check=False))


@mcp.tool()
def slurm_list_partitions(ctx: Context) -> str:
    """파티션 상세 구성을 반환합니다 (scontrol show partition).

    각 파티션의 노드 목록, 시간 제한(MaxTime), 상태(UP/DOWN), 우선순위 등
    상세 설정을 보여줍니다. 파티션 정책을 확인할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_scontrol("show", "partition", check=False))


@mcp.tool()
def slurm_job_accounting(ctx: Context) -> str:
    """완료/실행 잡의 어카운팅 기록을 반환합니다 (sacct).

    잡의 종료 상태(COMPLETED/FAILED/CANCELLED), ExitCode, 경과 시간 등
    회계 데이터베이스(slurmdbd) 기반 이력을 보여줍니다. 과거 잡 결과를
    확인하거나 실패 잡을 분석할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_sacct(check=False))


@mcp.tool()
def slurm_cluster_health(ctx: Context) -> str:
    """Slurm 설치/가용 여부를 점검합니다 (sinfo --version 기반).

    slurmctld 와의 통신 및 Slurm 바이너리 설치 상태를 확인합니다.
    'ok' 또는 'unavailable' 과 진단 메시지를 반환합니다. MCP 서버가 실제
    클러스터에 연결되는지 가장 먼저 확인할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    ok = check_slurm_installation()
    if ok:
        return "ok: Slurm 설치 확인됨 (sinfo --version 응답)"
    return (
        "unavailable: Slurm 명령에 응답이 없습니다. "
        "SLURM_BIN_DIR 환경변수 또는 slurmctld 상태를 확인하세요."
    )


@mcp.tool()
def slurm_scheduler_diag(ctx: Context) -> str:
    """스케줄러 진단 통계를 반환합니다 (sdiag).

    메인 스케줄러/백필 스케줄러의 사이클 수, 큐 길이, 마지막 스케줄 시각 등
    스케줄러 성능 지표를 보여줍니다. 잡이 왜 안 돌아가는지, 스케줄러가
    밀리는지 진단할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_sdiag(check=False))


@mcp.tool()
def slurm_fairshare(ctx: Context) -> str:
    """페어셰어(공정 사용량) 정보를 반환합니다 (sshare).

    계정/사용자별 할당된 share, 사용량(RawUsage), FairShare 점수를 보여줍니다.
    누가 자원을 많이 썼는지, 우선순위에 영향을 주는 공정성 지표를 확인할 때
    사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_sshare(check=False))


@mcp.tool()
def slurm_job_priority(ctx: Context) -> str:
    """대기 잡의 우선순위 분해를 반환합니다 (sprio).

    각 대기(PD) 잡의 우선순위를 구성 요소(Age, FairShare, JobSize, Partition,
    QOS 등)별로 분해해 보여줍니다. 어떤 잡이 먼저 돌지, 우선순위가 왜 낮은지
    분석할 때 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    return _stdout(get_sprio(check=False))


@mcp.tool()
def slurm_job_stat(job_id: str, ctx: Context) -> str:
    """실행 중인 특정 잡의 실시간 자원 사용량을 반환합니다 (sstat).

    Args:
        job_id: 조회할 잡 ID (예: "12345" 또는 "12345.batch").

    실행 중(R) 잡의 CPU/메모리/디스크 사용량 등 라이브 통계를 보여줍니다.
    sstat 는 RUNNING 상태 잡에만 동작합니다. 완료된 잡은 slurm_job_accounting
    (sacct) 을 사용하세요.
    """
    err = _require_user(ctx)
    if err:
        return err
    job_id = str(job_id).strip()
    if not job_id:
        return "error: job_id 가 비어 있습니다."
    return _stdout(get_sstat("-j", job_id, check=False))


# ---------------------------------------------------------------------------
# 잡 결과(완료 시뮬) 조회 tools — backend_5010 의 job_logs REST(/api/jobs/<id>/...) 프록시.
# 작업 디렉토리 탐색/파일 워크/로그 파싱 로직이 backend 에 있으므로 직접호출이 아니라 REST 재사용.
# ---------------------------------------------------------------------------

def _human_size(n) -> str:
    """바이트 → 사람이 읽는 크기."""
    try:
        size = float(n)
    except (TypeError, ValueError):
        return str(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024:
            return f"{int(size)}{unit}" if unit == "B" else f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}PB"


@mcp.tool()
def slurm_job_results(job_id: str, ctx: Context) -> str:
    """완료(또는 실행 중)된 잡의 결과 요약을 반환합니다 — 상태/종료코드/경과시간,
    작업 디렉토리, 그리고 ★결과 파일 목록★(LS-DYNA d3plot/binout, csv, 로그 등).

    시뮬레이션 잡이 끝난 뒤 정상 종료했는지, 어떤 산출물(결과 파일)이 생겼는지 확인할 때
    사용하세요. 텍스트 로그 내용(stdout/stderr)은 slurm_job_log 로 가져옵니다.
    (결과 데이터 자체는 d3plot 등 바이너리라 목록만 보여줍니다.)

    Args:
        job_id: 조회할 잡 ID (예: "12345").
    """
    err = _require_user(ctx)
    if err:
        return err
    job_id = str(job_id).strip()
    if not job_id:
        return "error: job_id 가 비어 있습니다."
    auth = _auth_header(ctx)

    ok_i, info_raw, st_i = _backend_request("GET", f"/api/jobs/{job_id}/info", None, auth)
    if not ok_i:
        if st_i == 404:
            return f"잡 {job_id} 를 찾을 수 없습니다(sacct/작업기록 없음)."
        return info_raw if isinstance(info_raw, str) and info_raw else f"error: HTTP {st_i}"
    try:
        info = json.loads(info_raw).get("job", {}) or {}
    except (ValueError, TypeError):
        info = {}

    ok_f, files_raw, _ = _backend_request("GET", f"/api/jobs/{job_id}/files", None, auth)
    files, work_dir = [], ""
    if ok_f:
        try:
            fj = json.loads(files_raw)
            files = fj.get("files", []) or []
            work_dir = fj.get("workDir") or ""
        except (ValueError, TypeError):
            pass

    out = [
        f"잡 {job_id} 결과",
        f"  이름: {info.get('jobName', '?')}",
        f"  상태: {info.get('state', '?')}  (ExitCode {info.get('exitCode', '?')})",
        f"  경과: {info.get('elapsed', '?')}  파티션: {info.get('partition', '?')}",
    ]
    if work_dir:
        out.append(f"  작업 디렉토리: {work_dir}")
    if files:
        out.append(f"  결과 파일 ({len(files)}개):")
        for f in files[:100]:
            tag = f.get("logType") or f.get("type", "")
            suffix = f", {tag}" if tag and tag != "file" else ""
            out.append(f"    - {f.get('name', '?')}  ({_human_size(f.get('size', 0))}{suffix})")
        if len(files) > 100:
            out.append(f"    … 외 {len(files) - 100}개")
    else:
        out.append("  결과 파일: (없음 또는 작업 디렉토리 접근 불가)")
    return "\n".join(out)


@mcp.tool()
def slurm_job_log(job_id: str, ctx: Context, lines: int = 200, log_type: str = "out") -> str:
    """잡의 stdout/stderr 로그 마지막 N줄을 반환합니다.

    시뮬레이션 출력/에러 메시지를 읽고 분석할 때 사용하세요(예: LS-DYNA 종료/수렴/에러 메시지).
    큰 로그는 tail 로 마지막 부분만 가져옵니다. 결과 파일 목록은 slurm_job_results 를 쓰세요.

    Args:
        job_id: 잡 ID.
        lines: 가져올 마지막 줄 수(기본 200, 최대 2000).
        log_type: "out"(stdout, 기본) 또는 "err"(stderr).
    """
    err = _require_user(ctx)
    if err:
        return err
    job_id = str(job_id).strip()
    if not job_id:
        return "error: job_id 가 비어 있습니다."
    try:
        n = max(1, min(int(lines), 2000))
    except (TypeError, ValueError):
        n = 200
    lt = "err" if str(log_type).strip().lower().startswith("e") else "out"
    auth = _auth_header(ctx)
    ok, raw, st = _backend_request("GET", f"/api/jobs/{job_id}/logs/tail?lines={n}&type={lt}", None, auth)
    if not ok:
        if st == 404:
            return f"잡 {job_id} 의 {lt} 로그를 찾을 수 없습니다."
        return raw if isinstance(raw, str) and raw else f"error: HTTP {st}"
    try:
        content = json.loads(raw).get("content", "")
    except (ValueError, TypeError):
        content = raw
    return content if content and content.strip() else "(로그 비어 있음)"


# ===========================================================================
# 변경계(write) tools — backend_5010 REST 프록시
#
# ⚠️ slurm_commands 직접호출이 아니라 backend 의 인증/권한/감사를 지나는 REST 를
#    호출한다. 들어온 요청의 Authorization 토큰을 그대로 전달(그 사용자 권한).
#    모든 tool 은 dry_run 기본 True. 실제 적용은 LLM 이 dry_run=False 명시해야 함.
# ===========================================================================

# node state -> (REST 경로, reason 필요, dry_run 지원)
# drain/resume/down/undrain 전부 서버단 dry_run 지원(미리보기→확인→실행).
_NODE_STATE_ROUTES = {
    "DRAIN": ("/api/nodes/drain", True, True),
    "RESUME": ("/api/nodes/resume", False, True),
    "DOWN": ("/api/nodes/down", True, True),
    "UNDRAIN": ("/api/nodes/undrain", False, True),
}


@mcp.tool()
def slurm_node_set_state(
    node: str,
    state: str,
    ctx: Context,
    reason: str = "",
    dry_run: bool = True,
) -> str:
    """노드 상태를 변경합니다 (backend REST 프록시, 변경계/위험).

    ⚠️ 클러스터를 실제로 바꾸는 변경 작업입니다. backend_5010 의 인증/권한 경계를
    통과하는 REST(POST /api/nodes/{drain|resume|down|undrain})를 호출합니다.

    Args:
        node: 대상 노드 이름 (예: "cn01").
        state: DRAIN(새 잡 중지·실행잡 유지) | RESUME(복귀) | DOWN(강제 다운, reason 필수, 파괴적)
               | UNDRAIN(drain 사유만 제거). 대소문자 무관.
        reason: 사유. DOWN 필수, DRAIN 권장. RESUME/UNDRAIN 무시.
        dry_run: True(기본)면 미리보기. 실제 적용은 dry_run=False 명시.
    """
    node = str(node).strip()
    if not node:
        return "error: node 가 비어 있습니다."
    key = str(state).strip().upper()
    if key not in _NODE_STATE_ROUTES:
        return f"error: state '{state}' 는 허용되지 않습니다. 가능: {sorted(_NODE_STATE_ROUTES.keys())}"
    path, reason_required, supports_dry_run = _NODE_STATE_ROUTES[key]
    reason = str(reason).strip()
    if key == "DOWN" and not reason:
        return "error: state=DOWN 은 reason 이 필수입니다 (왜 내리는지 명시)."
    body = {"node_name": node, "dry_run": bool(dry_run)}
    if reason and reason_required:
        body["reason"] = reason
    return _proxy_write(ctx, "POST", path, body, supports_dry_run, dry_run, f"node {key}")


def _body_dry_only(value, dry_run):
    return {"dry_run": bool(dry_run)}


def _body_priority(value, dry_run):
    return {"priority": value, "dry_run": bool(dry_run)}


def _body_nice(value, dry_run):
    return {"nice": value, "dry_run": bool(dry_run)}


# action -> (method, 경로, body builder, dry_run 지원). 전부 서버단 dry_run 지원.
_JOB_ACTIONS = {
    "hold":     ("POST", "/api/slurm/jobs/{id}/hold",     _body_dry_only, True),
    "release":  ("POST", "/api/slurm/jobs/{id}/release",  _body_dry_only, True),
    "cancel":   ("POST", "/api/slurm/jobs/{id}/cancel",   _body_dry_only, True),
    "requeue":  ("POST", "/api/slurm/jobs/{id}/requeue",  _body_dry_only, True),
    "priority": ("POST", "/api/slurm/jobs/{id}/priority", _body_priority, True),
    "nice":     ("POST", "/api/slurm/jobs/{id}/nice",     _body_nice,     True),
    "top":      ("POST", "/api/slurm/jobs/{id}/top",      _body_dry_only, True),
}


@mcp.tool()
def slurm_job_control(
    job_id: str,
    action: str,
    ctx: Context,
    value: int = 0,
    dry_run: bool = True,
) -> str:
    """대기/실행 잡을 제어합니다 (backend REST 프록시, 변경계/위험).

    ⚠️ 클러스터를 실제로 바꾸는 변경 작업입니다. backend 의 인증/권한 경계를 통과하는
    REST(/api/slurm/jobs/<id>/<action>)를 호출합니다.

    Args:
        job_id: 대상 잡 ID (예: "12345").
        action: hold | release | requeue | cancel(파괴적, 되돌릴 수 없음)
                | priority(value 정수) | nice(value 정수, 음수=우선순위↑) | top(내 큐 최상단).
        value: priority/nice 에서만 사용하는 정수.
        dry_run: True(기본)면 미리보기(생성될 명령만 반환). 실제 적용은 dry_run=False 명시.
    """
    job_id = str(job_id).strip()
    if not job_id:
        return "error: job_id 가 비어 있습니다."
    act = str(action).strip().lower()
    if act not in _JOB_ACTIONS:
        return f"error: action '{action}' 는 허용되지 않습니다. 가능: {sorted(_JOB_ACTIONS.keys())}"
    method, path_tmpl, body_builder, supports_dry_run = _JOB_ACTIONS[act]
    if act in ("priority", "nice"):
        try:
            value = int(value)
        except (TypeError, ValueError):
            return f"error: action '{act}' 는 value 가 정수여야 합니다 (받은 값: {value!r})."
    path = path_tmpl.format(id=job_id)
    body = body_builder(value, dry_run)
    return _proxy_write(ctx, method, path, body, supports_dry_run, dry_run, f"job {act}")


# ═══════════════════════════════════════════════════════════════════════════
# SmartTwin 시뮬레이션 제출 — 전각도 낙하(fullangle_drop) / 전위치 부분충격(partial_impact)
#
# scenario.json 권위 스키마 출처(pyKooCAE 소스에서 코드로 확정):
#  - 전각도(DROP): Runner/CumulativeDesigner.py(_parse_angle_source) +
#    Runner/AngleSourceParser.py(AngleSourceType 5종) + Runner/AngleMixingStrategy.py(5전략) +
#    Runner/StepConfigBuilder.py(build_drop_attitude_config — simulation_params/drop_surface).
#  - 부분충격(DWI): top-level mode=="drop_weight_impact" 디스패치(KooChainRun cmd_prepare)
#    → Runner/DropWeightImpactWorkflow.py 가 simulation_params.{impactor,locations,wall} 파싱.
#
# 제출 경로: 대시보드 Path A(/api/jobs/submit) 멀티파트 프록시 — 인증/권한/이력(job_submissions,
# result_dir)이 웹 제출과 동일하게 적용된다. 템플릿(smarttwin-*)은 scenario_json 업로드가
# 프리셋/기본격자보다 우선하므로, 이 도구가 옵션→scenario.json 을 만들어 올리면 끝.
# ═══════════════════════════════════════════════════════════════════════════

_SMARTTWIN_TEMPLATE_IDS = {
    "fullangle_drop": "smarttwin-fullangle-drop",
    "partial_impact": "smarttwin-partial-impact",
}
_SCENARIO_PRESET_DIR = os.environ.get("SCENARIO_PRESET_DIR", "/data/scenario")
# 모델(.k) 경로 허용 베이스 — MCP(헤드노드)가 읽어 업로드하므로 공유 FS 로 제한(경로탈출 방지)
_MODEL_ALLOWED_BASES = [
    p.strip() for p in os.environ.get(
        "SMARTTWIN_MODEL_BASES", "/data,/shared,/mnt/gluster,/home").split(",") if p.strip()
]
_SUBMIT_TIMEOUT = float(os.environ.get("MCP_SUBMIT_TIMEOUT", "600"))  # 대형 .k 업로드 대비

_DROP_OPTIONS_DOC = """\
━━ 전각도 낙하 (fullangle_drop / smarttwin-fullangle-drop) scenario.json 옵션 카탈로그 ━━
단위계 ★필수 확인★: LS-DYNA 덱과 동일해야 함. 표준은 [tonne, mm, s, MPa]
  (강철 예: density=7.85e-9 tonne/mm³, youngs_modulus=2.0e5 MPa, height 는 mm).

■ 최상위
- project_name (string) — 잡 이름으로 자동 치환됨(직접 설정 불필요)
- scenarios[0].template — "%INPUTFILE%" 그대로 둘 것(업로드한 모델 파일명으로 자동 치환)
- preserve_includes (list[string], 기본 []) — 보존할 *INCLUDE 패턴(멀티스케일/IGA)

■ simulation_params (전역 물리)
- height (float, mm, 1500) — 낙하 높이
- tFinal (float, s, 0.005) / dt (float, s, 1e-6) — 종료 시간 / 출력 간격
- density (float, tonne/mm³, 7.85e-9) / youngs_modulus (float, MPa, 2.0e5) /
  poisson_ratio (float, 0.3) — 바닥판(변형체일 때)의 물성
- offset_distance (float, mm, 0.05) — 모델-바닥 초기 간격
- drop_surface.type ∈ {Plane(기본), RigidWall, PlaneGraded, PlanewithRoughness}
  · Plane: size [x,y,z mm, 기본 300,300,20], mesh [nx,ny,nz, 기본 30,30,2]
  · RigidWall: 파라미터 없음(강체 바닥)
  · PlaneGraded: size/mesh + num_outer_layers(5), ratio(1.5) — 바깥층 점진 격자
  · PlanewithRoughness: size/mesh + roughness_mode("Random"), r_max, shape_factor, shape_factor2
  · deformable_to_rigid (bool, false) — D2R 전환
- dynamic_relaxation (bool 또는 {enabled, nrcyck 250, drtol 0.01, drfctr 0.995, drterm=tFinal})
  — 누적 스텝 간 DR 안정화
- 접촉 고급: convert_general_to_single_surface(true), ensure_single_surface(false),
  decompose_general_contact(false), robust_contact(false), include_wall_in_general(false),
  decompose_contact_margin(1.5), decompose_contact_absolute_margin_x/y/z(5,5,0.5)

■ scenarios[0].angle_source — 낙하 각도 집합(DOE)
- source_type ∈ {cuboid_geometry(기본), fibonacci_lattice, pitching_sweep, rolling_sweep, case_txt_file}
  · cuboid_geometry: {include_faces(T,6면), include_edges(T,12모서리), include_corners(T,8꼭짓점)} → 최대 26방향
  · fibonacci_lattice: {num_points(26, 별칭 num_directions), progressive(false),
    principal_directions, sampling_space} — 구면 균등 N방향
  · pitching_sweep: {pitch_min(-90), pitch_max(90), pitch_step(10), roll_fixed(0), yaw_fixed(0)}
  · rolling_sweep: {roll_min(-180), roll_max(170), roll_step(10), pitch_fixed(0), yaw_fixed(0)}
  · case_txt_file: {file_path(각도목록 .txt), selected_indices(선택)} — case_txt_path 인자로 파일을
    올리면 file_path 는 자동 설정됨

■ scenarios[0].cumulative — 연속(누적) 낙하
- num_steps (int, 1) — 각도당 연속 낙하 횟수
- mode_sequence (list, ["DROP"]) — 스텝별 모드(DROP 외 IMPACT/THERM/STAT/VIB 조합 가능)
- base_angle_index (int, 0)
- angle_mixing.strategy ∈ {same_angle(기본, 동일 각도 반복), cyclic(+offset 순환),
  random(랜덤), opposite(대칭), custom_mapping(스텝→인덱스 매핑)}
  · cyclic_offset(1), random_seed, custom_mapping({step:index})

■ environment (고급 — 기본은 프리셋 값 유지 권장)
- ncpu, time_limit, lsdyna_memory, nodes_per_job, mpi_enabled 정도만 조정.
  경로/sif/라이선스(LSTC_*) 키는 서버가 관리하므로 건드리지 말 것.

■ 드라이버 잡 자원(템플릿 env 고정, scenario 아님): 자식 잡 packing CHAIN_NODES=2,
  CHAIN_JOBS_PER_NODE=2, CHAIN_NCPU=4, 완료 후 후처리 CHAIN_POSTPROCESS=true.
"""

_IMPACT_OPTIONS_DOC = """\
━━ 전위치 부분충격 (partial_impact / smarttwin-partial-impact) scenario.json 옵션 카탈로그 ━━
단위계 ★필수 확인★: LS-DYNA 덱과 동일해야 함. 표준은 [tonne, mm, s, MPa]
  (강철: density=7.85e-9, youngs_modulus=2.0e5). ※대시보드 기본값(7850/2.0e11)은 SI 숫자라
  ton-mm-s 덱과 부정합 — 덱 단위계에 맞춰 반드시 확인/수정할 것.

■ 최상위 (자동 설정 — 직접 넣지 말 것): mode="drop_weight_impact"(디스패치 키),
  model_file(업로드 모델 파일명), output_dir("output"), project_name(잡 이름)
- preserve_includes (list[string], 기본 []) — 보존할 *INCLUDE 패턴

■ simulation_params
- tFinal (float, s, 0.001) / dt (float, s, 1e-6)
- generation_mode ∈ {DampingSpring(기본), OutsideRigidPart, OutsideRigidElement}
  — 임팩터-모델 결합/부분강체화 방식(오타 시 조용히 기본 처리되므로 정확히)
- boundary_distance (float, mm, 0) — >0 이면 충격점 반경 밖 강체화
- offset_distance (float, mm, 0.05) — 임팩터-모델 초기 간격
- impactor:
  · type ∈ {Sphere(기본), Cylinder}
  · radius (float, mm, 5.0) — Sphere 반경
  · height (float, mm, 100) — ★낙하 높이★(초속도 vz=-sqrt(2·9810·height); 임팩터 크기 아님)
  · density / youngs_modulus / poisson_ratio — 임팩터 물성(단위계 주의)
  · [Cylinder 전용 2단] front_radius(=radius), outer_radius(=radius*2),
    front_height(=radius), back_height(=radius*2), back_radius(=outer_radius)
- wall (바닥 강체판): density(1.0e-9), youngs_modulus(1.0e4 MPa), poisson_ratio(0.3)
- locations — 충격 위치 DOE:
  · mode ∈ {grid(기본), list, lhs, part_center}
  · grid: x_count(7)/y_count(13) 또는 spacing(mm, >0 이면 간격 기반 자동 산정);
    x_range/y_range([min,max] mm, 생략 시 모델 bbox×margin 자동), margin(0.9)
  · list: points=[[x,y],...] (mm, 필수)
  · lhs: n_samples(50) + x_range/y_range/margin — Latin Hypercube 샘플링
  · part_center: pids(파트 ID 목록, 필수; 별칭 pid) + spacing(5.0) + layers(2)
    → 파트 bbox 중심 기준 (2·layers+1)² 격자

■ environment (자식 잡이 실제 읽는 키만): ncpu(4), memory("4G"), partition("normal"),
  sif_path, koomeshmodifier_path, solver_command — 기본값 유지 권장.

■ 드라이버 잡 자원(템플릿 env 고정): CHAIN_NODES=2, CHAIN_JOBS_PER_NODE=2, CHAIN_NCPU=4,
  CHAIN_POSTPROCESS=true.
"""


def _deep_merge(base: Any, override: Any) -> Any:
    """dict 는 재귀 병합, 그 외(리스트/스칼라)는 override 로 교체."""
    if isinstance(base, dict) and isinstance(override, dict):
        out = dict(base)
        for k, v in override.items():
            out[k] = _deep_merge(base.get(k), v) if k in base else v
        return out
    return override if override is not None else base


def _list_drop_presets() -> list:
    """각도 프리셋 디렉토리(/data/scenario/*) 중 scenario.json 이 있는 것만."""
    try:
        return sorted(
            d for d in os.listdir(_SCENARIO_PRESET_DIR)
            if os.path.isfile(os.path.join(_SCENARIO_PRESET_DIR, d, "scenario.json"))
        )
    except OSError:
        return []


def _safe_filename(name: str) -> str:
    """backend secure_filename 과 호환되는 ASCII 파일명(변형 없이 통과하도록 선제 정제)."""
    base = os.path.basename(str(name or ""))
    return re.sub(r"[^A-Za-z0-9._-]", "_", base) or "input.k"


def _validate_shared_path(path: str, exts: tuple, what: str):
    """서버(헤드노드)측 파일 검증 — 절대경로/실존/확장자/허용 베이스. (ok, err|realpath)"""
    if not path or not os.path.isabs(path):
        return False, f"error: {what} 는 서버(헤드노드)의 절대경로여야 합니다 (예: /data/.../model.k). 받은 값: {path!r}"
    real = os.path.realpath(path)
    if not any(real == b or real.startswith(b.rstrip("/") + "/") for b in _MODEL_ALLOWED_BASES):
        return False, f"error: {what} 는 공유 저장소({', '.join(_MODEL_ALLOWED_BASES)}) 하위여야 합니다: {real}"
    if not os.path.isfile(real):
        return False, f"error: {what} 파일이 없습니다: {real} (MCP 서버=헤드노드 기준 경로여야 함)"
    if exts and not real.lower().endswith(exts):
        return False, f"error: {what} 확장자는 {exts} 만 허용: {real}"
    return True, real


def _lstc_license_server() -> str:
    """부분충격 생성 scenario 용 라이선스 서버.
    ★서버사이드 env(LSTC_LICENSE_SERVER) 우선★ — 운영마다 다르고 명시 설정이 권위.
    없으면 프리셋(start_production.sh 가 운영 IP 로 동기화한 /data/scenario/*)에서 폴백."""
    env_srv = os.environ.get("LSTC_LICENSE_SERVER", "").strip()
    if env_srv:
        return env_srv
    for preset in _list_drop_presets():
        try:
            with open(os.path.join(_SCENARIO_PRESET_DIR, preset, "scenario.json")) as fp:
                penv = (json.load(fp).get("environment") or {})
            srv = (penv.get("lsdyna_apptainer_env") or {}).get("LSTC_LICENSE_SERVER", "")
            if srv and "%" not in srv:
                return srv
        except (OSError, ValueError):
            continue
    return ""


def _impact_base_scenario(model_filename: str, job_name: str, license_server: str) -> dict:
    """부분충격 기본 scenario — 대시보드 템플릿(smarttwin-partial-impact) 생성본과 동일 구조."""
    return {
        "project_name": job_name or "MCP_DWI",
        "mode": "drop_weight_impact",
        "model_file": model_filename,
        "output_dir": "output",
        "environment": {
            # DWI(drop_weight_impact) run.sh 가 실제 읽는 평면 키. KooMeshModifier/sif 는 공유 FS(/data)
            # 여야 compute 노드가 접근(/opt 노드로컬이면 멀티노드 실패).
            # ★sif_path 를 비워 run.sh 가 `{solver_command} i=...` 를 bare 실행하게 하고, solver_command
            #   자체에 apptainer exec + 라이선스 --env 를 넣는다★ — DWI run.sh 의 `apptainer exec {sif}
            #   {solver}` 는 --env 를 안 줘서 라이선스 서버에 도달 못 하기 때문(검증: 그 경우 "License
            #   client cannot find any servers"). 아래 형태면 라이선스 통과 + 실솔브 확인됨.
            "koomeshmodifier_path": "/data/SmartTwinPreprocessor/bin/KooMeshModifier",
            "sif_path": "",
            "solver_command": (
                "apptainer exec --bind /data:/data "
                "--env LSTC_FILE=/opt/ls-dyna_license/LSTC_FILE "
                f"--env LSTC_LICENSE_SERVER={license_server} "
                "--env FI_PROVIDER=tcp --env I_MPI_FABRICS=ofi --env LD_LIBRARY_PATH=/opt/openmpi/lib "
                "/data/apptainers/LSDynaBasic_aocc420_ompi4.0.5_mpp_s.sif "
                "/opt/openmpi/bin/mpirun -np 1 /opt/ls-dyna/lsdyna"
            ),
            "partition": "normal",
            "lsdyna_path": "/opt/ls-dyna/lsdyna_R16.1.1",
            "mpi_path": "mpirun",
            "memory": "2G",
            "lsdyna_memory": "2000m",
            "apptainer_sif": "/opt/apptainers/SmartTwinPreprocessor.sif",
            "apptainer_bind": "/data:/data,/shared:/shared",
            "apptainer_env": {},
            "lsdyna_apptainer_sif": "/opt/apptainers/LSDynaBasic_aocc420_ompi4.0.5_mpp_s.sif",
            "lsdyna_apptainer_bind": "/data:/data,/shared:/shared",
            "lsdyna_apptainer_env": {
                "LSTC_FILE": "/opt/ls-dyna_license/LSTC_FILE",
                "LSTC_LICENSE_SERVER": license_server,
                "FI_PROVIDER": "tcp",
                "I_MPI_FABRICS": "ofi",
                "LD_LIBRARY_PATH": "/opt/openmpi/lib",
            },
            "apptainer_tmpdir": "/data/tmp",
            "nodes_per_job": 1,
            "mpi_launcher": "mpirun",
            "mpi_enabled": True,
            "ncpu": 1,
            "koochainrun_path": "/data/SmartTwinPreprocessor/bin/KooChainRun",
            "time_limit": "24:00:00",
        },
        "simulation_params": {
            "tFinal": 0.001,
            "dt": 0.000001,
            "impactor": {
                "type": "Sphere",
                "radius": 5.0,
                "height": 100,
                "density": 7850,
                "youngs_modulus": 2.0e11,
                "poisson_ratio": 0.3,
            },
            "locations": {"mode": "grid", "x_count": 5, "y_count": 5, "margin": 0.9},
            "generation_mode": "DampingSpring",
        },
    }


def _multipart_post(path: str, fields: dict, files: list, auth: str, timeout: float):
    """backend 에 multipart/form-data POST (httpx — mcp 전이 의존이라 항상 존재).
    files: [(폼필드명, 파일명, bytes|경로)]  반환 (ok, text, status)."""
    try:
        import httpx
    except ImportError:
        return False, "error: httpx 미설치 — mcp SDK 의존성이 깨졌습니다(venv 재설치 필요).", None
    url = f"{_BACKEND_URL}{path}"
    headers = {"Authorization": auth} if auth else {}
    opened = []
    try:
        file_parts = {}
        for field, fname, src in files:
            if isinstance(src, (bytes, bytearray)):
                file_parts[field] = (fname, io.BytesIO(src), "application/octet-stream")
            else:
                fh = open(src, "rb")  # noqa: SIM115 — httpx 가 스트리밍, finally 에서 close
                opened.append(fh)
                file_parts[field] = (fname, fh, "application/octet-stream")
        with httpx.Client(timeout=httpx.Timeout(timeout, connect=10.0)) as client:
            resp = client.post(url, data=fields, files=file_parts or None, headers=headers)
        return resp.status_code < 400, resp.text, resp.status_code
    except Exception as e:  # noqa: BLE001 — tool 이 죽으면 안 됨
        return False, f"error: backend 멀티파트 요청 실패: {e}", None
    finally:
        for fh in opened:
            try:
                fh.close()
            except OSError:
                pass


@mcp.tool()
def smarttwin_scenario_options(sim_type: str, ctx: Context) -> str:
    """전각도 낙하/전위치 부분충격 잡의 scenario.json 전체 옵션 카탈로그를 반환합니다.

    smarttwin_submit 을 부르기 전에 이 도구로 옵션(키/타입/단위/기본값/허용값)과
    사용 가능한 각도 프리셋(live)을 확인하세요. 카탈로그는 KooChainRun 실제 파서
    (pyKooCAE Runner/*)에서 확정한 권위 스키마입니다.

    Args:
        sim_type: "fullangle_drop"(전각도 낙하) | "partial_impact"(전위치 부분충격) | "all"(둘 다).
    """
    err = _require_user(ctx)
    if err:
        return err
    st = str(sim_type).strip().lower()
    if st not in ("fullangle_drop", "partial_impact", "all"):
        return "error: sim_type 은 fullangle_drop | partial_impact | all 중 하나여야 합니다."
    parts = []
    if st in ("fullangle_drop", "all"):
        presets = _list_drop_presets()
        parts.append(_DROP_OPTIONS_DOC)
        parts.append(
            f"■ 사용 가능한 각도 프리셋 (angle_preset, {_SCENARIO_PRESET_DIR}): "
            + (", ".join(presets) if presets else "(없음 — scenario_overrides 로 직접 구성)")
            + "\n  프리셋을 base 로 삼고 scenario_overrides 가 깊은 병합(dict 재귀, 리스트/스칼라 교체)됩니다."
        )
    if st in ("partial_impact", "all"):
        parts.append(_IMPACT_OPTIONS_DOC)
    parts.append(
        "■ 제출: smarttwin_submit(sim_type, model_path=서버측 .k 절대경로, job_name, "
        "angle_preset/case_txt_path[전각도], scenario_overrides={...}, memory, time_limit, "
        "dry_run=True→미리보기/False→실제 제출). 결과 추적: slurm_job_results / slurm_job_log."
    )
    return "\n\n".join(parts)


@mcp.tool()
def smarttwin_submit(
    sim_type: str,
    model_path: str,
    ctx: Context,
    job_name: str = "",
    angle_preset: str = "",
    scenario_overrides: Optional[Dict[str, Any]] = None,
    case_txt_path: str = "",
    memory: str = "",
    time_limit: str = "",
    dry_run: bool = True,
) -> str:
    """전각도 낙하/전위치 부분충격 잡을 대시보드 경유로 제출합니다 (변경계, dry_run 기본).

    옵션 스키마는 먼저 smarttwin_scenario_options 로 확인하세요. 이 도구는
    프리셋/기본 scenario 에 scenario_overrides 를 깊은 병합해 scenario.json 을 만들고,
    모델(.k)과 함께 대시보드 제출 API(/api/jobs/submit)로 올립니다 — 웹 제출과 동일한
    인증/권한/이력이 적용되고, 결과는 /data/single/<사용자>/<잡이름>_<잡ID>/ 에 저장됩니다.

    Args:
        sim_type: "fullangle_drop" | "partial_impact".
        model_path: LS-DYNA 모델(.k/.key/.dyn)의 ★서버(헤드노드) 절대경로★ (공유 FS: /data 등).
                    클라이언트 로컬 경로는 불가 — 먼저 공유 저장소에 두세요.
        job_name: 잡 이름(비우면 템플릿 기본). 결과 폴더명에 들어갑니다.
        angle_preset: [전각도] 각도 프리셋 이름(예: 26direction, 6face, fibonacci-100).
                      비우면 scenario_overrides 없을 때 템플릿 기본(26direction).
        scenario_overrides: scenario.json 에 깊은 병합할 부분 dict.
                            예(전각도): {"simulation_params": {"height": 1000,
                              "drop_surface": {"type": "RigidWall"}}}
                            예(부분충격): {"simulation_params": {"locations":
                              {"mode": "grid", "spacing": 10}, "impactor": {"radius": 8}}}
        case_txt_path: [전각도] 각도 케이스(.txt) 서버측 경로 — angle_source=case_txt_file 용.
        memory: Slurm 드라이버 잡 메모리 오버라이드(예: "8G"). 비우면 템플릿 기본 4G.
        time_limit: Slurm 드라이버 잡 시간 오버라이드(예: "24:00:00"). 기본 167:00:00.
        dry_run: True(기본)=검증+최종 scenario.json+스크립트 미리보기만. 실제 제출은 False 명시.
    """
    st = str(sim_type).strip().lower()
    if st not in _SMARTTWIN_TEMPLATE_IDS:
        return "error: sim_type 은 fullangle_drop | partial_impact 중 하나여야 합니다."
    template_id = _SMARTTWIN_TEMPLATE_IDS[st]
    auth = _auth_header(ctx)

    # ── 모델 파일 검증(서버측 경로) ──
    ok, model_real = _validate_shared_path(model_path, (".k", ".key", ".dyn"), "model_path")
    if not ok:
        return model_real
    model_fname = _safe_filename(model_real)

    ov = scenario_overrides if isinstance(scenario_overrides, dict) else None

    # ── scenario.json 구성 ──
    scenario = None          # None 이면 업로드 생략(템플릿 기본 동작)
    scenario_note = ""
    case_real = None
    if st == "fullangle_drop":
        if case_txt_path:
            ok, case_real = _validate_shared_path(case_txt_path, (".txt",), "case_txt_path")
            if not ok:
                return case_real
        if angle_preset or ov or case_real:
            preset = (angle_preset or "26direction").strip()
            preset_file = os.path.join(_SCENARIO_PRESET_DIR, preset, "scenario.json")
            try:
                with open(preset_file) as fp:
                    scenario = json.load(fp)
            except (OSError, ValueError) as e:
                return (f"error: 각도 프리셋 '{preset}' 로드 실패({e}). "
                        f"사용 가능: {', '.join(_list_drop_presets()) or '(없음)'}")
            scenario_note = f"base=프리셋 {preset}"
            if ov:
                scenario = _deep_merge(scenario, ov)
                scenario_note += " + overrides 병합"
            if case_real:
                # 케이스 파일 업로드 시 angle_source 를 case_txt_file 로 자동 배선(미지정 시)
                scen_list = scenario.get("scenarios") or [{}]
                asrc = scen_list[0].setdefault("angle_source", {})
                if not ov or "scenarios" not in ov:
                    asrc["source_type"] = "case_txt_file"
                asrc.setdefault("case_txt_file", {}).setdefault(
                    "file_path", _safe_filename(case_real))
                scenario["scenarios"] = scen_list
                scenario_note += f" + case_txt({_safe_filename(case_real)})"
    else:  # partial_impact
        if ov:
            lic = _lstc_license_server()
            if not lic:
                return ("error: LS-DYNA 라이선스 서버 주소를 결정할 수 없습니다 "
                        f"(프리셋 {_SCENARIO_PRESET_DIR}/*/scenario.json / env LSTC_LICENSE_SERVER 모두 없음). "
                        "운영이면 start_production.sh 라이선스 동기화를 먼저 확인하세요.")
            scenario = _deep_merge(_impact_base_scenario(model_fname, job_name, lic), ov)
            # 디스패치/파일명 키는 사용자 오버라이드로 깨지지 않게 고정
            scenario["mode"] = "drop_weight_impact"
            scenario["model_file"] = model_fname
            scenario_note = "base=기본격자(5x5) + overrides 병합"

    # ── 폼 필드 ──
    slurm_overrides = {}
    if memory:
        slurm_overrides["mem"] = str(memory)
    if time_limit:
        slurm_overrides["time"] = str(time_limit)
    fields = {"template_id": template_id,
              "slurm_overrides": json.dumps(slurm_overrides)}
    if job_name:
        fields["job_name"] = str(job_name)

    files = [("file_model_k", model_fname, model_real)]
    if scenario is not None:
        files.append(("file_scenario_json", "scenario.json",
                      json.dumps(scenario, ensure_ascii=False, indent=2).encode("utf-8")))
    if case_real:
        files.append(("file_case_txt", _safe_filename(case_real), case_real))

    size_mb = os.path.getsize(model_real) / 1e6
    if not scenario_note:
        default_base = "프리셋 26direction" if st == "fullangle_drop" else "기본격자 5x5"
        scenario_note = f"(업로드 생략 — 템플릿 기본: {default_base})"
    plan = (
        f"[{st}] template={template_id}\n"
        f"model: {model_real} ({size_mb:.1f}MB → {model_fname})\n"
        f"scenario: {scenario_note}\n"
        f"slurm_overrides: {slurm_overrides or '(없음)'}  job_name: {job_name or '(템플릿 기본)'}"
    )

    if dry_run:
        # 서버측 스크립트 미리보기(/api/jobs/preview 는 파일 불필요) + 최종 scenario 반환
        ok, text, status = _multipart_post("/api/jobs/preview", fields, [], auth, 30.0)
        preview = ""
        if ok:
            try:
                script = json.loads(text).get("script", "")
                sbatch = "\n".join(l for l in script.splitlines() if l.startswith("#SBATCH"))
                preview = f"\n--- 드라이버 잡 #SBATCH (backend preview) ---\n{sbatch}"
            except ValueError:
                pass
        else:
            preview = f"\n(backend preview 실패 status={status}: {text[:300]})"
        scen_txt = ""
        if scenario is not None:
            scen_txt = ("\n--- 업로드될 scenario.json ---\n"
                        + json.dumps(scenario, ensure_ascii=False, indent=2))
        return (f"[DRY-RUN] 제출 계획 (실제 제출은 dry_run=False)\n{plan}{preview}{scen_txt}")

    ok, text, status = _multipart_post("/api/jobs/submit", fields, files, auth, _SUBMIT_TIMEOUT)
    if not ok:
        if status in (401, 403):
            return (f"error: 인증/권한 거부(status={status}): {text[:300]}\n"
                    "PAT 토큰(Authorization) 또는 dashboard 권한을 확인하세요.")
        return f"error: 제출 실패(status={status}): {text[:500]}"
    try:
        data = json.loads(text)
    except ValueError:
        return f"제출 응답 파싱 실패(원문): {text[:500]}"
    job_id = data.get("job_id")
    return (
        f"✅ 제출 완료 — job_id={job_id}\n{plan}\n"
        f"script: {data.get('script_path')}\n"
        f"결과 폴더: /data/single/<사용자>/{(job_name or template_id)}_{job_id}/ (드라이버 잡 완료 후)\n"
        f"추적: slurm_job_results(job_id={job_id}) / slurm_job_log(job_id={job_id}) — "
        "드라이버가 자식 잡들을 제출/대기하므로 전체 완료까지 시간이 걸립니다."
    )


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "streamable-http").strip()

    if transport == "stdio":
        # 기존 동작 보존 — 클라이언트가 로컬에서 spawn, 단일 사용자.
        mcp.run()
        sys.exit(0)

    # HTTP(streamable) 모드 — 원격 Claude Desktop/Code 가 mcp-remote 로 접속.
    host = os.environ.get("MCP_HOST", "127.0.0.1")
    mcp.settings.host = host
    mcp.settings.port = int(os.environ.get("MCP_PORT", "5012"))

    # FastMCP 는 생성 시점(host=127.0.0.1)에 DNS rebinding 보호를 켜고 allowed_hosts 를
    # localhost 로 고정한다. host 를 0.0.0.0 등으로 바꾸면 서버 IP/도메인으로 들어온
    # Host 헤더가 거부돼 421 "Invalid Host header" 가 난다(외부 노출 시).
    if host not in ("127.0.0.1", "localhost", "::1"):
        from mcp.server.transport_security import TransportSecuritySettings

        allowed = [h.strip() for h in os.environ.get("MCP_ALLOWED_HOSTS", "").split(",") if h.strip()]
        if allowed:
            # 권장: 허용할 Host 만 명시(포트 와일드카드 가능).
            #   MCP_ALLOWED_HOSTS="slurm.example.com,slurm.example.com:*,10.0.0.5:5012"
            mcp.settings.transport_security = TransportSecuritySettings(
                enable_dns_rebinding_protection=True,
                allowed_hosts=allowed,
                allowed_origins=[],
            )
        else:
            # 미지정이면 보호를 끈다 — 인증은 PAT(backend 검증), 망 보호는 nginx/방화벽에
            # 맡기는 사내망 노출 시나리오. 외부망 노출 시엔 MCP_ALLOWED_HOSTS 권장.
            mcp.settings.transport_security = TransportSecuritySettings(
                enable_dns_rebinding_protection=False,
            )

    mcp.run(transport="streamable-http")
