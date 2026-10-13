<!-- 구 mcp_slurm 미이관 관리 도구 11종을 smarttwin_mcp 카탈로그로 옮기는 계획·체크리스트·컨텍스트 노트 -->
# 미이관 관리 도구 이관 계획 (mcp_slurm → smarttwin_mcp)

## 배경

nginx `/mcp`와 클라이언트는 smarttwin_mcp(:5013)만 쓴다. 구 MCP 서버 `dashboard/mcp_slurm/`(:5012)은
운영에서 stcx 요청(2026-10-14)에 따라 폴백으로 유지되지만(dev 서비스는 내림) 라우팅되지 않는다. 그래서
mcp_slurm 19개 도구 중 smarttwin_mcp에 대응 도구가 없는 아래 11개는 지금 MCP로 쓸 수 없다.
원본 구현은 `dashboard/mcp_slurm/server.py`에 그대로 있다.

목표는 이 11개 기능을 smarttwin_mcp 카탈로그 도구로 다시 제공하는 것이다. 이관이 끝나야 mcp_slurm 은퇴를
다시 검토할 수 있다. 단, 구 구현을 그대로
옮기지 않고 이관 과정에서 발견된 인증·권한·입력검증 구멍을 함께 막는다.

비범위.
- 이미 이관된 기능(잡 취소=`job_stop`, 단일 노드=`show_slurm_node`, 파티션=`list_slurm_partitions`)은 건드리지 않는다.
- 기존 도구(`job_stop`, `batch_cancel_jobs` 등)의 중복 코드 정리는 별도 과제로 남긴다.
- 파티션/예약/계정 생성·수정 같은 backend의 다른 관리 API는 구 mcp_slurm에도 없었으므로 이번 범위가 아니다.

## 설계 원칙

1. **모든 도구는 backend_5010을 경유한다.** `local` transport의 `script.sh`가 공용 헬퍼로 backend REST를
   호출한다. 인증(PAT)·권한·감사가 backend에 모여 있고, MCP 서비스 계정에 Slurm 관리 권한을 줄 필요가 없다.
   단일 요청인 `http` transport로는 아래 2번의 사전 인증 호출을 붙일 수 없어서 쓰지 않는다.
2. **모든 도구는 먼저 `GET /api/me`로 호출자를 확인한다(fail-closed).** 구 mcp_slurm의 `_require_user`를
   복원하는 것이다. smarttwin의 local 도구는 지금 PAT를 검증하지 않고, backend 읽기 엔드포인트 상당수가
   무인증이라 이 게이트가 없으면 /mcp에 닿기만 하면 전체 사용자 잡·fairshare까지 보이게 된다.
3. **입력은 schema와 스크립트 양쪽에서 검증한다.** job_id `^[0-9]+(_[0-9]+)?(\.[A-Za-z0-9_+-]+)?$`,
   노드 이름 `^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$`(단일 노드, 콤마·범위 불가) — 구 mcp_slurm 정규식 그대로.
   구 `slurm_job_control`은 job_id를 검증하지 않고 URL 경로에 넣었는데(server.py L652-664), 이 버그는 옮기지 않는다.
4. **출력은 JSON + 상한.** 구 도구는 CLI 출력을 무제한 raw text로 돌려줬다. 카탈로그 규약대로 JSON으로 반환하고
   목록형은 `limit`(기본 200)과 `truncated` 플래그를 둔다.
5. **쓰기는 기본 `dry_run=true`, 감사 기록 필수.** `_shared/audit.py`의 `record_event`를 쓰되 actor는
   `$USER`(서비스 계정) 대신 `/api/me`가 돌려준 실제 사용자명으로 남긴다.
6. **쓰기 도구는 액션 enum 2개로 묶는다.** `node_set_state`, `job_control`. 잡 취소는 기존 `job_stop`을 유지하고
   `job_control`에서는 뺀다.

## 도구 목록

읽기 9종(태그 `mode-read-all`, `expose: catalog`).

