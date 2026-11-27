<!-- SM 묶음 작업 중 결정과 근거 -->
# 컨텍스트 노트 — SM 묶음 (2026-11-25)

- SM-04: 이름으로 admin 을 막지 않는다 — 실제 웹 사용자 admin 이 있다(/data/single/admin 캠페인). SSO 꺼짐으로 풀린 admin 은
  /api/me 의 auth=sso_off 로 가린다(요청서 대안안). MCP 는 auth==pat 만 받는다 → backend 를 먼저 올려야 MCP 가 산다(배포 순서).
- 운영 박스(cae00)의 backend_5010 도 같이 올라가야 그쪽 MCP 가 산다 — 운영 수작업에 적을 것.
- REST PatVerifier 도 /api/me 로만 확인하던 관문이라 같은 auth==pat 을 건다(SSO 꺼짐이면 아무 Bearer 나 admin 으로 통과했다).
- job_helpers.backend_submit·submit_job/1.2.0 의 /api/me 는 backend 가 제출을 허가한 뒤 결과 폴더 이름만 읽는 것 — backend 신원과 같은 값이라 그대로 둠.
- 위임 PAT 의 권한은 DELEGATE_IDENTITY(role user, permissions [dashboard]). MCP 가 부르는 /api/jobs/submit·preview·rerun 은 dashboard 만 요구 → 고친 뒤에도 막히지 않는다.
- dev backend 는 dashboard_backend.service, SSO_ENABLED=false(.env) — 이 결함이 실제로 걸린 상태였다.
- push 보류(사용자 결정 11-25): 6차 받은 편지함 글이 KooSlurm main 을 d93017a5(SM-04 포함)로 박았다. SM-01~03·카탈로그는 모두 끝낸 뒤 한 번에 판으로 —
  그때까지 가지에만 두고, main push 전에 hwaxportal-71 에 먼저 알린다. live 트리가 main 이라 dev 반영(재시작)도 그때까지 없다.
- d93017a5 판 운영에서는 SM-01 의 세 도구가 여전히 PAT 없이 열려 있다 → 게이트웨이 grant_only 유지 권고(71 에 전함).
- SM-01: 잡에 호출자를 남기는 기존 관례가 없어 요청서 예시 --comment=stmc:<호출자> 를 쓴다(caller 는 _USER_RE 를 지난 이름).
- SM-01: submit_lsdyna_remote 는 닫는다 — 서버 env 에 STMC_CLUSTER_HEAD 가 없어 dev 에서 애초에 못 돌고, registry 사용 기록 0. 같은 일은 submit_lsdyna_job(backend 경유).
  transport 를 local 로 바꿔 ssh 를 열지 않고 거절만 돌려준다. 1.0.0 도 transport local(1.1.0 으로 위임).
- SM-01: train_script 위치는 요청 범위 밖이라 보지 않는다(work_dir 만). dry_run 도 이제 PAT 가 있어야 한다(요청서 '남의 work_dir → dry_run 에서도 거절').
- SM-02: mode-read 태그를 따르라는 요청서 문장은 쓰지 않는다 — hwaxportal-71 정정대로 mode-* 는 시야 구분(job_status 같은 읽기도 mode-own). meta.yaml 에 read_only 칸을 따로.
- SM-02: job_diagnose(KooChainRun diagnose 가 파일을 쓰는지 확인 못 함)·job_collect(요약 파일을 씀)는 read_only 를 달지 않았다 — 확실한 것만. readOnlyHint 는 모든 직접 도구에 true/false 로 명시.
- SM-02: fastmcp 3.3.1 tool(annotations=dict) 동작 확인(ToolAnnotations 로 바뀜).
- SM-03: SHA256SUMS 는 dev main 트리의 wheel 68개로 만들었다. cae00 의 wheel 이 다른 판이면 설치기가 불일치로 멈춘다 — 그때는 그쪽 wheel 로 다시 만들 것.
- SM-03: 이미 깔린 유닛(/etc/systemd/system/smarttwin-mcp.service)은 건드리지 않는다 — 새로 설치할 때만 의미가 있다. 운영 재설치 불필요.
- B: 운영 MCP 는 배포 리포 판 길(build→push→stage→swap)로 바뀌고 판 폴더는 smarttwin_mcp 만 담는다(71, Q45). 리포 뿌리를 넘는 경로는 운영에서 없다 —
  image_version_check 는 tools/_shared 사본으로. 착지 안내에 「KooSlurm git + start_production.sh」 외에 MCP 판 길을 따로 적을 것.
