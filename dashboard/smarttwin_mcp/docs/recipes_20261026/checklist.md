<!-- 레시피 등록소 체크리스트 -->
# 체크리스트 — 레시피 등록소 (2026-10-26)

- [x] 조사 — KMM 확장 지점 없음, 재빌드 없이 쌓이는 층(MCP 카탈로그·kmm_chain·후처리 YAML), 잡 결과 폴더(stmc_result.json·work/stmc_options.txt)
- [x] 계획 PLAN.md · 사용자 결정(호출자 신뢰 → 품질 관문)
- [x] `tools/_shared/recipes.py` — 저장소(판·해시·원자적 쓰기·잠금), 형식 검증, 매개변수 펼치기, 근거 확인
- [x] 도구 5개 `recipe_save`·`recipe_list`·`recipe_get`·`recipe_run`·`recipe_retire` (meta·schema·script, latest 링크)
- [x] 시험 `tests/test_recipes.py` 10건 — 저장·판 증가·검증 거절 5꼴·근거 거절 4꼴·펼치기·dry_run·실제 제출(가짜 backend)·retire·매개변수 검사·post 레시피
- [x] 기존 시험 335 통과(실패 1 = test_vendored_kooremapper_core_matches_source, KooRemapper 리포가 벤더 원본보다 앞서 있어 전부터 실패 — 이 일과 무관)·lint 0 오류
- [x] 사용 지침 — 서버 instructions(다음 재시작부터)·smarttwin_capabilities how_to·AGENT_GUIDE §31
- [x] 실제 확인 — admin 의 kmm_chain 잡 1174(registry 23)를 근거로 대조 통과(stmc_options.txt·argv), 틀린 값(dz 6) 거절, 새 값(pid 7·dz 12.5)으로 펼친 옵션 파일 확인(임시 저장소)
- [x] 커밋(내 파일만 — 저장소의 남의 미커밋 변경은 건드리지 않음). 앞서 안 올렸던 251ee6b8 은 10-25 후처리 v41 때의 post_deep_report 재생성
- [x] 운영 반영(10-27 00:13, 사용자 승인) — push 2d396153..078c02af, smarttwin-mcp 재시작(유휴 확인 뒤). 실제 MCP 클라이언트로 instructions 문장·직접 도구 3개·catalog_search 5개·recipe_list(빈 저장소) 확인
- [x] 2단계 — KMM 옵션 파일 `*Recipe,<이름>[,<판>]` 펼치기(10-27, KMM v126 · SIF 6254091c · 헤드 /opt 교체). pyKooCAE a331d8e·d547730·4afbf7c·3296a37, 시험 tests/test_kmm_recipe.py(MCP recipes.save 로 판을 만들어 stmc_options.txt 와 바이트 대조)
