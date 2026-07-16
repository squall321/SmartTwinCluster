<!-- SmartTwinMCP → KooSlurm 종속 이관(2a) 계획·체크리스트·컨텍스트 노트 -->
# SmartTwinMCP 이관 (2a) — 계획 · 체크리스트 · 컨텍스트

## 목표
SmartTwinMCP(카탈로그 인덱스 + 버전드 도구 + 메타툴 아키텍처)를 **실제 backend_5010에 재배선**하고,
`dashboard/smarttwin_mcp/`(이 위치)로 vendoring 하여 **KooSlurmInstallAutomationRefactory 프로젝트에 종속**시킨다.
현재 운영 MCP(`dashboard/mcp_slurm/`, mcp-slurm.service :5012)는 **파리티 달성까지 그대로 유지**(스트랭글러 패턴).

## 왜 이렇게 (핵심 사실)
- **live 정본** = `dashboard/mcp_slurm/server.py` (단일파일 FastMCP, 19툴, backend_5010 `/api/*` 프록시 + slurm CLI, RCE 하드닝 완료). Claude 가 붙는 :5012. 실제 잡 제출됨(job 871 검증).
- **SmartTwinMCP** = 더 나은 뼈대(카탈로그/버전/메타툴/audit.db/registry/HTTP·SSH/테스트)지만 도구가 **플레이스홀더**. 배선이 상상 속 control-plane `${STMC_CLUSTER_URL}/v1/*`(예: `/v1/health`, `stcluster submit`)에 꽂혀 있어 실동작 아님. 미구동.
- 둘은 **상보적** — 뼈대(SmartTwinMCP) + 실배선/하드닝(mcp_slurm). 2a = 뼈대에 실배선을 이식.

## 절대 규칙
1. `dashboard/mcp_slurm/`(live)와 원본 repo `/home/koopark/claude/SmartTwinMCP`(upstream)는 **파리티 전까지 손대지 않는다**.
2. 새 서버는 **별도 포트(5013)** 로 병행 구동해 검증. 검증 전 nginx `/mcp`·mcp-slurm.service 전환 금지.
3. 실제 제출/제어 로직은 mcp_slurm 의 **검증된 것**을 이식(특히 RCE 방어 = scenario_overrides environment 잠금, job_id/node 검증).

## 재배선 계약 (Phase 2에서 확정)
- `STMC_CLUSTER_URL/v1/*` → **backend_5010 `/api/*`** 로 교체.
  - `/v1/health` → `/api/slurm/status`, 잡목록 → `/api/slurm/jobs`, 제출 → `/api/jobs/submit`(멀티파트) 등.
- 인증: mcp_slurm 처럼 **들어온 Authorization(PAT kst_) 패스스루** → backend 가 검증/권한/감사. (SmartTwinMCP 의 `STMC_CLUSTER_TOKEN` 단일토큰 모델을 패스스루로 교체 검토.)
- 도구 실행 트리플(`tools/<name>/<ver>/script.sh`)의 script.sh 를 `curl backend_5010 /api/...` 로 교체(또는 _shared 공통 헬퍼 도입).

## 체크리스트
- [x] Phase1: `dashboard/smarttwin_mcp/` 로 vendoring (venv/git/캐시/CI/세션 제외, 1.7M)
- [x] Phase1: import/lint 산안검증(src 전 파싱 OK, 도구 45개) + 커밋(12e82a7)
- [x] Phase2: 인증 결정 = **(ii) 요청별 PAT 패스스루**. 구현: runner.run(entry,args,extra_env) +
      server._auth_extra_env(get_http_headers(include={"authorization"}) → STMC_CLUSTER_TOKEN/STMC_AUTH).
      transport 에 http(streamable) + --host/--port 추가.
- [x] Phase2 PoC read: get_cluster_health → `${STMC_CLUSTER_URL}/api/slurm/status`. 5013 병행 구동,
      PAT 有 → ok/200/실데이터, PAT 無 → fail-closed 검증 완료. (get_http_headers 가 기본으로
      authorization 을 strip 하는 함정 → include 로 해결.)
- [ ] Phase2 PoC submit: submit_job → `/api/jobs/submit` 멀티파트(file_<key>) + 하드닝 이식(경로검증 등)
- [ ] Phase2: submit 실제 잡 제출 e2e
- [ ] Phase3: 나머지 도구 순차 이식(하드닝 이식) → 파리티
- [ ] Phase3: 파리티+검증 후 mcp-slurm.service(또는 nginx /mcp) 컷오버, 구버전 폴백 유지

## 컨텍스트 노트 (이관 중 결정 기록 — 계속 추가)
- vendoring 방식 = **copy(코드 종속)**. git-subtree(히스토리 보존) 아님. 원본 repo 는 upstream 으로 보존(삭제 안 함).
- 제외: `.venv .git .pytest_cache __pycache__ *.egg-info .bkit .koo-llm-sessions .github .claude`.
- 진입점: `pyproject [project.scripts] smarttwin-mcp = smarttwin_mcp.server:main`. 패키지 = `src/smarttwin_mcp/`.
- 프레임워크 파일: `src/smarttwin_mcp/{server,catalog,spec,runner,search,lint}.py`. 공통헬퍼: `tools/_shared/{registry,audit,job_helpers,scenario_builder,auto_tune}.py`.
- audit/registry DB 는 `/data/SmartTwinMCP/*.db`(STMC_AUDIT_DB / STMC_JOBS_DB 로 override). 운영경로 재검토 필요(→ `/data/smarttwin_mcp/`?).
- ★인증 모델(Phase2 핵심 결정)★ — runner.py 는 도구 실행 시 env 를 **`os.environ`**(서버 프로세스)에서
  가져온다(local: line64 `{**os.environ,...}`, http: line216 `env=os.environ`, headers 를 `${STMC_CLUSTER_TOKEN}`
  로 보간). 즉 **단일 서비스 토큰** 모델 — 요청별 PAT 패스스루가 아님. 그대로 쓰면 backend_5010 의
  사용자별 권한/감사/이력이 전부 한 서비스계정으로 뭉개진다(대시보드 권한모델 붕괴).
  → **결정 필요**: (i) 단일 서비스토큰 유지(간단, 보안 후퇴) vs (ii) 요청 Authorization 을 catalog_run
  (server.py, ctx.request_context.request.headers) 에서 읽어 runner→도구 env 로 **주입(패스스루)**
  — mcp_slurm 의 검증된 모델. (ii) 는 runner.py/server.py 프레임워크 수정 필요(도구별 아님).
  추천 = (ii). Phase2 는 이 결정부터.