- E1: 직접 도구 호출 꼴이 바뀐다 — 이제 납작한 인자({"registry_id": 1, "runs": true})가 정본이고, 옛 꼴 {"args": {...}} 은 카탈로그 스키마에 args 칸이 없을 때만 풀어 받는다(호환).
  kooremapper-4a(C-1 runs 를 args 안에 넣는다고 적어 둠)·포털에 알릴 것.
- E1: 직접 도구 실행은 anyio.to_thread 로 — run_tool 이 subprocess 로 막히므로. Authorization 은 요청 컨텍스트에서 먼저 읽어 넘긴다.
- 린트 L070 경고 하나 늘었다: 닫은 submit_lsdyna_remote 1.1.0 에 dry_run 인자가 남아 변경 도구로 잡힘(1.0.0 위임 시험이 두 판 스키마 동일을 요구). 오류 아님 — 둠.
- C(SH): 로그 환경값은 새 이름(JOB_LOGS_BASE) 대신 읽는 쪽(job_logs_api)이 이미 쓰던 JOB_LOGS_DIR 를 쓰는 쪽에도 쓴다 — 한 이름으로 맞춤. 업로드는 UPLOAD_BASE(새). 기본값은 예전과 같아 환경값이 없으면 동작이 그대로(dev 는 SHARED_BASE=/data).
- C(SH): lsdyna_submit_api 의 lsdyna_uploads 도 같은 결함이라 함께 UPLOAD_BASE 로. ensure_dir 실패는 job_submit_api import 때 RuntimeError → gunicorn 기동 실패(SH-04).
- C(SH): 운영 손일 — .env 에 UPLOAD_BASE=/data/<…>, JOB_LOGS_DIR=/data/<…>/logs 두 줄, 그 폴더를 실행 계정 소유로. 값이 없거나 못 만들면 backend 가 안 뜬다(예전엔 조용히 /tmp).
- SH-04 의 「헤드에서 쓴 표시 파일을 계산 노드 하나에서 읽어 보는 점검」은 안 함 — 기동 중 srun 은 큐 상태에 묶여 기동을 막을 수 있다. 노드 배포 Step 4.5 가 /data 마운트를 본다.
- check_vnc_job_script.sh 는 이 일 전부터 83행 문법 오류(for file in $path_pattern 2>/dev/null) — 범위 밖이라 둠(보고만).
- A: 운영 stcx 깔린 판은 Pre v128 · Post v53(71 바로잡음 11-26). 새 KCR 명령 도구는 실행 전 `KooChainRun <cmd> --help` 로 판을 보고 koochainrun_outdated 로 거절.
  생성 도구(KMM·post)는 잡 안에서 SIF 가 모르는 키를 만나면 rc 1 — 설명에 판 경고 한 줄과 image_version_check 안내.
- A: 사용자 결정(11-27) — extract·d3plot-delete·keeper 는 required_extractions command 를 실행(헤드·서비스 계정)할 수 있음을 알고 그대로 도구화. 설명에 ⚠ 로 적음.
- A: smarttwin-tool 템플릿은 backend 가 SHARED_BASE/templates 에서 읽는다. start_production.sh 가 /shared/templates 로 동기화(운영). dev 는 SHARED_BASE=/data 라 /data/templates 로 손 복사 필요.
- A: test_vendored_kooremapper_core_matches_source 는 사본(노드 SIF v119 판 44f16c9 에 고정)과 KooRemapper HEAD 를 비교해 늘 실패 — 「HEAD 를 따른다」와 「깔린 SIF 판에 고정」 중 사용자 결정 필요.
- KS-AP3: 끝난 여러 잡이 섞이면 cancelled > failed > completed. 하나라도 돌면 running, 대기만 있으면 queued, 모르는 상태가 섞이면 unknown.
  KR-10(DynaForge 의 종료 판정 고정)은 이 칸으로 닫을 수 있다 — 저쪽 첫 실제 제출 원문으로 확인할 것.
