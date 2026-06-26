# mcp_slurm — Slurm MCP 서버 (HTTP/stdio, 읽기전용 + 변경계 REST 프록시)

LLM 클라이언트(Claude Desktop, Claude Code 등)가 **Model Context Protocol(MCP)** 로
Slurm 클러스터를 **조회(읽기)** 및 **제어(변경)** 하게 해주는 서버입니다.

기본은 **HTTP(streamable) 트랜스포트**(`127.0.0.1:5012/mcp`)로, 원격 노트북의
Claude Desktop/Code 도 접속할 수 있습니다. 사용자별 토큰(PAT)을 `Authorization` 헤더로
받아 backend 가 검증하므로 **그 사용자 권한**으로 동작합니다(만능 토큰 없음).

## 무엇

- `mcp.server.fastmcp.FastMCP` 기반 MCP 서버 (`server.py`). transport 는 env 로 전환:
  - **`streamable-http`(기본)** — 원격 Claude 가 `mcp-remote` 브리지로 접속.
  - **`stdio`** — 기존 동작(클라이언트가 로컬에서 직접 spawn). 단일 사용자.
- **읽기전용 tool**: `../backend_5010/slurm_commands.py` 의 검증된 래퍼 함수를 **직접 import 재사용**.
  단, HTTP 노출 시 무인증 조회를 막기 위해 backend `/api/me` 로 토큰을 **검증(게이트)** 한 뒤 실행.
- **변경(write) tool**: slurm_commands 직접 호출이 아니라 `backend_5010` 의 변경계 **REST 를 프록시**.
  JWT 인증 / `permission_required` 권한 / 감사 경계를 **우회하지 않기** 위함.

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
| `slurm_job_results(job_id)` | backend `/api/jobs/<id>/info`+`/files` | **완료 잡 결과** — 상태/종료코드/작업디렉토리 + 결과 파일 목록(d3plot/binout/csv/로그) |
| `slurm_job_log(job_id, lines, log_type)` | backend `/api/jobs/<id>/logs/tail` | 잡 stdout/stderr 로그 마지막 N줄(시뮬 출력/에러 분석) |

### 제공 tools (변경계 / write — REST 프록시)

**모든 write tool 은 `dry_run` 기본값이 `True`** 입니다 — 실제 적용은 `dry_run=False` 명시 필요.

| Tool | 호출 REST | 설명 |
| --- | --- | --- |
| `slurm_node_set_state(node, state, reason, dry_run=True)` | `POST /api/nodes/{drain\|resume\|down\|undrain}` | 노드 상태 변경(enum 강제). `DOWN` 은 `reason` 필수·파괴적. |
| `slurm_job_control(job_id, action, value, dry_run=True)` | `/api/slurm/jobs/<id>/<action>` | 잡 제어(enum 강제). `priority`/`nice` 는 `value`. `cancel` 파괴적. |

> 모든 변경계 REST(`hold`/`release`/`cancel`/`drain`/`resume`/`down`/`undrain`/`requeue`/`priority`/`nice`/`top`/
> 파티션 state)는 서버단 `dry_run` 을 지원합니다 — `dry_run=True`(기본)면 생성될 명령만 반환하고 적용하지 않습니다.

## 인증 (★권장: 웹에서 토큰 발급★)

변경계 REST 와 읽기 게이트는 `@jwt_required` 로 보호됩니다. MCP 서버는 인증을 스스로
판단하지 않고, **들어온 요청의 `Authorization` 헤더를 backend 로 전달**해 backend 가
PAT(개인 액세스 토큰) 또는 JWT 를 검증하게 합니다.

1. **웹 대시보드 → 사이드바 「MCP 토큰 (Claude 연동)」** 메뉴에서 토큰을 발급합니다.
   - 발급된 평문 토큰(`kst_…`)은 **그 화면에서 1회만** 노출됩니다(서버는 sha256 해시만 저장).
   - 같은 화면이 **토큰을 박은 Claude Code/Desktop 등록 명령**을 바로 복사할 수 있게 보여줍니다.
   - 유출 시 그 화면에서 삭제하면 즉시 무효화됩니다(만료 기본 90일).
2. 이 토큰을 클라이언트가 `Authorization: Bearer kst_…` 로 보내면, backend 가
   토큰에 묶인 사용자/역할로 권한을 적용합니다(파티션 접근·변경 권한 등).

> backend 가 `SSO_ENABLED=false` 모드면 토큰 없이도 동작합니다(전권 부여 — 개발/기본).
> 운영(`SSO_ENABLED=true`)에서는 유효한 PAT 가 없으면 `401` 입니다.

## 실행법

```bash
# 1) 의존성 설치
#  [오프라인 운영서 — 권장] repo 동봉 wheel 로 venv 생성 + 설치 + 검증을 한 번에:
./install_offline.sh                 # ./venv 생성 (OS/파이썬 버전 자동 감지)
#  [인터넷 가능 환경]
pip install -r requirements.txt

# 2) 서버 실행 (HTTP 기본 — 127.0.0.1:5012/mcp)
SLURM_MCP_BACKEND=http://127.0.0.1:5010 ./venv/bin/python server.py
#  stdio 로 쓰려면:
MCP_TRANSPORT=stdio ./venv/bin/python server.py
```

HTTP 모드는 보통 **systemd 데몬**으로 상시 기동합니다(아래 systemd 절). stdio 모드는
클라이언트가 직접 spawn 하므로 데몬이 필요 없습니다.

### 오프라인 설치 (인터넷 없는 운영서)

`mcp` SDK + 의존성(starlette/uvicorn/pydantic-core 등 네이티브 포함)을 repo 에 동봉했습니다.

