#!/usr/bin/env python3
"""
Slurm MCP 서버 (stdio) — 읽기전용 직접호출 + 변경계 REST 프록시

LLM 클라이언트(Claude Desktop, Claude Code 등)가 Slurm 클러스터를
조회(읽기) 및 제어(변경)할 수 있게 해주는 MCP 서버입니다.

설계:
- mcp.server.fastmcp.FastMCP 기반 별도 stdio 서버.
- 읽기전용(Phase1): backend_5010/slurm_commands.py 의 검증된 래퍼 함수를 직접 import 재사용
  (Slurm 명령 경로/환경변수/타임아웃 처리를 단일 소스에서 관리).
- 변경계(Phase2): slurm_commands 를 직접 호출하지 않고 ★backend_5010 의 REST API 를
  HTTP 로 프록시★ 한다. 이렇게 해야 JWT/권한(permission_required)/감사 경계를
  우회하지 않는다. 표준 라이브러리 urllib 로 localhost:5010 변경계 엔드포인트를 호출.

읽기전용 원칙:
- 조회(squeue/sinfo/sacct/scontrol show/sdiag/sshare/sprio/sstat) 계열은 직접호출.

변경계 원칙:
- node/job 제어 tool 은 전부 dry_run 기본 True (안전). 실제 적용은 dry_run=False 명시 필요.
- state/action 은 enum 으로 제약(임의 값 차단).
- backend 가 안 떠 있거나 인증 실패 시 tool 은 예외로 죽지 않고 에러 문자열을 반환.

실행:
    python server.py           # stdio 로 대기 (클라이언트가 spawn)

환경변수:
    SLURM_BIN_DIR     - Slurm 바이너리 경로 (slurm_commands.py 가 사용, 기본 /usr/local/slurm/bin)
    SLURM_MCP_BACKEND - 변경계 REST 베이스 URL (기본 http://127.0.0.1:5010)
    SLURM_MCP_TOKEN   - 변경계 REST 호출용 JWT (Authorization: Bearer 헤더로 실림).
                        backend SSO_ENABLED=false 모드면 생략 가능(전권 부여). README 참고.
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
    from mcp.server.fastmcp import FastMCP
except ImportError:
    sys.stderr.write(
        "[mcp_slurm] 'mcp' 패키지를 찾을 수 없습니다.\n"
        "  이 서버는 공식 MCP Python SDK 가 필요합니다.\n"
        "  설치: pip install mcp   (requirements.txt 참고)\n"
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2) backend_5010 의 slurm_commands.py 직접 import (검증된 래퍼 재사용)
#    이 파일 위치: .../dashboard/mcp_slurm/server.py
#    대상:        .../dashboard/backend_5010/slurm_commands.py
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
# 3) 변경계 REST 프록시 설정 (Phase2)
#    write tool 은 backend_5010 의 인증/권한/감사 경계를 지나가야 하므로
#    slurm_commands 직접호출이 아니라 localhost REST 를 HTTP 로 호출한다.
# ---------------------------------------------------------------------------
_BACKEND_URL = os.getenv("SLURM_MCP_BACKEND", "http://127.0.0.1:5010").rstrip("/")
_MCP_TOKEN = os.getenv("SLURM_MCP_TOKEN", "").strip()
_HTTP_TIMEOUT = 15  # seconds


def _request_backend(method: str, path: str, body: dict):
    """backend_5010 변경계 REST 엔드포인트에 method(POST/PATCH) JSON 호출.

    표준 라이브러리 urllib 만 사용(requests 의존 회피).
    반환: (ok: bool, message: str). 절대 예외를 raise 하지 않는다 — tool 이 죽으면 안 됨.
    연결 실패/타임아웃/HTTP 에러/인증 실패를 전부 사람이 읽을 수 있는 문자열로 변환.
    """
    url = f"{_BACKEND_URL}{path}"
    data = json.dumps(body or {}).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if _MCP_TOKEN:
        headers["Authorization"] = f"Bearer {_MCP_TOKEN}"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT) as resp:
            raw = resp.read().decode("utf-8", "replace")
        prefix = "" if _MCP_TOKEN else (
            "[warning] SLURM_MCP_TOKEN 미설정 — 인증 헤더 없이 호출함 "
            "(backend SSO_ENABLED=false 가 아니면 401 일 수 있음)\n"
        )
        return True, prefix + raw

    except urllib.error.HTTPError as e:
        # 4xx/5xx — backend 가 응답은 했으나 거부/실패. 본문에 error 메시지 있음.
        detail = ""
        try:
            detail = e.read().decode("utf-8", "replace")
        except Exception:
            pass
        hint = ""
        if e.code in (401, 403):
            hint = (
                " (인증/권한 실패 — SLURM_MCP_TOKEN 환경변수에 유효한 JWT 를 넣었는지, "
                "또는 backend 가 SSO_ENABLED=false 인지 확인하세요)"
            )
        return False, f"error: HTTP {e.code} {e.reason}{hint}\n{detail}".strip()

    except urllib.error.URLError as e:
        # 연결 거부/DNS/타임아웃 — backend 가 안 떠 있을 가능성.
        return False, (
            f"error: backend({_BACKEND_URL}) 에 연결할 수 없습니다: {e.reason}. "
            "dashboard backend_5010 이 실행 중인지, SLURM_MCP_BACKEND 가 맞는지 확인하세요."
        )
    except Exception as e:  # noqa: BLE001 — tool 은 절대 죽지 않는다.
        return False, f"error: 예기치 못한 오류: {e}"


def _stdout(result) -> str:
    """
    CompletedProcess 에서 LLM 에 돌려줄 텍스트를 추출.
    실패(비정상 종료)면 stderr 도 함께 보여 디버깅이 가능하게 한다.
    """
    out = (result.stdout or "").strip()
    if result.returncode != 0:
        err = (result.stderr or "").strip()
        return f"[exit {result.returncode}]\n{out}\n{err}".strip()
    return out if out else "(no output)"


# ---------------------------------------------------------------------------
# 읽기전용 tools (slurm_commands 직접호출)
# 변경계 tools 는 아래 별도 섹션(REST 프록시)에 있습니다.
# ---------------------------------------------------------------------------

@mcp.tool()
def slurm_list_jobs() -> str:
    """현재 큐에 있는 Slurm 잡 목록을 반환합니다 (squeue).

    실행 중(R)/대기 중(PD) 잡의 JobID, 파티션, 사용자, 상태, 시간, 노드를
    한눈에 보여줍니다. 클러스터에 어떤 작업이 돌고 있는지 파악할 때 사용하세요.
    """
    return _stdout(get_squeue(check=False))


@mcp.tool()
def slurm_list_nodes() -> str:
    """클러스터 노드/파티션 요약을 반환합니다 (sinfo).

    파티션별 노드 상태(idle/alloc/mix/down 등)와 가용 노드 수를 보여줍니다.
    어떤 자원이 비어 있는지, 다운된 노드가 있는지 확인할 때 사용하세요.
    """
    return _stdout(get_sinfo(check=False))


@mcp.tool()
def slurm_list_partitions() -> str:
    """파티션 상세 구성을 반환합니다 (scontrol show partition).

    각 파티션의 노드 목록, 시간 제한(MaxTime), 상태(UP/DOWN), 우선순위 등
    상세 설정을 보여줍니다. 파티션 정책을 확인할 때 사용하세요.
    """
    return _stdout(get_scontrol("show", "partition", check=False))


@mcp.tool()
def slurm_job_accounting() -> str:
    """완료/실행 잡의 어카운팅 기록을 반환합니다 (sacct).

    잡의 종료 상태(COMPLETED/FAILED/CANCELLED), ExitCode, 경과 시간 등
    회계 데이터베이스(slurmdbd) 기반 이력을 보여줍니다. 과거 잡 결과를
    확인하거나 실패 잡을 분석할 때 사용하세요.
    """
    return _stdout(get_sacct(check=False))


@mcp.tool()
def slurm_cluster_health() -> str:
    """Slurm 설치/가용 여부를 점검합니다 (sinfo --version 기반).

    slurmctld 와의 통신 및 Slurm 바이너리 설치 상태를 확인합니다.
    'ok' 또는 'unavailable' 과 진단 메시지를 반환합니다. MCP 서버가 실제
    클러스터에 연결되는지 가장 먼저 확인할 때 사용하세요.
    """
    ok = check_slurm_installation()
    if ok:
        return "ok: Slurm 설치 확인됨 (sinfo --version 응답)"
    return (
        "unavailable: Slurm 명령에 응답이 없습니다. "
        "SLURM_BIN_DIR 환경변수 또는 slurmctld 상태를 확인하세요."
    )


@mcp.tool()
def slurm_scheduler_diag() -> str:
    """스케줄러 진단 통계를 반환합니다 (sdiag).

    메인 스케줄러/백필 스케줄러의 사이클 수, 큐 길이, 마지막 스케줄 시각 등
    스케줄러 성능 지표를 보여줍니다. 잡이 왜 안 돌아가는지, 스케줄러가
    밀리는지 진단할 때 사용하세요.
    """
    return _stdout(get_sdiag(check=False))


@mcp.tool()
def slurm_fairshare() -> str:
    """페어셰어(공정 사용량) 정보를 반환합니다 (sshare).

    계정/사용자별 할당된 share, 사용량(RawUsage), FairShare 점수를 보여줍니다.
    누가 자원을 많이 썼는지, 우선순위에 영향을 주는 공정성 지표를 확인할 때
    사용하세요.
    """
    return _stdout(get_sshare(check=False))


@mcp.tool()
def slurm_job_priority() -> str:
    """대기 잡의 우선순위 분해를 반환합니다 (sprio).

    각 대기(PD) 잡의 우선순위를 구성 요소(Age, FairShare, JobSize, Partition,
    QOS 등)별로 분해해 보여줍니다. 어떤 잡이 먼저 돌지, 우선순위가 왜 낮은지
    분석할 때 사용하세요.
    """
    return _stdout(get_sprio(check=False))


@mcp.tool()
def slurm_job_stat(job_id: str) -> str:
    """실행 중인 특정 잡의 실시간 자원 사용량을 반환합니다 (sstat).

    Args:
        job_id: 조회할 잡 ID (예: "12345" 또는 "12345.batch").

    실행 중(R) 잡의 CPU/메모리/디스크 사용량 등 라이브 통계를 보여줍니다.
    sstat 는 RUNNING 상태 잡에만 동작합니다. 완료된 잡은 slurm_job_accounting
    (sacct) 을 사용하세요.
    """
    job_id = str(job_id).strip()
    if not job_id:
        return "error: job_id 가 비어 있습니다."
    return _stdout(get_sstat("-j", job_id, check=False))


# ===========================================================================
# 변경계(write) tools — backend_5010 REST 프록시 (Phase2)
#
# ⚠️ 아래 tool 은 slurm_commands 직접호출이 아니라 backend 의 인증/권한/감사를
#    지나는 REST 엔드포인트를 HTTP 로 호출한다. 모든 tool 은 dry_run 기본 True.
#    실제 적용은 LLM 이 dry_run=False 를 명시해야만 일어난다.
# ===========================================================================

# node state -> (REST 경로 템플릿, reason 필요 여부, dry_run 지원 여부)
#   drain/resume REST 는 dry_run 미지원(즉시 실행) → dry_run=True 여도 경고 후 실행됨.
#   down/undrain REST(Phase2 추가)는 dry_run 지원.
_NODE_STATE_ROUTES = {
    "DRAIN": ("/api/nodes/drain", True, False),     # drain: reason 권장, dry_run 미지원
    "RESUME": ("/api/nodes/resume", False, False),  # dry_run 미지원
    "DOWN": ("/api/nodes/down", True, True),        # down: reason 필수, dry_run 지원
    "UNDRAIN": ("/api/nodes/undrain", False, True), # dry_run 지원
}


@mcp.tool()
def slurm_node_set_state(
    node: str,
    state: str,
    reason: str = "",
    dry_run: bool = True,
) -> str:
    """노드 상태를 변경합니다 (backend REST 프록시, 변경계/위험).

    ⚠️ 이것은 클러스터를 실제로 바꾸는 변경 작업입니다. backend_5010 의 인증/권한
    경계를 통과하는 REST(POST /api/nodes/{drain|resume|down|undrain})를 호출합니다.
    slurm_commands 를 직접 호출하지 않습니다.

    Args:
        node: 대상 노드 이름 (예: "cn01"). REST 본문 node_name 으로 전달.
        state: 다음 중 하나 (대소문자 무관):
            - DRAIN  : 새 잡 배정 중지, 실행 중 잡은 끝까지 유지 (점검 전 권장).
            - RESUME : DRAIN/DOWN 해제, 노드 정상 가동 복귀.
            - DOWN   : 노드를 강제 DOWN — 실행 중 잡이 죽을 수 있음. reason 필수. (가장 파괴적)
            - UNDRAIN: drain 사유만 제거(잡 유지). DOWN 노드를 살리진 않음.
        reason: 사유 문자열. DOWN 은 필수, DRAIN 은 권장. RESUME/UNDRAIN 은 무시됨.
        dry_run: True(기본)면 실제로 바꾸지 않고 생성될 명령/요청만 미리보기.
            실제 적용하려면 반드시 dry_run=False 를 명시하세요.

    동작/안전:
        - dry_run=True 면 변경 없음(미리보기). 사용자에게 확인받기 전 기본값을 유지하세요.
        - backend 가 안 떠 있으면 예외 없이 'error: ...' 문자열을 돌려줍니다.
        - state 가 enum 밖이면 호출조차 하지 않고 에러를 반환합니다.
    """
    node = str(node).strip()
    if not node:
        return "error: node 가 비어 있습니다."

    key = str(state).strip().upper()
    if key not in _NODE_STATE_ROUTES:
        return (
            f"error: state '{state}' 는 허용되지 않습니다. "
            f"가능: {sorted(_NODE_STATE_ROUTES.keys())}"
        )

    path, reason_required, supports_dry_run = _NODE_STATE_ROUTES[key]
    reason = str(reason).strip()
    if key == "DOWN" and not reason:
        return "error: state=DOWN 은 reason 이 필수입니다 (왜 내리는지 명시)."

    body = {"node_name": node, "dry_run": bool(dry_run)}
    # reason 은 drain/down 에서만 의미. resume/undrain REST 는 무시하므로 보내도 무해.
    if reason and reason_required:
        body["reason"] = reason

    # dry_run 미지원 REST(drain/resume)에 dry_run=True 가 오면 서버가 즉시 실행하므로
    # job_control 과 동일하게 경고만 붙인다(차단 않음 — LLM 판단 존중).
    ok, message = _request_backend("POST", path, body)
    if not supports_dry_run and dry_run and ok:
        message = (
            f"[warning] state '{key}' REST 는 dry_run 을 지원하지 않아 "
            "서버에서 즉시 실행되었습니다(미리보기 아님).\n" + message
        )
    return message


# job action -> (HTTP method, REST 경로 템플릿, body builder, dry_run 지원여부)
#   <id> 는 job_id 로 치환. body builder 는 (job_id, value, dry_run) -> dict.
def _body_dry_only(job_id, value, dry_run):
    return {"dry_run": bool(dry_run)}


def _body_priority(job_id, value, dry_run):
    return {"priority": value, "dry_run": bool(dry_run)}


def _body_nice(job_id, value, dry_run):
    return {"nice": value, "dry_run": bool(dry_run)}


# 주의: hold/release/cancel REST(app.py)는 dry_run/body 를 읽지 않는다(즉시 실행).
#       requeue/priority/nice/top REST(slurm_admin_api.py)는 dry_run 을 지원한다.
_JOB_ACTIONS = {
    "hold":     ("POST",  "/api/slurm/jobs/{id}/hold",     _body_dry_only, False),
    "release":  ("POST",  "/api/slurm/jobs/{id}/release",  _body_dry_only, False),
    "cancel":   ("POST",  "/api/slurm/jobs/{id}/cancel",   _body_dry_only, False),
    "requeue":  ("POST",  "/api/slurm/jobs/{id}/requeue",  _body_dry_only, True),
    "priority": ("POST",  "/api/slurm/jobs/{id}/priority", _body_priority, True),
    "nice":     ("POST",  "/api/slurm/jobs/{id}/nice",     _body_nice,     True),
    "top":      ("POST",  "/api/slurm/jobs/{id}/top",      _body_dry_only, True),
}


@mcp.tool()
def slurm_job_control(
    job_id: str,
    action: str,
    value: int = 0,
    dry_run: bool = True,
) -> str:
    """대기/실행 잡을 제어합니다 (backend REST 프록시, 변경계/위험).

    ⚠️ 클러스터를 실제로 바꾸는 변경 작업입니다. backend_5010 의 인증/권한 경계를
    통과하는 REST(/api/slurm/jobs/<id>/<action>)를 호출합니다. slurm_commands 직접호출 아님.

    Args:
        job_id: 대상 잡 ID (예: "12345").
        action: 다음 중 하나 (소문자):
            - hold    : 잡을 보류 — 스케줄링 중지(나중에 release 로 해제).
            - release : hold 해제 — 다시 스케줄링 가능.
            - requeue : 잡을 재큐(다시 PENDING). 실행 중이면 중단 후 재시작될 수 있음.
            - cancel  : 잡 취소(scancel) — 실행 중 작업이 종료됨. (파괴적, 되돌릴 수 없음)
            - priority: 우선순위를 value(0 이상 정수)로 설정. 관리자 권한 필요할 수 있음.
            - nice    : nice 값을 value(정수, 음수=우선순위↑)로 설정.
            - top      : 본인 큐에서 이 잡을 최상단으로 이동(비관리자도 가능).
        value: priority/nice 에서만 사용하는 정수. 그 외 action 에선 무시됨.
        dry_run: True(기본)면 실제로 바꾸지 않고 미리보기.
            실제 적용하려면 dry_run=False 명시.
            주의: hold/release/cancel REST 는 dry_run 을 지원하지 않아 dry_run=True 여도
            서버에서 즉시 실행됩니다. cancel 처럼 파괴적인 건 사용자 확인 후 호출하세요.

    동작/안전:
        - action 이 enum 밖이면 호출하지 않고 에러를 반환합니다.
        - priority/nice 는 value 가 정수여야 합니다(아니면 backend 가 400).
        - backend 가 안 떠 있으면 예외 없이 'error: ...' 문자열을 돌려줍니다.
    """
    job_id = str(job_id).strip()
    if not job_id:
        return "error: job_id 가 비어 있습니다."

    act = str(action).strip().lower()
    if act not in _JOB_ACTIONS:
        return (
            f"error: action '{action}' 는 허용되지 않습니다. "
            f"가능: {sorted(_JOB_ACTIONS.keys())}"
        )

    method, path_tmpl, body_builder, supports_dry_run = _JOB_ACTIONS[act]

    if act in ("priority", "nice"):
        try:
            value = int(value)
        except (TypeError, ValueError):
            return f"error: action '{act}' 는 value 가 정수여야 합니다 (받은 값: {value!r})."

    path = path_tmpl.format(id=job_id)
    body = body_builder(job_id, value, dry_run)

    # dry_run 미지원 REST(hold/release/cancel)에 dry_run=True 가 오면, 서버가 즉시
    # 실행해버리므로 사용자에게 경고만 붙여 명확히 한다(차단하지는 않음 — LLM 판단 존중).
    ok, message = _request_backend(method, path, body)
    if not supports_dry_run and dry_run and ok:
        message = (
            f"[warning] action '{act}' REST 는 dry_run 을 지원하지 않아 "
            "서버에서 즉시 실행되었습니다(미리보기 아님).\n" + message
        )
    return message


if __name__ == "__main__":
    # stdio 트랜스포트로 실행 (클라이언트가 이 프로세스를 spawn 하고 stdin/stdout 으로 통신)
    mcp.run()
