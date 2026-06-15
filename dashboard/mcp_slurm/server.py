#!/usr/bin/env python3
"""
Slurm 읽기전용 MCP 서버 (stdio)

LLM 클라이언트(Claude Desktop, Claude Code 등)가 Slurm 클러스터 상태를
읽기 전용으로 조회할 수 있게 해주는 MCP 서버입니다.

설계:
- mcp.server.fastmcp.FastMCP 기반 별도 stdio 서버
- 기존 backend_5010/slurm_commands.py 의 검증된 래퍼 함수를 직접 import 재사용
  (Slurm 명령 경로/환경변수/타임아웃 처리를 단일 소스에서 관리)

읽기전용 원칙:
- 이번 Phase1 에서는 조회(squeue/sinfo/sacct/scontrol show/sdiag/sshare/sprio/sstat)
  계열만 노출합니다.
- scancel/scontrol update/sacctmgr 등 mutating(변경) tool 은 의도적으로 제외합니다.
  write tools = Phase2 에서 REST 프록시(backend_5010 의 인증/권한 경유)로 별도 노출 예정.

실행:
    python server.py           # stdio 로 대기 (클라이언트가 spawn)

환경변수:
    SLURM_BIN_DIR  - Slurm 바이너리 경로 (slurm_commands.py 가 사용, 기본 /usr/local/slurm/bin)
"""

import os
import sys

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
# 읽기전용 tools
# (mutating tools = Phase2, REST 프록시 — 여기 추가 금지)
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


if __name__ == "__main__":
    # stdio 트랜스포트로 실행 (클라이언트가 이 프로세스를 spawn 하고 stdin/stdout 으로 통신)
    mcp.run()