| OS | 파이썬 | wheel 위치 |
| --- | --- | --- |
| Ubuntu 22.04 | 3.10 (cp310) | `offline_packages/python_wheels/mcp/python3.10/` |
| Ubuntu 22.04 (alt) | 3.12 | `offline_packages/python_wheels/mcp/python3.12/` |
| Ubuntu 24.04 | 3.12 (cp312) | `offline_packages_2404/python_wheels/mcp/python3.12/` |

`install_offline.sh` 가 OS/파이썬을 감지해 `pip install --no-index --find-links=<dir>` 로 설치합니다.

## 환경변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `MCP_TRANSPORT` | `streamable-http` | `streamable-http`(원격 가능) \| `stdio`(로컬 spawn) |
| `MCP_HOST` | `127.0.0.1` | HTTP 바인딩 호스트. 외부 노출 시 `0.0.0.0` + `MCP_ALLOWED_HOSTS` |
| `MCP_PORT` | `5012` | HTTP 바인딩 포트 |
| `MCP_ALLOWED_HOSTS` | (없음) | 비-localhost 바인딩 시 허용 Host(쉼표구분). 예: `slurm.example.com,10.0.0.5:5012` |
| `SLURM_MCP_BACKEND` | `http://127.0.0.1:5010` | backend REST 베이스 URL(인증 게이트 + 변경계 프록시) |
| `SLURM_BIN_DIR` | `/usr/local/slurm/bin` | Slurm 바이너리 경로(읽기 tool). apt 설치면 `/usr/bin` |
| `SLURM_MCP_TOKEN` | (없음) | **stdio 모드 폴백 토큰**. HTTP 모드는 요청 헤더가 우선 |

> 외부망 노출 시 `MCP_ALLOWED_HOSTS` 를 지정해 DNS rebinding 보호를 유지하세요.
> 미지정 + 비-localhost 바인딩이면 보호가 꺼지므로(인증은 PAT, 망 보호는 nginx/방화벽 가정)
> 사내망 한정으로만 쓰세요.

## MCP 클라이언트 등록

> **가장 쉬운 길**: 웹 대시보드 「MCP 토큰 (Claude 연동)」 메뉴에서 토큰을 발급하면
> 아래 명령들이 **토큰까지 박힌 상태로** 화면에 나옵니다 — 복사해서 붙이기만 하면 됩니다.

접속 주소는 **대시보드와 같은 오리진의 `/mcp`** 입니다(nginx 가 내부 `127.0.0.1:5012` streamable-http
로 프록시 — TLS·단일포트, PAT 암호화 전송). 데몬은 loopback 바인딩을 유지합니다.

- **Claude Code**: 네이티브 HTTP 트랜스포트로 `/mcp` 에 직접 연결(Node/npx 불필요).
- **Claude Desktop**: 설정 파일은 stdio(command) 서버만 받으므로 `npx mcp-remote` 브리지로 연결(Node.js 필요).
- ※ 사설(self-signed) 인증서 환경이면 클라이언트가 그 인증서를 신뢰하도록 설정해야 합니다
  (Claude Code: `NODE_EXTRA_CA_CERTS`, Desktop: `NODE_OPTIONS=--use-system-ca` 또는 정식 인증서 권장).

### Claude Code (터미널)

```bash
claude mcp add --transport http slurm-mcp https://<host>/mcp \
  --header "Authorization: Bearer kst_<발급받은토큰>"
```

등록 확인: `claude mcp list` / 세션 내 `/mcp`.

### Claude Desktop (설정 파일)

설정 → 개발자 → 「설정 편집」으로 `claude_desktop_config.json` 을 열고, 아래 항목을
`"mcpServers": { }` 중괄호 안에 붙여넣은 뒤 Claude Desktop 재시작:

```json
"slurm-mcp": {
  "command": "npx",
  "args": ["-y", "mcp-remote", "https://<host>/mcp",
           "--header", "Authorization:${AUTH}"],
  "env": { "AUTH": "Bearer kst_<발급받은토큰>", "NODE_OPTIONS": "--use-system-ca" }
}
```

파일에 `mcpServers` 가 없으면 `{ "mcpServers": { 여기 } }` 로 감싸고, 다른 항목이 있으면 쉼표로 구분.

### (참고) stdio 로컬 등록

같은 머신(헤드노드)에서 Claude Code 를 쓰면 stdio 도 가능합니다:

```bash
claude mcp add slurm-mcp \
  -e MCP_TRANSPORT=stdio \
  -e SLURM_MCP_TOKEN=kst_<토큰> \
  -- /path/to/dashboard/mcp_slurm/venv/bin/python /path/to/dashboard/mcp_slurm/server.py
```

## systemd (HTTP 데몬)

HTTP 모드는 상시 데몬으로 운영합니다. `mcp-slurm.service.example` 참고
(`install_services.sh` 가 `__SERVICE_USER__`/`__PROJECT_HOME__` placeholder 치환).

## 한계 (현 구현)

- 읽기 게이트/변경계는 backend 가 떠 있어야 동작합니다(인증을 backend 가 검증). backend 불가 시
  tool 은 예외 없이 에러 문자열을 반환합니다.
- PAT 는 발급 시점의 신원(역할/그룹)을 스냅샷합니다 — 발급 후 역할이 바뀌면 토큰을 재발급하세요.

## 파일

- `server.py` — MCP 서버(읽기 게이트+직접호출 / 변경계 REST 프록시, HTTP·stdio 양용).
- `requirements.txt` — `mcp` SDK 의존성.
- `install_offline.sh` — 오프라인 wheel 설치 + venv 생성 + 검증.
- `mcp-slurm.service.example` — systemd 유닛 예시(HTTP 데몬).
