<!-- C-1 job_status runs 체크리스트 -->
# 체크리스트 — job_status `runs` (2026-11-25)

- [x] 조사 — 출처 파일(runner_config doe_angles·simulation_index), 별칭 꼴, 재시도 덮어쓰기, 최근 캠페인 3개 확인
- [x] 사용자 결정 — job_status 선택 인자, 지금 구현
- [x] worktree `feat/c1-job-status-runs` (live main 트리를 직접 고치지 않음)
- [x] `job_status` args.schema `runs` · meta 설명 · script
- [x] 시험 `tests/test_job_status_runs.py` 4건 — 완료/실패/pending 각도, 기본 응답에 runs 없음, 시작 전 전부 pending, 각도 DOE 아닌 잡·KooChainRun 아닌 잡, 남의 경로로 새는 folder 거절
- [x] 전체 시험 341 통과 · 실패 3 은 main 에서도 같음(KMM RIGID_DROP_ENDTIME·KooChainRun 새 명령 미생성, kooremapper 벤더 사본) — 이 일과 무관
- [x] 실데이터 확인 — BindFix_Verify_2angle_1088(실패 2, error 실림)·E2E_drop_9000001(완료 26, d3plot 경로)
- [ ] 커밋 → main 병합(사용자 확인)
- [ ] 운영 반영 — catalog_reload 또는 재시작(사용자 확인)
- [ ] kooremapper-4a 에 도구 이름·응답 예시 회신
