# mcp_slurm — Slurm MCP 서버 (읽기전용 + 변경계 REST 프록시)

LLM 클라이언트(Claude Desktop, Claude Code 등)가 **Model Context Protocol(MCP)** 로
Slurm 클러스터를 **조회(읽기)** 및 **제어(변경)** 하게 해주는 stdio 서버입니다.

## 무엇

- `mcp.server.fastmcp.FastMCP` 기반의 별도 stdio MCP 서버 (`server.py`).
- **읽기전용 tool**: `../backend_5010/slurm_commands.py` 의 검증된 래퍼 함수를 **직접 import 재사용**
  → Slurm 명령 경로 / `SLURM_BIN_DIR` 환경변수 / 타임아웃 처리를 단일 소스에서 관리.
- **변경(write) tool**: slurm_commands 를 직접 호출하지 **않고**, `backend_5010` 의
  변경계 **REST API 를 HTTP 로 프록시**합니다(표준 라이브러리 `urllib`).
  → JWT 인증 / `permission_required` 권한 / 감사 경계를 **우회하지 않기** 위함.

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

### 제공 tools (변경계 / write — REST 프록시)

변경계 tool 은 `backend_5010` 의 변경계 REST 를 호출합니다. 직접 Slurm 을 건드리지 않습니다.
**모든 write tool 은 `dry_run` 기본값이 `True`** 입니다 — 실제 적용하려면 LLM 이
`dry_run=False` 를 명시해야 합니다.

| Tool | 호출 REST | 설명 |
| --- | --- | --- |
| `slurm_node_set_state(node, state, reason, dry_run=True)` | `POST /api/nodes/{drain\|resume\|down\|undrain}` | 노드 상태 변경. `state ∈ {DRAIN, RESUME, DOWN, UNDRAIN}` (enum 강제). `DOWN` 은 `reason` 필수. |
| `slurm_job_control(job_id, action, value, dry_run=True)` | `/api/slurm/jobs/<id>/<action>` | 잡 제어. `action ∈ {hold, release, requeue, cancel, priority, nice, top}` (enum 강제). `priority`/`nice` 는 `value`(정수) 사용. |

위험도 / `dry_run` 주의:

- **`DOWN` / `cancel` 은 파괴적**입니다(실행 중 잡 종료). 반드시 사용자 확인 후 호출하세요.
- `slurm_node_set_state` 의 `DOWN`/`UNDRAIN` REST 와, `slurm_job_control` 의
  `requeue`/`priority`/`nice`/`top` REST 는 서버단에서 **`dry_run` 을 실제로 지원**합니다
  (`dry_run=True` 면 생성될 `scontrol` 명령 문자열만 반환, 미적용).
- 단, **`hold` / `release` / `cancel` REST(`app.py`)는 `dry_run` 을 지원하지 않아**
  `dry_run=True` 로 불러도 서버가 **즉시 실행**합니다. 이 경우 tool 응답 앞에
  `[warning] ... 즉시 실행되었습니다` 가 붙습니다.
- `drain`/`resume` REST 도 현재 서버단 `dry_run` 미지원(즉시 실행) — `down`/`undrain` 만 지원.
  `drain`/`resume` 을 `dry_run=True` 로 불러도 즉시 실행되며, hold/release/cancel 과 동일하게
  tool 응답 앞에 `[warning] ... 즉시 실행되었습니다` 가 붙습니다.
- backend 가 안 떠 있으면 tool 은 예외로 죽지 않고 `error: backend(...) 에 연결할 수 없습니다 ...`
  문자열을 반환합니다.

## 인증 (변경계 REST 호출용 토큰)

변경계 REST 는 `@jwt_required` 로 보호됩니다(`Authorization: Bearer <JWT>` 필요).
MCP 서버는 **`SLURM_MCP_TOKEN` 환경변수의 토큰을 그대로 `Authorization: Bearer` 헤더에 실어** 보냅니다.

- `SLURM_MCP_TOKEN` 이 **설정돼 있으면** → 그 JWT 로 인증 시도. (Auth Portal 발급 토큰)
- `SLURM_MCP_TOKEN` 이 **없으면** → 헤더 없이 호출하고, 응답 앞에
  `[warning] SLURM_MCP_TOKEN 미설정 ...` 경고를 붙입니다.
  backend 가 `SSO_ENABLED=false` 모드(전권 부여)면 토큰 없이도 동작하지만,
  그 외에는 `401` 을 받습니다.
- `401/403` 응답 시 tool 은 토큰/SSO 확인 힌트를 포함한 에러 문자열을 돌려줍니다.

> ⚠️ **현 구현은 최소 수준**입니다: env 토큰을 그대로 헤더에 싣기만 하며,
> 토큰 만료/갱신/자동 로그인은 처리하지 않습니다. 장기 운영 시 단기 토큰 갱신 또는
> backend 측 내부 호출 전용 경로(서비스 토큰) 설계를 권장합니다. (아래 '한계' 참고)

## 실행법

```bash
# 1) 의존성 설치 (오프라인 환경이면 사내 미러/휠 사용)
pip install -r requirements.txt

# 2) 서버 실행 (stdio 로 대기 — 보통은 직접 실행하지 않고 클라이언트가 spawn)
python server.py
```

환경변수:

- `SLURM_BIN_DIR` — Slurm 바이너리 경로. 기본 `/usr/local/slurm/bin`.
  apt/yum 패키지 설치 환경이면 `/usr/bin` 으로 지정. (읽기전용 tool 이 사용)
- `SLURM_MCP_BACKEND` — 변경계 REST 베이스 URL. 기본 `http://127.0.0.1:5010`.
  (변경계 tool 이 이 주소로 `urllib` HTTP 호출)
- `SLURM_MCP_TOKEN` — 변경계 REST 호출용 JWT. `Authorization: Bearer` 헤더로 실립니다.
  미설정이면 헤더 없이 호출(경고 부착). backend `SSO_ENABLED=false` 면 생략 가능.
  자세한 내용은 위 **인증** 절 참고.

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
        "SLURM_BIN_DIR": "/usr/local/slurm/bin",
        "SLURM_MCP_BACKEND": "http://127.0.0.1:5010",
        "SLURM_MCP_TOKEN": "<Auth Portal 발급 JWT 또는 생략(SSO off 시)>"
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

## 한계 (현 구현)

- 변경계 인증은 **env 토큰을 헤더에 싣는 최소 구현**입니다. 토큰 만료/갱신/자동
  로그인 미처리 — 만료되면 `401` 을 받고 tool 은 힌트 문자열을 반환합니다.
  장기 운영 시: (a) Auth Portal 단기 토큰 주기 갱신, 또는 (b) backend 측 내부 호출
  전용 서비스 토큰/네트워크 경계(127.0.0.1 only) 설계를 권장합니다.
- `hold`/`release`/`cancel`/`drain`/`resume` REST 는 서버단 `dry_run` 미지원이라
  `dry_run=True` 로 불러도 즉시 실행됩니다(tool 이 경고 부착). 진짜 미리보기가 필요하면
  backend 측 해당 라우트에 `dry_run` 분기를 추가해야 합니다(향후 과제).

## 파일

- `server.py` — MCP 서버 본체 (읽기전용 tool 직접호출 + 변경계 tool REST 프록시).
- `requirements.txt` — `mcp` SDK 의존성 (보수적 버전핀).
- `mcp-slurm.service.example` — systemd 유닛 예시 (참고용).
