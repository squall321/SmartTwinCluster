<!-- SmartTwin MCP+REST 커버리지 작업 체크리스트 -->
# 체크리스트 — SmartTwin 전 기능 MCP + REST

## 0. 선행
- [x] SIF v112 node001 배포(다른 세션이 굽고 배포 안 함) · sha 확인
- [x] Post SIF(10-02) node001 배포(09-11 본이 남아 있었음) · sha 확인
- [ ] 기존 시험 실패 2건 정리(오래된 submit 시험 · http runner 검사 순서 결함)

## 1. 실행 기반
- [ ] backend 템플릿 `smarttwin-tool`(화이트리스트 디스패처) + `smarttwin-scenario`(드라이버)
- [ ] `_shared/stmc_exec.py` — 경로 수집·허용 루트 검사·tar 업로드·제출·dry_run·wait·결과 읽기
- [ ] `_shared/kooremapper_core/` 벤더링 + 원본 일치 시험
- [ ] 템플릿 실잡 스모크(KooRemapper version/info)

## 2. 생성기 + 도구
- [ ] `tools/_gen/generate_smarttwin_tools.py`
- [ ] kmm_* 32 + kmm_chain
- [ ] kam_* 6
- [ ] remap_* 59
- [ ] post_* 11
- [ ] scenario_* (drop·impact·vibration·therm·part_validation·drop_weight_impact) + scenario_submit
- [ ] job_reprioritize · job_harvest · tool_result · smarttwin_capabilities
- [ ] search 한글 토큰
- [ ] lint 0 error

## 3. REST
- [ ] custom routes 5종 + OpenAPI 생성 + PAT 검증
- [ ] 시험(ASGI 클라이언트) — MCP 와 같은 결과

## 4. 정본 갱신(pyKooCAE)
- [ ] cli_help_kcr.py 에 10월 기능 반영 + test_cli_help
- [ ] 생성기 재실행 → scenario_* 문서 갱신

## 5. 시험·배포
- [ ] 커버리지 시험 · pytest 전체 · lint
- [ ] 실잡 e2e 5종(backend 경유)
- [ ] smarttwin-mcp 재기동 + nginx `/smarttwin-api/`(정본+라이브) + 443 경유 MCP·REST 확인
- [ ] KooChainRun 빌드 → SIF v113 → tar·메일 → node001
- [ ] 커밋·푸시(KooSlurm · pyKooCAE) · 메모리