| 신규 도구 | 구 도구 | backend 엔드포인트 | 주요 인자 | 비고 |
|---|---|---|---|---|
| `list_slurm_jobs` | slurm_list_jobs | GET `/api/slurm/jobs` (app.py:606) | user, state, partition, limit | 전체 사용자 squeue + 최근 sacct |
| `list_slurm_nodes` | slurm_list_nodes | GET `/api/nodes` (node_management_api.py:72) | state, partition | 노드별(`sinfo -N`). 구 도구는 파티션 요약이었음 |
| `get_fairshare` | slurm_fairshare | GET `/api/slurm/fairshare` (slurm_admin_api.py:99) | account, user, limit | `sshare -P -a` |
| `get_job_priority` | slurm_job_priority | GET `/api/slurm/jobs/priority` (slurm_admin_api.py:139) | job_id, user, limit | `sprio -l` |
| `list_slurm_reservations` | slurm_list_reservations | GET `/api/slurm/reservations` (slurm_reservation_api.py:78) | 없음 | backend가 admin 전용 → 일반 사용자는 403을 그대로 안내 |
| `list_slurm_qos` | slurm_list_qos | GET `/api/slurm/qos` (app.py:1321) | 없음 | `sacctmgr show qos` |
| `get_scheduler_diag` | slurm_scheduler_diag | GET `/api/slurm/diag` (slurm_admin_api.py:59) | 없음 | `sdiag` |
| `get_job_stat` | slurm_job_stat | GET `/api/slurm/jobs/<id>/stat` (slurm_admin_api.py:179) | job_id(필수) | `sstat`, RUNNING 잡만 |
| `query_job_accounting` | slurm_job_accounting | **신설 필요** GET `/api/slurm/accounting` | job_id, user, start, end, state, limit | 일반 사용자=본인 잡, admin=전체 |

쓰기 2종(기본 `dry_run=true`).

| 신규 도구 | 구 도구 | backend 엔드포인트 | 주요 인자 |
|---|---|---|---|
| `node_set_state` | slurm_node_set_state | POST `/api/nodes/{drain,resume,down,undrain}` (node_management_api.py:240·315·482·577) | node, action, reason(drain·down 필수), dry_run |
| `job_control` | slurm_job_control(cancel 제외) | POST `/api/slurm/jobs/<id>/{hold,release}` (app.py:1071·1102), `/{requeue,requeuehold,priority,nice,top}` (slurm_admin_api.py:417·438·514·542·571) | job_id, action, value(priority·nice 필수), dry_run |

## 선행 조건 — backend (Phase 0)

1. **쓰기 권한이 너무 넓다(결정 필요).** 노드 drain/resume/down/undrain과 잡 hold/release/requeue/priority/nice/top은
   지금 `permission_required('dashboard')`만 요구하고 소유권을 확인하지 않는다. `dashboard` 권한은 DX-Users·
   CAEG-Users에도 있어서, 이대로 MCP에 노출하면 일반 사용자가 자연어 한 줄로 노드를 내리거나 남의 잡을
   requeue할 수 있다. 제안은 노드 상태 변경=`admin`, 잡 제어=`admin` 또는 잡 소유자(scontrol로 UserId 확인).
   다만 `frontend_3010`의 `SlurmManagement`·`NodeManagement` 화면이 같은 API를 쓰므로 UI 접근 권한과 맞춰야 한다.
   MCP 층에서만 막는 건 같은 PAT로 REST를 직접 부르면 우회되므로 backend에서 막아야 한다.
2. **sacct 조회 엔드포인트 신설.** 범용 sacct 엔드포인트가 없다(`/api/slurm/jobs`의 sacct는 `-a` 없이 최근 N일만).
   GET `/api/slurm/accounting` — 필터(job_id, user, start, end, state), 일반 사용자는 본인 잡만, admin은 전체, 결과 상한.
3. **MOCK_MODE 확인.** `slurm_admin_api.py:31`의 기본값이 `'true'`라 `.env`에 `MOCK_MODE=false`가 없으면 진짜 Slurm
   대신 목 데이터가 나온다. dev는 false 확인됨. 운영(icn401)도 확인해야 한다.
