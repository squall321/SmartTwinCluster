<!-- 포털 mcp-modernize 공통 계약(contract.md) 항목별 답 — SmartTwin MCP(KooSlurm) -->
# 공통 계약 답 — SmartTwin MCP (2026-11-27, 가지 feat/sm-security-1125)

| # | 답 | 언제 | 비고 |
|---|---|---|---|
| P1 stateless | 됨 | 이 판 | fastmcp 3.3.1 은 `run(..., stateless_http=True)`(생성자 인자 아님). 서버→클라이언트 채널 안 씀 |
| P2 두 세대(SDK 2.x) | 할 차례 | 다음 판 | fastmcp 3.3.1 이 mcp 1.28 위. 2.x 는 프레임워크 교체 + 오프라인 wheel(SHA256SUMS)·운영 판 다시 — 따로 계획 |
| P3 오류 꼴 | 됨(1.x 범위) | 이 판 | 도구 오류는 `{ok:false, reason}` 를 결과 글로 — 가려지지 않는다. ToolError 는 2.x 때 |
| C1 설명의 꼴 | 할 차례 | 다음 판 | 직접 도구 19개 설명을 「한 문장 → 언제·형제 → 돌려주는 꼴」로 다시 쓰기. job_changes 는 이 꼴로 씀 |
| C2 인자 설명 | 됨 | 이 판 | 직접 도구 inputSchema 를 카탈로그 스키마 그대로(E1) — 설명·단위·기본값 |
| C3 enum | 됨 | 이 판 | 카탈로그 스키마의 enum 이 inputSchema 로 나감 |
| C4 숫자 경계 | 일부 | 이 판 | 양(limit·since_hours_ago 등)엔 최소·최대. 식별자(registry_id·job_id)는 상한 없음(의미 없음). fullangle yield_stress_mpa 상한은 옛 판 위임 스키마와 함께 다음 판 |
| C5 구조 있는 객체 | 됨 | 이 판 | catalog_run 의 args 는 도구마다 달라 자유형 — 설명에 catalog_describe 로 보라고 적음 |
| C6 표지 | 됨 | 이 판 | 23개(+job_changes) 모두 readOnlyHint·destructiveHint·idempotentHint·openWorldHint, tools/list 원문에서 camelCase 확인(시험) |
| C7 결과 꼴(outputSchema) | 할 차례 | 다음 판 | 지금은 structured_content(dict)+같은 글. 도구별 결과 모델은 따로 |
| C8 정직한 한도 | 일부 | 이 판 | 새 도구(job_changes·KCR 9개)는 truncated·next_cursor. 기존 도구는 다음 판에 훑기 |
| C9 이름 | 됨 | — | 동사_대상, 앱 접두 없음(게이트웨이가 겹칠 때 smarttwinmcp_ 를 붙임) |
| R1 이벤트 | 됨 | 이 판 | job_changes(커서 = 시각#registry_id, 시간순, 끝·시작·대기) |
| R2 길 안내 | 할 차례 | 다음 판 | 대표 업무: 전각도 낙하 → job_status → job_changes / 결과 회수(runs:true) |
| R3 앱 입구 | 됨 | — | smarttwin_capabilities(서버 instructions 가 catalog_search → describe → run 차례를 안내) |
