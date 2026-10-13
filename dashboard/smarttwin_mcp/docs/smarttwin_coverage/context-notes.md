<!-- SmartTwin MCP+REST 커버리지 작업의 결정과 근거 — 계속 추가 -->
# 컨텍스트 노트

## 2026-10-13 착수
- 요청: "smarttwinmcp(5013) 개발을 마저 — SmartTwinPreprocessor·Postprocessor 의 모든 커버리지가 MCP 로" +
  "REST API 로도".
- 재부팅이 있었다(커널 5.15.0-191→198) — /tmp 가 비워져 deploy 노드 파일이 사라졌다. 노드 목록은
  스크래치패드에 둔다. LSTC 서버는 재부팅 후 떠 있었다.
- 기준선: lint 0 error/1 warning(submit_job L070), pytest 46 pass/2 fail(기존 결함). 서비스 venv 에 pytest 가
  없어 시험은 업스트림 `/home/koopark/claude/SmartTwinMCP/.venv`(py3.10, fastmcp 3.3.1)로 돌린다.

## 결정
- **도구는 정본에서 생성.** 손으로 120개를 쓰면 다음 기능 추가 때 바로 어긋난다. 정본 4종(KMM·KAM·KCR
  help 카탈로그, kooremapper_core)과 후처리 argparse 를 생성기가 읽는다. 생성물은 커밋한다 — 운영 머신에는
  pyKooCAE·KooRemapper 소스가 없다.
- **계산은 Slurm 잡(backend 경유).** 헤드에서 KMM/후처리를 돌리면 대형 모델에서 메모리·시간이 터지고,
  권한·감사도 우회한다. 기존 규약((C) 하이브리드: 쓰기는 backend)과 같다.
- **범용 템플릿 하나 + 화이트리스트.** backend 는 template_id·files·slurm_overrides(값 검사)·job_name 만
  받는다(env 를 사용자에게서 받지 않는다). 그래서 실행할 도구는 업로드 파일(request.json)로 전달하고 템플릿이
  고정 목록에서만 고른다. argv 는 배열로 실행해 셸 해석이 없다.
- **경로 허용 루트**: 입력·작업 폴더는 `/data/single/<웹사용자>/` 와 `/data/<웹사용자>/`(있으면) 아래만.
  MCP 서버는 koopark 로 돌기 때문에 검사 없이 경로를 받으면 남의 파일을 읽어 올릴 수 있다. 웹사용자는
  backend `/api/me` 로 얻는다. 템플릿에서도 `$WEB_USER`(backend 가 JWT 로 설정)로 다시 검사한다.
- **REST 는 같은 서버(:5013)의 custom route.** 같은 검증·실행 함수를 부르므로 MCP 와 어긋날 수 없다.
  backend_5010 에 따로 만들면 로직이 둘이 된다. nginx 접두는 `/smarttwin-api/` — `/mcp` 는 접두 일치라
  `/mcp…` 로 시작하는 이름은 피했다.
- **kooremapper_core 는 벤더링**(tools/_shared). 운영에 KooRemapper 리포가 없다. 원본과 같은지 시험한다.
- **search 한글 토큰**: 정규식이 [a-z0-9_] 뿐이라 한글 설명이 검색에 안 걸린다. 카탈로그 설명이 한글이라 필요.

## 기존 결함(발견, 범위 밖 — 기록만)
- MCP 의 네이티브 읽기 도구(job_status·audit_* 등)는 PAT 를 검사하지 않는다. nginx `/mcp` 도 인증이 없다.
  → REST 는 PAT 필수로 만들고, MCP 쪽 게이트는 별건으로 사용자에게 알린다.
