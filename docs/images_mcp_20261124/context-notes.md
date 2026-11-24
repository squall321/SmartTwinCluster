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
