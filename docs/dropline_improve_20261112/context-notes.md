# 낙하 파이프라인 개선(KooSlurm 몫) — 컨텍스트 노트

- **가지·worktree** — cae00 판 고정 중이라 `feat/dropline-check-e2e` 에서 짓는다. 공유 작업트리에서 브랜치를 바꾸면 다른 세션의
  파일이 흔들려 worktree(`KooSlurmInstallAutomationRefactory-wt-dropline`)를 썼다. 보류가 풀리면 main 에 올린다.
- **분담** — 1번(노드 배포 안전)은 kooslurminstallautomationrefactory-de 가 사용자 확인 뒤 맡기로(그쪽 가지 `feat/dropline-node-deploy`).
- **2번 점검 스크립트** — 표준입력(`bash -s`)으로 도는 꼴이라 안의 ssh·apptainer 를 모두 `-n`/`</dev/null`. 기대값은 env 로 받아
  붙여넣기 한 줄에 sha 를 박는다. 판은 sha·커밋으로 본다(SIF 안에 v 번호가 없다). KooChainRun 은 버전 표시가 없어 sha256+md5.
  표본 노드는 sinfo 파티션마다 하나(운영 YAML 의 노드 ssh_user 는 전부 koopark). 닿지 않는 노드는 ERR(종료 1).
- **3번 E2E** — 결과 사본은 새로 만들었다(`RRVerify_ok_828` 은 10-28 검증 기록이라 건드리지 않음). 시험 잡 번호 9000001 은
  dev Slurm·DB 에 없는 번호 — 기존 828 기록(원본·admin)을 덮지 않으려고. 소유자 `e2etest` 는 위임 창구가 거절하지 않는 이름.
- **비밀** — 메시지·문서에 값을 싣지 않고 `~/.config/smarttwin/dev_kooslurm_sso_secret`(600)을 양쪽이 읽는다(같은 리눅스 계정).
  dev 백엔드 `.env` 가 755 였어 600 으로 좁혔다.
- **SSO** — dev 는 꺼진 채로 돈다. 켜면 같은 박스의 다른 세션(smarttwin_mcp 등)이 깨진다. 소유 검사는 백엔드 단위 시험이 본다.
