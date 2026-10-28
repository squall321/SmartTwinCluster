# 결과 귀환 선행 — 컨텍스트 노트

계기: 2026-10-28 kooremapper-4a 세션이 사용자 지시(「계속 진행 · 나머지 세션도 역할에 맞게」)를 전달.
DynaForge 후처리 예약 연산(KooRemapper `platform/docs/REQUEST-postprocess-operation.md` §7-1, W-93)이
이 리포의 [REQUEST-result-return.md](../REQUEST-result-return.md) A~D 에 걸려 있다. E·F 는 이번 범위 밖.

## 요청서 §4 "이 리포가 정할 것" — 결정

- **소유 대조 키** — `job_submissions.user_id` 를 호출자 `username` 과 **그대로** 비교한다.
  `_sanitize_web_user` 는 이름을 그대로 두거나 `anonymous` 로 바꾸므로, 정상 이름은 그대로 같고,
  `@` 든 이름 등은 기록이 `anonymous` 가 되어 누구와도 맞지 않는다(fail-closed). `user_id='anonymous'` 행은
  admin 만 연다 — 여러 사람이 섞일 수 있는 키라서. app.py(legacy-script)는 정제 전 이름을 기록하므로 그대로 비교가 맞다.
  제출 기록이 없는 잡(대시보드 밖에서 sbatch 한 잡)은 admin 만.
- **admin 판정** — `g.user.role == 'admin'`(smarttwin_mcp list_recent_jobs 와 같은 규칙). SSO 꺼짐이면
  미들웨어가 모두 admin 으로 넣으므로 이 검사는 SSO 켜짐에서만 의미가 있다(운영 SSO 설정은 이 변경 밖).
- **서비스 신원 모델** — 지금은 ③ **사용자 본인 kst_ PAT**(대시보드 'MCP 토큰' 메뉴 발급본)로 부른다.
  새 신원 개념(① 서비스 PAT + 대리 사용자 헤더)은 만들지 않았다 — 대리 헤더를 믿을 근거(서비스 계정 목록·서명)를
  새로 세워야 하고, smarttwin_mcp 가 이미 호출자 PAT 를 그대로 넘기는 모델이라 같은 길이 일관된다.
  admin role 의 PAT 는 모든 잡이 열린다(②와 같은 효과) — DynaForge 서비스 계정에 admin 을 주는 것은 권하지 않는다.
- **다운로드 버튼** — `window.open` 은 헤더를 못 싣는다. blob 다운로드는 결과 ZIP(수십 GB)에서 브라우저 메모리를
  넘으므로, **단기 다운로드 티켓**(JWT_SECRET 서명, 120초, 잡 id 에 묶임, `scope=job-download`)을 발급해
  `?ticket=` 으로 받는다. 티켓은 download·download-all 두 라우트만 받는다.
- **매니페스트 경로·스키마** — `RESULT_DIR/output/return_manifest.json`, `schema: "smarttwin.return_manifest"`,
  `version: 1`. 임시 파일에 쓰고 `os.replace`(같은 디렉터리라 원자적). 리포트 있음/없음은 rc 가 아니라 **파일 유무**.
- **겹침(누가 정본인가)** — KooChainRun submit 이 건 **리포트 잡이 정본**. 리포트 잡 id 가 submit.log 에 있으면
  post_exec 는 그 잡을 기다리고 `postprocess --all` 을 돌리지 않는다. 리포트 잡이 없을 때(제출 실패)만 예전처럼
  드라이버에서 `postprocess --all`. 이유: 드라이버(1 CPU·4G)가 전 Run deep 을 다시 돌리고 sphere 를 리포트 잡과
  같은 때에 다시 써서 sha256 이 흔들렸다. inline deep 은 이미 각 Run 잡 안에서 돈다(auto_deep_mode=inline 기본).
- **D 의 방식** — 리포트가 기대되는데(CHAIN_POSTPROCESS=true) 없으면 드라이버 **exit 3** → `FAILED 3:0`.
  해석 산출물은 그대로 있고, 까닭은 매니페스트에. comment 방식은 accounting 설정(AccountingStoreFlags=job_comment)에
  기대야 해서 고르지 않았다.
- **ssh 대체 길** — 같은 파일(`RESULT_DIR/output/return_manifest.json`)을 읽으면 된다. /data/single 은 NFS 라
  헤드·노드 어디서 읽어도 같다. 권한은 파일 소유자(대시보드 서비스 계정)의 umask 를 따른다.

