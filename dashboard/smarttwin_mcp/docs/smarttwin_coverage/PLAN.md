<!-- SmartTwin 전처리·후처리 전 기능을 MCP(:5013)와 REST 로 노출하는 계획 -->
# SmartTwin 전 기능 MCP + REST 커버리지 (2026-10-13)

## 목표
SmartTwinPreprocessor(SIF v112)와 SmartTwinPostprocessor(10-02 빌드)의 **모든 기능**을
smarttwin-mcp(:5013)에서 MCP 도구로, 그리고 **같은 카탈로그를 REST API 로도** 쓸 수 있게 한다.
"새 기능이 생기면 카탈로그만 고치고 생성기를 다시 돌리면 MCP·REST 에 같이 나타난다"가 완료 기준이다.

## 현재 (조사 결과)
44 도구 중 SmartTwin 기능은 DROP(피보나치·단일각도)과 KooChainRun 후속 명령(status/collect/
postprocess/diagnose/rerun/stop)뿐이다. 나머지는 전부 빠져 있다.

| 영역 | 기능 수 | 정본(권위 소스) | 현재 MCP |
|---|---|---|---|
| KooMeshModifier 모드 | 32 | pyKooCAE `occProject/Generators/KooCLIHelp/kmm_catalog.py` | 0 |
| KooAutomatedModeller 모드 | 6 | 같은 폴더 `kam_catalog.py` | 0 |
| KooRemapper op | 60 | KooRemapper `platform/core/kooremapper_core` (스키마·build_command) | 0 |
| KooChainRun 시나리오 모드·워크플로우 | 7 | pyKooCAE `Runner/cli_help_kcr.py` | DROP 일부 |
| KooChainRun 명령 | 11 | 같은 파일 | 6 (run 은 계산노드 내부용) |
| 후처리 실행 파일 | 11 | Post SIF `/opt/kood3plot/bin` (argparse `--help`) | postprocess(all/deep/sphere)만 |

## 설계

### 1. 도구 = 정본 카탈로그에서 **생성**
- `tools/_gen/generate_smarttwin_tools.py` 가 위 정본을 읽어 `tools/<이름>/1.0.0/{meta.yaml,
  args.schema.json, script.sh}` 를 만든다. 생성물은 커밋한다(운영 머신에는 소스가 없다).
- 이름: `kmm_<mode>`, `kam_<mode>`, `remap_<op>`, `post_<tool>`, `scenario_<mode>`.
- 설명(meta.description)에 카탈로그의 when/syntax/keys/examples/notes 를 그대로 싣는다 →
  `catalog_describe` 한 번이면 그 기능의 전체 사용법이 나온다.
- 커버리지 시험: 정본의 모든 모드/op/도구에 대응 도구가 있어야 통과(소스가 없으면 skip).

### 2. 실행 = backend_5010 Slurm 잡 (권한·감사 경유, 기존 (C) 하이브리드 규약)
- 전처리·후처리 계산은 헤드에서 돌리지 않는다(대형 모델은 수 GB·수십 분). 새 범용 템플릿
  `smarttwin-tool` 로 **잡 하나**를 낸다. 도구는 입력 파일을 만들어 올리고 job_id 를 돌려준다.
- 템플릿은 업로드된 `request.json` 의 실행 파일을 **화이트리스트**로만 고르고 argv 를 배열로
  실행한다(셸 보간 없음). backend 는 env 를 사용자 입력으로 받지 않으므로 주입 경로가 없다.
- 기존 결과 폴더에 대한 후처리는 업로드 없이 그 폴더에서 실행 — 경로는 `/data/single/<웹사용자>/`
  (와 `/data/<웹사용자>/`) 아래만 허용. MCP 와 템플릿 **양쪽**에서 검사한다.
- 시나리오(KooChainRun)는 새 드라이버 템플릿 `smarttwin-scenario`(기존 전각도 드라이버와 같은
  prepare→submit→대기→collect→postprocess, 모드 무관). DWI 는 기존 `smarttwin-partial-impact`.
- `dry_run` 은 PAT 없이도 생성될 입력 파일·명령을 돌려준다(LLM 이 먼저 확인하도록).
- `wait_sec` 를 주면 그 시간 안에 끝난 결과(rc·로그 꼬리·작은 산출물)를 바로 돌려준다.

### 3. REST = 같은 카탈로그, 같은 서버(:5013)
- FastMCP custom route 로 `GET /api/v1/tools`(검색) · `GET /api/v1/tools/{name}`(설명·스키마) ·
  `GET /api/v1/tools/{name}/versions` · `POST /api/v1/tools/{name}/run` · `GET /api/v1/openapi.json`.
- MCP 와 **같은 함수**(검증·실행·PAT 패스스루)를 부르므로 패리티가 구조적으로 보장된다.
- nginx `/smarttwin-api/` → `127.0.0.1:5013/api/` (정본 conf + 라이브 conf 둘 다).
- REST 는 PAT 를 backend `/api/me` 로 검증한다(캐시). MCP 는 기존 동작 유지(별건으로 노트).

### 4. 정본 갱신
- `cli_help_kcr.py` 가 09-17 본이라 10-03~07 기능(deformable_to_rigid 세부·drop_contact
  InheritGeneral/Type/Scope·convert_general_to_single_surface 등)이 없다 → 정본부터 고친다.
  KooChainRun 재빌드 → SIF v113 → tar → 노드 배포(절차 고정).

## 성공 기준
1. 커버리지 시험: 32 + 6 + 60(−version) + 7 + 11 + 11 전부 대응 도구 존재.
2. lint 0 error, 기존+신규 pytest 전부 통과.
3. 실잡 e2e(backend 경유): KooRemapper info · KMM TRANSFORM · KAM PKG · 후처리 1종 · 시나리오 dry_run.
4. nginx 경유 MCP 와 REST 로 같은 도구를 불러 같은 결과.
