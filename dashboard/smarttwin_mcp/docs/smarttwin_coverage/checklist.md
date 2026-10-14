<!-- SmartTwin MCP+REST 커버리지 작업 체크리스트 -->
# 체크리스트 — SmartTwin 전 기능 MCP + REST

## 0. 선행
- [x] SIF v112 node001 배포(다른 세션이 굽고 배포 안 함) · sha 확인
- [x] Post SIF(10-02) node001 배포(09-11 본이 남아 있었음) · sha 확인
- [x] 기존 시험 실패 2건 정리(오래된 submit 시험 · http runner 검사 순서 결함) — 78706837

## 1. 실행 기반
- [x] backend 템플릿 `smarttwin-tool`(화이트리스트 디스패처) — 6762e32a·8b38834d
- [x] backend 템플릿 `smarttwin-scenario`(드라이버) — b275c109
- [x] `_shared/stmc_exec.py` — 경로 수집·허용 루트 검사·tar 업로드·제출·dry_run·wait·결과 읽기
- [x] `_shared/kooremapper_core/` 벤더링 + 원본 일치 시험
- [x] 템플릿 실잡 스모크(KooRemapper version/info)

## 2. 생성기 + 도구
- [x] `tools/_gen/generate_smarttwin_tools.py`
- [x] kmm_* 32 + kmm_chain
- [x] kam_* 6
- [x] remap_* 59
- [x] post_* 10 (후처리 실행 파일 10종 — 계획의 11 은 오기)
- [x] scenario_* (drop·impact·vibration·therm·remap·part_validation·drop_weight_impact) + scenario_submit
- [x] job_reprioritize · job_harvest · tool_result · smarttwin_capabilities — 9097c402
- [x] KooChainRun 명령 → 도구 대응을 기능표에(새 명령이면 생성 중단)
- [x] search 한글 토큰 — f7c4ce25
- [x] lint 0 error (164 도구, 기존 경고 1: submit_job L070)

## 3. REST
- [x] custom routes 7종 + OpenAPI 생성 + PAT 검증 — 2c1eb85a
- [x] 시험(ASGI 클라이언트) — MCP 와 같은 결과
- [x] dev 서비스 재기동 후 실PAT 확인(검색·기능표·tool_result·reprioritize 계획·harvest, PAT 없음 401)

## 4. 정본 갱신(pyKooCAE)
- [x] cli_help_kcr.py 에 10월 기능 반영 + test_cli_help — pyKooCAE 04760dc(D2R 사례 DROP#3 검증)
- [x] 생성기 재실행 → scenario_* 문서 갱신 — e1484248

## 5. 시험·배포
- [x] 커버리지 시험 · pytest 전체(285) · lint
- [x] 실잡 e2e 8종(backend 경유, 잡 1171~1178)
- [x] 시나리오 e2e(잡 1182 → 자식 1183·1184) — LS-DYNA 직전까지 완주, dev 라이선스 만료로 LS-DYNA 거절
- [x] kmm_chain e2e 재실행 + MAT 카드 의미 검사 — 잡 1196(node001, SIF v113) 통과, 판정은 옛 불량 산출물(1174)에서 실패 확인 — 7c6b93e4
- [ ] nginx `/smarttwin-api/`(정본+라이브) + 443 경유 확인 — b5·사용자 확인 후(터널 경유는 nginx 없이 된다)
- [x] KMM·KooChainRun 빌드(glibc 2.35, 산출물로 ETOR 재질 확인·회귀 e2e 7종) → SIF v113 → tar·Drive·메일 → 헤드·node001·node002(sha 동일)
- [x] 커밋·푸시 — pyKooCAE 7a135d9..04760dc, KooSlurm c58cf408..7c6b93e4(사용자 승인) · 메모리
- [x] 임시 PAT(id 17) 삭제 — dev 는 SSO 꺼짐이라 API 로는 소유자(koopark) 토큰이 안 보여 backend mcp_token.delete_token 으로

## 6. 개통 전 접근 통제 (사용자 결정 2026-10-14 — 허용 루트·job_* 소유권·옛 버전 위임)
- [x] fullangle·single drop 1.1.2 — work_dir 은 호출자 영역 + STMC_WORK_ROOTS, model_file_path 는 입력 루트, 심볼릭 링크 거절
- [x] job_helpers.resolve_job 소유권(PAT 호출자) — job_* 11종·get_job_details, my_jobs·batch_cancel 도
- [x] 옛 버전 위임 10종(스키마 동일 확인, deprecated 표시)
- [x] 시험 test_owner_gates 37 + 전체 322 · lint 0 error · dev 재기동 후 실PAT 확인 — 5aa61b67
- [x] stcx 회신 문서 deploy/STCX_DYNAFORGE_REPLY.md (§2·§3 반영 내역, §1 차이, lstc_license_ip 답)
- [ ] 운영 유닛 drop-in STMC_WORK_ROOTS — 운영 측(회신에 명시)
