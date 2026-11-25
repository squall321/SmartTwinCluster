<!-- C-1 job_status runs 체크리스트 -->
# 체크리스트 — job_status `runs` (2026-11-25)

- [x] 조사 — 출처 파일(runner_config doe_angles·simulation_index), 별칭 꼴, 재시도 덮어쓰기, 최근 캠페인 3개 확인
- [x] 사용자 결정 — job_status 선택 인자, 지금 구현
- [x] worktree `feat/c1-job-status-runs` (live main 트리를 직접 고치지 않음)
- [x] `job_status` args.schema `runs` · meta 설명 · script
- [x] 시험 `tests/test_job_status_runs.py` 4건 — 완료/실패/pending 각도, 기본 응답에 runs 없음, 시작 전 전부 pending, 각도 DOE 아닌 잡·KooChainRun 아닌 잡, 남의 경로로 새는 folder 거절
- [x] 전체 시험 341 통과 · 실패 3 은 main 에서도 같음(KMM RIGID_DROP_ENDTIME·KooChainRun 새 명령 미생성, kooremapper 벤더 사본) — 이 일과 무관
- [x] 실데이터 확인 — BindFix_Verify_2angle_1088(실패 2, error 실림)·E2E_drop_9000001(완료 26, d3plot 경로)
- [x] 커밋 e5cb6f41 → main fast-forward · push ea9ebe59..e5cb6f41 (11-25, 사용자 승인)
- [x] 운영 반영 — smarttwin-mcp 재시작 11-25 02:50(30분 호출 0건 확인 뒤, 사용자 승인). 도구 172·문제 0. 실제 MCP 클라이언트로 job_status 설명·catalog_describe 에 runs, runs:true 는 스키마 통과(PAT 단계), 오타 runz 는 거절 확인
- [ ] dev 게이트웨이 tools/list 확인 — 이 셸에 HWAX_GATEWAY_PAT 없음, hwaxportal-87 에 부탁
- [x] kooremapper-4a 에 도구 이름·응답 예시 회신(11-25) · 운영 반영 알림
