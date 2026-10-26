<!-- 레시피 등록소 — 결정과 근거 -->
# 결정 노트 — 레시피 등록소 (2026-10-26)

## 조사에서 확인한 사실
- **KMM 은 확장 지점이 없다.**
  - 모드 32개가 if/elif 로 굳어 있고, 모르는 모드면 exit 한다.
  - KMM·KooChainRun·KAM 어디에도 외부 .py 로더(exec·importlib·runpy)가 없다.
  - 모드를 하나 더하면 KMM.py 4곳·AdvMod·kmm_catalog·KCR·MCP 생성기를 고치고, 전체 빌드와 SIF·노드 배포를 거쳐야 한다.
- **재빌드 없이 쌓이는 층은 데이터뿐이다.** MCP 카탈로그(tools/<이름>/<판>/ + catalog_reload), kmm_chain 의 modes[{mode, options, lines}], 후처리 YAML(unified_analyzer·custom_report·federate).
- **결과 폴더에 잡 입력이 남는다.** 잡 결과 폴더는 /data/single/<사용자>/<잡이름>_<id>/ 이고, 안에 stmc_result.json(tool·rc·argv·inputs·outputs)과 work/(stmc_options.txt 등 입력 글)이 있다. registry(jobs.db)는 인자를 저장하지 않는다 — 그래서 근거 확인은 work/ 의 입력 글과 비교한다.
- **비슷한 본보기가 있다.** HWAXPortal procedures 가 SQLite 에 소유자별 판으로 저장하고, 실행 기록에서 초안을 만들고, 확정은 사람이 한다.

## 결정
- **레시피는 코드가 아니라 기존 도구 인자의 틀이다.**
  - 컴파일 KMM 안에서 LLM 이 쓴 Python 을 exec 하면 Nuitka 제약(번들 밖 모듈 없음·컴파일본 전용 결함)과 "올라온 파일은 실행 불가" 설계를 함께 깬다.
  - 인자 틀이면 원래 도구 경로의 검증(키 정규식·구조 줄 금지·경로 범위)을 그대로 거친다.
- **관문은 '근거 잡과 같은 입력' 이다.** 운영 호출자는 감시받는 서버팜 LLM 뿐이라(사용자 결정) 사람 승인 단계를 두지 않는다. 대신 레시피가 효과를 본 실행을 정확히 재현하는지 기계로 확인한다 — 펼친 입력 글이 근거 잡의 work/ 파일과 바이트로 같아야 한다.
- **판은 고정이고 덮어쓰지 않는다.** 판이 바뀌면 새 판 번호를 쓴다. 내리기(retire)는 표시만 바꾼다 — 예전 결과가 어느 판으로 돌았는지 늘 다시 볼 수 있게 한다.
- **저장은 NFS 파일(YAML)이다.** 헤드·노드·사람이 그대로 읽을 수 있고, 판마다 파일 하나라 diff 가 쉽다. 쓰기는 임시 파일 + rename 으로 원자적이고, 판 번호는 이름별 잠금(fcntl) 안에서 정한다.
- **KMM 명령줄 펼치기(`*Recipe`)는 다음 KMM 판으로 미룬다.** 빌드가 한 번 필요하다. 1단계(MCP)는 LLM 경로를 전부 덮는다.
