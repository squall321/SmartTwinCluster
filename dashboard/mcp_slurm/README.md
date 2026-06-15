# mcp_slurm — Slurm 읽기전용 MCP 서버

LLM 클라이언트(Claude Desktop, Claude Code 등)가 **Model Context Protocol(MCP)** 로
Slurm 클러스터 상태를 **읽기 전용**으로 조회하게 해주는 stdio 서버입니다.

## 무엇

- `mcp.server.fastmcp.FastMCP` 기반의 별도 stdio MCP 서버 (`server.py`).
- 기존 `../backend_5010/slurm_commands.py` 의 검증된 래퍼 함수를 **직접 import 재사용**
  → Slurm 명령 경로 / `SLURM_BIN_DIR` 환경변수 / 타임아웃 처리를 단일 소스에서 관리.
- 노출 tool 은 전부 **읽기전용**입니다. (변경 명령 미포함)

### 제공 tools (읽기전용)

| Tool | Slurm 명령 | 용도 |
|------|-----------|------|
| `slurm_list_jobs` | `squeue` | 현재 큐 잡 목록 |
| `slurm_list_nodes` | `sinfo` | 노드/파티션 상태 요약 |
| `slurm_list_partitions` | `scontrol show partition` | 파티션 상세 구성 |
| `slurm_job_accounting` | `sacct` | 완료/실행 잡 어카운팅 이력 |
| `slurm_cluster_health` | `sinfo --version` | Slurm 설치/가용 점검 |
| `slurm_scheduler_diag` | `sdiag` | 스케줄러 진단 통계 |
| `slurm_fairshare` | `sshare` | 페어셰어(공정 사용량) |
| `slurm_job_priority` | `sprio` | 대기 잡 우선순위 분해 |
| `slurm_job_stat(job_id)` | `sstat -j <id>` | 실행 잡 실시간 자원 사용량 |

> **변경(mutating) tool 은 이번 Phase1 에서 제외**했습니다.
> `scancel` / `scontrol update` / `sacctmgr` 등 write 계열은 **Phase2** 에서
> `backend_5010` REST API(인증/권한 경유) 프록시로 별도 노출할 예정입니다.

## 실행법

```bash
# 1) 의존성 설치 (오프라인 환경이면 사내 미러/휠 사용)
pip install -r requirements.txt

# 2) 서버 실행 (stdio 로 대기 — 보통은 직접 실행하지 않고 클라이언트가 spawn)
python server.py
```

환경변수:

- `SLURM_BIN_DIR` — Slurm 바이너리 경로. 기본 `/usr/local/slurm/bin`.
  apt/yum 패키지 설치 환경이면 `/usr/bin` 으로 지정.

## MCP 클라이언트 등록 (`.mcp.json`)

이 서버는 **stdio 트랜스포트**입니다. 보통 별도 데몬으로 띄우지 않고,
MCP 클라이언트가 아래 설정을 보고 프로세스를 **직접 spawn** 합니다.

`.mcp.json` 예시 (Claude Code 프로젝트 루트 또는 클라이언트 설정):

```json
{
  "mcpServers": {
    "slurm-readonly": {
      "command": "python",
      "args": [
        "/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/mcp_slurm/server.py"
      ],
      "env": {
        "SLURM_BIN_DIR": "/usr/local/slurm/bin"
      }
    }
  }
}
```

> `command` 는 `mcp` 패키지가 설치된 파이썬을 가리켜야 합니다.
> 프로젝트 venv 를 쓴다면 venv 의 절대경로 python 으로 바꾸세요. 예:
> `/home/koopark/claude/KooSlurmInstallAutomationRefactory/venv/bin/python`

## systemd (참고용)

stdio 서버라 보통은 클라이언트가 직접 spawn 하므로 systemd 서비스가 필요 없습니다.
다만 항상 떠 있는 데몬 형태로 운영하고 싶을 때를 대비해
`mcp-slurm.service.example` 을 참고용으로 동봉했습니다
(`backend_5010` 의 `dashboard-backend.service` 패턴을 본떠 작성).

## 파일

- `server.py` — MCP 서버 본체 (읽기전용 tool 정의).
- `requirements.txt` — `mcp` SDK 의존성 (보수적 버전핀).
- `mcp-slurm.service.example` — systemd 유닛 예시 (참고용).