4. **무인증 읽기 엔드포인트(선택, 결정 필요).** diag·fairshare·priority·stat·qos·jobs·nodes 읽기 엔드포인트에 인증이 없고
   backend는 `0.0.0.0:5010`에 떠 있다. MCP 게이트(원칙 2)는 MCP 경로만 막는다. `jwt_required`를 붙일지 이번 범위에서 정한다.
5. **SSO-off 배포 주의.** SSO가 꺼져 있으면 모든 요청이 FULL_ACCESS(admin)로 처리된다(jwt_middleware.py:60-66). 이 경우
   1번의 권한 강화는 효과가 없다. 운영이 SSO-on인지 확인한다.

## 단계

- **Phase 0 (backend).** 위 1~4 결정·반영. backend 변경은 `start_production.sh`로 dashboard_backend 재기동.
- **Phase 1 (공용 헬퍼).** 호출자 확인(GET /api/me → username·role·permissions, 401/403/연결실패는 fail-closed)은
  병행 작업 중인 `tools/_shared/stmc_exec.py`의 헬퍼를 재사용한다(새로 만들지 않는다). 거기 없는 것만 보탠다 —
  `backend_get()`/`backend_post()`(STMC_CLUSTER_URL + Bearer STMC_CLUSTER_TOKEN, 타임아웃 15초),
  `validate_job_id()`/`validate_node()`, 목록 상한 헬퍼. 기존 `job_helpers.py`와 같은 env 규약을 따른다.
  관리자 쓰기 도구용 `mode-admin` 태그를 신설할지 정한다(lint.py:76 `_MODE_TAG_RE`, AGENT_GUIDE §18.2).
- **Phase 2 (읽기 9종).** `query_job_accounting`은 Phase 0의 2번 이후.
- **Phase 3 (쓰기 2종).** Phase 0의 1번 결정·반영 이후.
- **Phase 4 (검증·문서·배포).** 아래 체크리스트 참고. 새 도구는 `expose: catalog`라 `catalog_reload`로 재시작 없이 반영된다.

## 체크리스트

### Phase 0 — backend
- [ ] 쓰기 권한 강화 범위 결정(노드=admin, 잡=admin 또는 소유자) + frontend 화면 권한과 정합 확인
- [ ] 노드 상태 변경 엔드포인트 권한 반영(node_management_api.py)
- [ ] 잡 제어 엔드포인트 권한·소유권 검사 반영(app.py hold/release, slurm_admin_api.py requeue~top)
- [ ] GET `/api/slurm/accounting` 신설 + 권한 범위 + 상한
- [ ] 운영 `.env`의 `MOCK_MODE=false` 확인
- [ ] 무인증 읽기 엔드포인트 인증 추가 여부 결정(·반영)
- [ ] 운영 SSO-on 여부 확인

### Phase 1 — 공용 헬퍼
- [ ] `stmc_exec.py`의 /api/me 호출자 확인 헬퍼 확인(함수명·반환 형태) 후 재사용
- [ ] 부족분(backend_get/post, validate_*, 상한) 추가 — 위치는 stmc_exec.py 작성 세션과 협의
- [ ] `mode-admin` 태그 신설 여부 결정 → 신설 시 lint.py `_MODE_TAG_RE` + AGENT_GUIDE §18.2 갱신

### Phase 2 — 읽기 9종 (도구마다 meta.yaml · args.schema.json · script.sh · latest 심링크 · 예시 2개 이상)
- [ ] list_slurm_jobs
- [ ] list_slurm_nodes
- [ ] get_fairshare
- [ ] get_job_priority
- [ ] list_slurm_reservations
- [ ] list_slurm_qos
- [ ] get_scheduler_diag
- [ ] get_job_stat
- [ ] query_job_accounting

### Phase 3 — 쓰기 2종
- [ ] node_set_state(dry_run 기본 true, reason 조건부 필수는 schema if/then, record_event)
- [ ] job_control(cancel 제외, value 조건부 필수, record_event)

