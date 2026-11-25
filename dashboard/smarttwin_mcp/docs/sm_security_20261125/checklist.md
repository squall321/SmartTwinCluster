<!-- SM 묶음 체크리스트 -->
# 체크리스트 — SM-04 → 01 → 02 → 03 (2026-11-25)

- [x] 접수·차례 회신(hwaxportal-71), SM 커밋 없음 확인
- [x] worktree `feat/sm-security-1125`
- [x] SM-04 backend jwt_middleware 순서·auth 칸, /api/me auth
- [x] SM-04 MCP caller_identity — kst_·auth==pat·금지 이름 + REST PatVerifier 도 auth==pat
- [x] SM-04 시험 — backend tests/test_sm04_pat_before_sso_off.py 5건(전체 56 통과) · MCP tests/test_sm04_caller_identity.py 8건(전체 352 통과, 실패 3 은 main 과 같은 카탈로그 밀림)
- [x] SM-04 반영(11-25 16:36 UTC) — main 89172f14 push, dashboard_backend → smarttwin-mcp 재시작. live 확인: /api/me 머리 없음 admin·auth sso_off, 틀린 kst_ 401, 비PAT Bearer 는 sso_off(MCP 가 거절). REST /api/v1/tools 비PAT·틀린 kst_ 401. 진짜 위임 PAT 로 이름 확인은 PAT 가 없어 못 함(시험으로 덮음)
- [x] SM-01 — train_pytorch_gpu·submit_distributed_train 1.1.0: 인자 직후 caller_name()+check_under(work_dir, work_roots), sbatch --comment=stmc:<호출자>, 감사 actor·registry extra.caller = 호출자. submit_lsdyna_remote 1.1.0 닫힘(local transport·거절, 1.0.0 위임도 같이). 시험 tests/test_sm01_sbatch_gates.py 8건, 전체 363 통과(실패 3 = 카탈로그 밀림, main 과 같음). 가지 커밋만(push 보류)
- [x] SM-02 — ToolMeta.read_only(기본 false) · catalog_search/describe/versions readOnlyHint true, catalog_run/reload false, 직접 도구는 meta read_only. read_only: true = echo·get_job_details·job_status·list_recent_jobs·recipe_list·smarttwin_capabilities·tool_result. 시험 tests/test_sm02_read_only_hint.py 2건
- [ ] SM-03
- [ ] hwaxportal-71 에 착지 넷(push 해시·Drive·SIF sha256/캐시 열쇠·운영 수작업)
