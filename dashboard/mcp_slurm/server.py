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

import json
import os
import sys
import urllib.error
import urllib.request

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
