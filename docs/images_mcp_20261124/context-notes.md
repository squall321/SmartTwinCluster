# 귀환 매니페스트 이미지 출처(⑥)·이미지 점검 MCP 도구(⑨) — 컨텍스트 노트

요청: hwaxportal-87(사용자 지시 11-24, 포털 docs/smarttwin-pipeline/PLAN.md §3 ⑥·⑨). 5차 cae00 동결 중 → 가지
`feat/images-manifest-mcp`(worktree `KooSlurmInstallAutomationRefactory-wt-images`), push 는 해제 알림 뒤.

## ⑥ images{}
- **어느 노드** — 작성기는 매니페스트를 쓰는 노드에서 돈다(드라이버 post_exec 또는 C 후처리 잡). C·드라이버 inline 은 리포트를 같은
  노드에서 만드니 그 노드가 곧 리포트 노드. 리포트 잡(KooChainRun 이 건 sbatch)은 다른 노드라 sacct NodeList 로 이름만 남기고,
  그 노드의 SIF 출처는 리포트 셸이 곁에 `<kind>_report.images.json` 을 쓰면 싣는다(선택 — pyKooCAE 리포트 셸 몫, 제안으로 보냄).
  F4(리포트 셸의 헤드·노드 판 탐침)를 정확히 대신하려면 리포트 노드 출처가 필요해서 이 자리를 열어 둔다.
- **판 글자** — SIF 안에 v 번호가 없다. Post 는 `/opt/kood3plot/VERSION`(KooD3plotReader 커밋), KooRemapper 는 BUILD_INFO 의 소스 커밋,
  Pre 전처리 판은 pyKooCAE 가 `/opt/SmartTwinPreprocessor/VERSION`(`Version: …` 한 줄, kood3plot 와 같은 꼴)을 넣기로 제안 — 없으면 null.
- **비용** — 매니페스트를 쓸 때마다 노드 SIF 두 개 sha256(약 2.7 GB 읽기)과 apptainer exec 세 번. 잡당 한 번이라 받아들인다.
- **실패 접기** — 출처 수집은 매니페스트를 막지 않는다(예외 → error 칸). ok·종료 코드와 무관, version 1 그대로(칸 추가).
- **시험** — `tests/_env.py` 가 `SMARTTWIN_SIF_DIR` 를 빈 임시 폴더로 — 그러지 않으면 드라이버 post_exec 시험이 dev 의 실 SIF(수 GB)를 해시한다.

## ⑨ image_version_check MCP 도구
- `cluster/utils/image_version_check.sh` 를 그대로 감싼다(로직 한 벌) — markdown 표를 `rows[{where,item,actual,expected,verdict}]`·`counts`·
  `all_ok` 로 바꾸고 원 표는 `table` 로 함께 준다. 스크립트 경로는 도구 폴더에서 다섯 단계 위(리포 뿌리), 시험·다른 배치는 `STMC_IMAGE_CHECK_SCRIPT`.
- DIFF 는 도구 실패가 아니다(`ok:true`, `all_ok:false`) — 점검을 했고 판이 다르다는 결과. 스크립트가 없거나 표가 안 나오면 `ok:false`.
- 서버 프로세스 env 의 `EXPECT_*` 가 새어 들지 않게 매번 지우고 인자로만 채운다.
- mode-read-all, local, expose: catalog(`catalog_run image_version_check`). 노드 sha256 이 노드당 수십 초라 timeout 900.
- 게이트웨이 등재는 하지 않는다 — stcx `:5013` 확인(PA-16) 뒤 포털이 다음 받은 편지함 물음으로.
- 시험: smarttwin_mcp venv 에 pytest 가 없어(돌고 있는 서비스의 venv 라 건드리지 않음) scratchpad 의 별도 venv + 서비스 venv site-packages 를
  PYTHONPATH 로. 전 스위트 343 통과·3 실패 — 실패 셋은 기준선(이 변경 전)과 같다: KMM 모드·vendored kooremapper_core·KooChainRun 명령이
  외부 원천과 어긋난 커버리지 시험(다른 리포가 앞서 나감).
- dev 헤드 실측(11-24): 이미지가 Pre v141(11-22)·Post v54(11-23)로 바뀌어 v136·v51 기대값과는 모두 DIFF — 도구가 맞게 본 것.
  image_check.md 의 기대값은 그 판(v136·v51) 기준이라 다음 라운드 붙여넣기 전에 값을 새로 읽어 넣을 것.