## 구현 메모
- 매니페스트 작성기는 `dashboard/backend_5010/return_manifest.py` 한 곳. 백엔드가 스크립트를 만들 때
  템플릿 본문에 `write_return_manifest` 가 보이면 그 소스를 셸 함수(heredoc)로 심는다 — 노드에 따로 배포할 파일이 없다.
  C 의 후처리 잡 스크립트도 같은 함수를 심는다.

## 진행 기록 (2026-10-28)
- A `f8552d8c`, B·D `0a8c9cca`, C `2e257262`. 테스트 34건 `cd dashboard/backend_5010 && venv/bin/python -m unittest discover -s tests`
  (venv 에 pytest 가 없어 unittest). `tests/_env.py` 가 SSO·DB·SLURM_BIN_DIR·KOOCHAINRUN_BIN 을 임시 경로로 고정한다.
- 이른 종료 매니페스트가 처음엔 `ok: true` 로 나왔다(기대 판정을 stage=complete 에 묶었던 탓) — 테스트가 잡아 고침.
  이른 종료도 리포트를 기대했던 잡이므로 없음 = ok 아님.
- 후처리 잡의 job_submissions 기록은 원 잡 제출자 명의(user_id) — admin 이 대신 걸어도 그 잡 로그는 원 사용자에게 열린다.
- 실제 Slurm 검증은 못 했다(dev 박스). 운영 반영 뒤 §3-B 확인 항목(성공·sif 틀린 실패·부분충격)으로 볼 것.
- (같은 날 밤) kooremapper-4a 가 pyKooCAE 34203b7(SIF v127) 주의를 전했다. 부분충격 리포트는 `<output_dir>/impact_report.*` 이고
  DWI 의 output_dir 은 runner_config 최상위 키(예제는 `dwi_output`)라 `output/` 고정 탐색이면 놓친다. 작성기가 KooChainRun 의
  output_dir 규칙(project.output_dir → 최상위 output_dir → base_dir/output, 상대는 결과 폴더 기준)을 따르게 고쳤고,
  `job.output_dir` 를 더했다. 매니페스트 위치는 계약대로 `output/` 고정이다. sphere_report.json(런 수에 비례해 커짐)은
  W-93 이 "HTML 만" 이라 reports[] 에 싣지 않았다 — 필요해지면 v1 안에서 키를 더한다.
- 사용자 결정(peer 경유): 운영 반영은 "실제 잡 하나로 검증한 뒤". dev 노드 VM 은 사용자 답 전에는 띄우지 않는다.
  DynaForge 신원은 "예약한 사용자의 kst_ PAT 를 DynaForge 가 암호화해 맡았다가 반입 뒤 지운다".
- 실 Slurm 검증(23:06~23:15): 사용자 결정 "dev 노드 VM 을 띄워 사본으로". node001 만 기동(가용 44.8→약 38GiB, 조건 30GB 이상).
  pykoocae-88 이 node001 에 SIF v127(4d31651f)·Postprocessor v41(6176ff66)을 깔았다(그 배포가 헤드 Preprocessor 도
  v127 로 바꿨고 v126 백업은 없다 — pykoocae-88 이 사용자께 올리기로 함). 사본은 원본 경로를 sed 로 사본 경로로 바꾸고
  원본을 가리키는 심링크를 지웠다. d3plot 은 하드링크(sphere 모드는 읽기만). 제출은 백엔드 서비스 재시작 없이
  scratchpad 드라이버가 Flask 테스트 클라이언트로 새 라우트를 실제 sbatch·squeue 에 붙였다(임시 DB).
  결과: 1245 COMPLETED 0:0 ok·sha256 일치, 1246·1247 FAILED 3:0. 검증 뒤 node001 shut off.
- 실 Slurm 에서 찾은 결함: log_tail 에 지난 실행의 파일(사본에 남은 7월 리포트 잡의 sphere_report.slurm.err)이 섞였다.
  postprocess.by 로 고른다 — report_job 이면 <kind>_report.slurm.{err,out}, driver·postprocess_job 이면 <kind>_report.log.
- 사본 /data/single/admin/RRVerify_{ok_828,fail_1088} 은 남겨 두었다(peer 확인용). 지워도 원본에는 영향이 없다(d3plot 은 하드링크).