### Phase 4 — 검증·문서·배포
- [ ] `smarttwin-mcp lint tools/` 오류 0
- [ ] `pytest tests/test_catalog.py tests/test_lint.py` 통과
- [ ] `scripts/smoke_all_tools.py`의 `MINIMAL_ARGS`/`EXTERNAL_DEPS`에 신규 도구 등록 후 스모크
- [ ] dev e2e — PAT 있음=실데이터, PAT 없음=fail-closed, 일반 사용자 PAT로 쓰기=403, 쓰기 기본 dry_run 확인
- [ ] dev 실동작 1회(사용자 승인 후) — node002 drain→resume, 테스트 잡 hold→release
- [ ] AGENT_GUIDE §21(Slurm 래퍼) 목록 갱신
- [ ] deploy/RUNBOOK.md "미이관 도구" 섹션 → 이관 완료로 갱신, MIGRATION.md 체크
- [ ] 운영 반영 — git pull → `start_production.sh`(backend) → `catalog_reload`

## 결정 필요 사항

1. 쓰기 권한 강화 범위와 UI 영향(Phase 0의 1번).
2. `mode-admin` 태그 신설 vs 기존 `mode-own` 재사용.
3. 무인증 backend 읽기 엔드포인트에 인증을 이번에 붙일지.

## 컨텍스트 노트

이관 전 조사(2026-10-13)에서 확인한 사실. 결정이 내려지면 아래에 이어 적는다.

- 구 구현 위치 `dashboard/mcp_slurm/server.py`. 읽기 도구 L220-430, 쓰기 도구 L558-666, 공용 헬퍼 L93-213.
  CLI 래퍼는 `dashboard/backend_5010/slurm_commands.py`(절대경로 `SLURM_BIN_DIR`, argv 리스트, 셸 미사용, 10초 타임아웃).
- 구 읽기 도구는 대부분 인자 없이 무플래그 CLI(squeue, sinfo, sacct, sdiag, sshare, sprio) 출력을 상한 없이 반환했다.
  인증은 `/api/me` 2xx 여부만 봤고 역할은 보지 않았다.
- 구 쓰기 도구는 MCP 층에서 `/api/me`도 호출하지 않고 권한 판단을 전부 backend에 맡겼다. 기본 dry_run=true.
- smarttwin의 `mode-*` 태그는 런타임에 강제되지 않는 lint 신호다(lint.py:76, 87-102, 279-309). 허용값은
  `mode-own`, `mode-own-shared`, `mode-read-all`뿐이다.
- smarttwin MCP 서버는 PAT를 사용자로 해석하지 않고 `STMC_CLUSTER_TOKEN`으로 스크립트에 넘기기만 한다
  (server.py:38-57). 사용자 해석은 `GET /api/me`(job_helpers.py:99)뿐이다. local 스크립트의 `$USER`는 서비스 계정이다.
- backend 권한 모델. 그룹→권한은 `auth_portal_4430/config/config.py:137-141`(HPC-Admins=admin 포함, DX-Users·CAEG-Users=dashboard 포함),
  검사는 `middleware/jwt_middleware.py`의 `permission_required`(L187-225). PAT는 발급 시점의 권한 스냅샷을 쓴다(mcp_token.py:134-175).
- backend 쓰기 엔드포인트는 모두 dry_run을 지원하고 `log_admin_action`(audit_log.py:80)으로 자체 감사 기록을 남긴다.
- `node_management_api_fixed.py`, `node_management_api_with_path.py`는 등록되지 않은 사본이다. 실제 등록은 `node_management_api`(app.py:121).
- 같은 쓰기 API를 프론트도 쓴다 — `frontend_3010/src/components/SlurmManagement/index.tsx`, `NodeManagement/index.tsx`, `src/utils/api.ts`.
- `catalog_reload`(server.py:191)는 카탈로그를 다시 읽어 새 도구·버전을 재시작 없이 반영한다.
- (2026-10-13) 다른 세션(pykoocae)이 smarttwin_mcp를 병행 수정 중 — `tools/_shared/{scenario_builder,job_helpers,stmc_exec,stmc_tools}.py`,
  `src/smarttwin_mcp/{server,search}.py`, 신규 도구(kmm_·kam_·remap_·post_·scenario_*)는 그쪽 담당. 이관 작업 시 이 파일들은
  직접 고치지 말고 협의한다. `stmc_exec.py`에 fail-closed /api/me 헬퍼가 들어온다고 해서 Phase 1을 재사용으로 바꿨다.
