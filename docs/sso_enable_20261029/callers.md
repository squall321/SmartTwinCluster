# 운영 SSO 켜기 전 — 토큰 없이 대시보드(backend_5010)를 부르는 쪽

**날짜** 2026-10-29 · **계기** 사용자 결정 「켜기 전에 영향부터 조사」(kooremapper-4a 전달)
**범위** 이 리포 전체, 이 박스의 다른 리포(/home/koopark/claude/*). 운영 머신(icn401·cae00)의 설정 파일은 보지 못했다.

## 0. 요약

- SSO 를 켜면 깨지는 것은 `@jwt_required` 라우트(75개)에 토큰 없이 오는 호출이다. 인증 데코레이터가 없는 라우트(140개)는 그대로 열려 있다.
- **반드시 고칠 것은 하나** — DynaForge 덱 업로드(`StcxUploader`). §2 에 토큰 제안.
- **KooSlurm 화면 3곳**은 헤더 없이 보호 라우트를 불렀다 → 고침(`f267c127`).
- **이미 막혀 있을 수 있는 길** — HWAX 게이트웨이가 smarttwin_mcp(:5013)·mcp_slurm(:5012)에 Authorization 을 싣지 않는다(이 박스 `gateway_config.json`).
  smarttwin_mcp 는 토큰이 없으면 제출·조회 도구를 거부하므로(fail-closed) SSO 와 무관하게 게이트웨이 경유 제출은 지금도 안 된다. 운영 게이트웨이 설정 확인 필요(§3).
- **신원이 바뀐다** — 지금은 모든 호출이 `admin` 이다. 켜면 실제 사용자가 되므로 켜기 전 잡·업로드는 그 사용자에게 안 보인다(§4).

## 1. 켜면 깨지는 호출자

| 라우트 | 부르는 앱·파일 | 지금 싣는 인증 | 켜면 | 조치 |
|---|---|---|---|---|
| `POST /api/v2/files/upload/{init,chunk,complete}`, `DELETE /api/v2/files/uploads/<id>` (jwt + `dashboard` 권한) | KooRemapper `platform/backend/app/runner/stcx_client.py` `StcxUploader`(669-802), `worker/runner_loop.py` 417·495 | 없음 | 401 — 덱 업로드 실패 | DynaForge 가 토큰을 싣는다(§2) |
| `POST /api/nodes/{drain,resume,reboot}` | frontend_3010 `NodeManagement/index.tsx` 148·201 | 없음(raw fetch) | 401 | 고침 `f267c127` |
| `POST /api/slurm/partitions/<p>/state`, `/api/slurm/jobs/<id>/{requeue,hold,release,top}` (dry_run 미리보기·실행) | frontend_3010 `SlurmManagement/index.tsx` 82·93 | 없음 | 401 | 고침 `f267c127` |
| `GET /api/v2/files/uploads/<id>` | frontend_3010 `hooks/useFileUpload.ts` 112 | 없음(업로드 자체는 토큰 실음) | 업로드 뒤 조회만 401 | 고침 `f267c127` |
| `GET /api/vnc/images`, `/api/vnc/nodes` | `dashboard/start_production.sh` 939·940 (진단 출력) | 없음 | 진단 줄만 401, 스크립트는 계속 | 그대로 둔다 |
| VNC 끝단 시험 | `start_production.sh` 1085~ | auth_portal `test/login` JWT | SSO 켜짐이면 test/login 이 403 → 시험을 건너뜀(스크립트가 처리) | 그대로 둔다 |
| 수동 시험 스크립트 | `dashboard/check_backend_status.py` 46, `test_apply_api.py` 35, `MoonlightSunshine_8004/test_all_services.sh` 103 | 없음 | 401 | 손으로 돌리는 도구 — 필요할 때 토큰 추가 |

## 2. DynaForge 덱 업로드에 실을 토큰 — 제안

**7-1 과 같은 것, 예약한 사용자 본인의 `kst_` PAT** 를 업로드·삭제 네 호출에 `Authorization: Bearer` 로 싣는다.
그 PAT 는 도구 인자로 나르지 않고 **위임 창구** `POST /api/auth/sso` 로 그때그때 받는다(사용자 결정 10-29, 규격은 context-notes.md).
**보류(10-29)** — 지금 제출은 게이트웨이 경유 단일 신원(smarttwin-mcp `STMC_CLUSTER_TOKEN`)이라, 업로드만 잡 소유자로 바꾸면 켜는 순간
제출이 업로드 경로를 거절한다. 업로드 신원은 제출 신원과 함께 SSO 를 켤 때 정한다(sso_enable_procedure.md §0 조건 5).

- 업로드는 토큰 사용자 폴더 `/shared/uploads/users/<user>/data/…` 에 놓인다(`file_classifier.get_storage_path`).
  smarttwin_mcp 는 입력 파일을 **호출자 본인의** `/shared/uploads/users/{user}` 아래에서만 받는다(`STMC_INPUT_ROOTS` 기본값).
  업로드와 제출이 같은 사용자의 PAT 여야 이 둘이 맞는다.
- 삭제(`cancel_upload`)는 올린 사람만(또는 HPC-Admins) — 업로드와 같은 PAT.
- PAT 소유자에게 `dashboard` 권한이 있어야 한다(PAT 는 발급 때 사용자의 권한을 복사한다).
- 서비스 계정·admin PAT 는 권하지 않는다 — 모든 업로드·잡이 한 사람으로 뭉치고, 사용자별 소유 검사가 무력해진다.

## 3. 게이트웨이 경유 MCP — 확인과 결정이 필요

| 경로 | 지금(이 박스) | SSO 와의 관계 |
|---|---|---|
| HWAXMcpGateway `smart-twin-mcp` → :5013 | `headers` 없음, `per_user_sso` 아님 → Authorization 없이 호출 | smarttwin_mcp 는 토큰이 없으면 백엔드를 부르는 도구(제출·조회·rerun)를 거부한다. **SSO 와 무관하게 지금도 막힘**(SSO 꺼짐이라도 토큰이 비면 도구가 먼저 거절) |
| HWAXMcpGateway `smart-twin-cluster` → :5012(mcp_slurm) | 같음 | mcp_slurm 은 토큰을 그대로 넘긴다. SSO 꺼짐이면 빈 토큰도 admin 으로 통과, 켜면 401 |
| KooRemapper `StcxClient`(stcx_client.py 805-879) → 게이트웨이 → :5013 | 게이트웨이에만 `KOORM_GATEWAY_PAT` | 위와 같다 |

길은 둘이다. 어느 쪽이든 PAT 는 예약자 본인의 것이다.
- (가) 게이트웨이 `per_user_sso` 에 smart-twin 두 항목을 넣어 사용자별 `kst_` 를 싣는다(게이트웨이의 기존 위임 방식).
- (나) DynaForge 가 7-1 처럼 smarttwin_mcp 를 예약자 PAT 로 직접 부른다.

## 4. 신원이 바뀌는 영향(켜는 순간)

- SSO 꺼짐에서는 토큰이 무엇이든 `admin`. 그래서 지금까지의 제출 기록(`job_submissions.user_id`)·결과 폴더(`/data/single/admin/…`)·업로드(`/shared/uploads/users/admin/…`)는 모두 `admin` 명의다.
- 켜면 실제 사용자 명의가 된다. **켜기 전 잡은 일반 사용자 PAT 로 403**(A 의 소유 검사) — DynaForge 7-1 이 켜기 전 예약을 들고 있으면 그 잡은 귀환이 막힌다.
  켜는 시각을 진행 중 예약이 없을 때로 잡거나, 그 잡들만 admin 이 처리한다.
- MCP 사용자도 같다 — PAT 는 DB 에 살아 있는 것이어야 하고, 일반 사용자 PAT 는 예약·노드·파티션 관리에 403.

## 5. 켜도 열려 있는 쓰기 라우트(참고 — 깨지지는 않음)

`/api/yaml/init-startup`, `/api/apptainer/scan`, `/api/jobs/templates/scan`, `/api/health/auto-heal`, `/api/slurm/sync-nodes`,
`/api/storage/scratch/{move,delete}`, `/api/notifications`(POST·DELETE), `/api/cache/invalidate`, `/api/jobs/upload-file`.
설치 스크립트·화면이 토큰 없이 부르므로 막으려면 그쪽을 같이 고쳐야 한다. SSO 켜기와 별도 과제.

## 6. 켤 때 바꿀 것(참고)

설치된 systemd 유닛(dashboard_backend·auth_backend·cae_backend·cae_automation·websocket_service)에 `SSO_ENABLED=false` 가 박혀 있다.
YAML `sso.enabled`, 유닛 env, nginx 정본 conf(start_production.sh 가 SSO 값으로 고른다)를 함께 바꿔야 한다.

## 7. 문제 없는 것

- smarttwin_mcp(:5013)·mcp_slurm(:5012) 자체 — 들어온 Authorization 을 그대로 넘긴다.
- 헬스 체크(`/api/health`, `/metrics`, `/api/vnc/health`) — 인증 데코레이터 없음, 그대로 둔다.
- 백엔드 자기 호출(`health_check_api.py`), 설치·배포 스크립트의 scan·init 호출 — 인증 없는 라우트.
- 잡 템플릿·백엔드가 만드는 잡 스크립트·Slurm prolog/epilog·cron — 대시보드를 부르지 않는다.
- DynaForge 7-1(`kooslurm_client.py`, 작업 중) — 처음부터 예약자 `kst_` PAT.
