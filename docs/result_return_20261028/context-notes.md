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
