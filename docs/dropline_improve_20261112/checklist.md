# 스마트트윈 낙하 파이프라인 개선 — KooSlurm 몫 (2026-11-12)

요청: hwaxportal-a5(사용자 지시 11-12 「우리가 해 줄 수 있는 건 개선한다」). cae00 판 고정 중 → 가지 `feat/dropline-check-e2e`
(worktree `KooSlurmInstallAutomationRefactory-wt-dropline`)에서 짓고 보류가 풀리면 올린다 → 11-14 판 고정 해제(포털), main 에 올림. 결정 근거는 [context-notes.md](context-notes.md).

## 분담
- [ ] 1. 노드 배포 안전(phase8_containers.sh --image, deploy_compute_images.sh) — kooslurminstallautomationrefactory-de 에 제안
- [x] 2. 읽기 전용 이미지 점검 스크립트 — 이쪽 → [image_check.md](image_check.md)
- [x] 3. 해석기 없는 dev E2E 차례 — 이쪽(준비 끝, ① 까지 실행, 메모리로 멈춤)

## 2. 읽기 전용 이미지 점검
- [x] 점검 항목·경로 확정(헤드·표본 노드·NFS: SIF sha256, /opt/kood3plot/VERSION, KooRemapper BUILD_INFO, NFS KooChainRun sha, /data/SmartTwinPostprocessor 판)
- [x] 스크립트 — 기대값을 맨 위 변수로, `ssh stcx 'bash -s' < 스크립트` 로 돈다, 아무것도 설치·변경하지 않는다, 표 출력
- [x] dev 박스에서 실제로 돌려 표가 나오는지

## 3. dev E2E
- [x] DynaForge 후처리 예약 흐름 확인(예약 만들기·위임·폴링·반입)
- [x] dev 설정(KooSlurm 쪽) — 비밀 파일·dev 백엔드 HEAX_GATEWAY_SECRET·결과 사본·시험 잡 기록 9000001 / [ ] DynaForge dev 의 KOORM_* (kooremapper-fd)
- [x] 노드 이미지 Pre v136·Post v51 — node001 에 원자 교체로 맞춤(11-12, deploy_apptainers.sh 는 헤드 제자리 cp 때문에 쓰지 않음)
- [ ] ②~⑤ 실행 — 11-12 메모리 조건(가용 30GB)으로 멈춤, 다시 돌릴 때 사용자 재확인
- [x] 차례 문서 — [dev_e2e_runbook.md](dev_e2e_runbook.md), 포털에 알림(VM 은 포털이 켠다)
