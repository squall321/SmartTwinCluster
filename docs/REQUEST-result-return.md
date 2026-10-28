# 요청 — 해석 결과를 DynaForge 로 **자동으로 돌려받기** 위한 클러스터 쪽 선행(파일 REST 인증·귀환 매니페스트·후처리 잡 제출 경로)

**보내는 곳** HWAX Portal · 절차(procedures) 기능
**날짜** 2026-09-17
**한 줄** 전각도 낙하·전위치 부분충격 잡이 끝나면 DynaForge 가 **리포트 HTML 만** 받아 가려 합니다. 기본 길은 대시보드
파일 REST 인데 지금은 **토큰 없이 열리고**, "끝났다·무엇이 생겼다" 를 알릴 **한 장**이 없고, 리포트가 없을 때 DynaForge 가
**후처리 잡을 걸 경로**가 없습니다. 이 셋을 먼저 부탁드립니다.
**성격** 선행 작업 요청입니다. 모양(경로·스키마·신원 모델)은 이 리포가 정해 주십시오.

---

## 1. 왜 지금 쓰나

사용자가 정한 모양입니다(HWAXPortal `docs/procedures/context-notes.md` W-93).

```
제출(smarttwin_submit 씨앗)  →  d3plot 은 클러스터에 남는다(잡 하나 37~50GB — 나르지 않는다)
DynaForge 후처리 연산         →  클러스터에 후처리 잡을 건다(대시보드 REST 기본, 안 되면 ssh)
                              →  끝나면 sphere/impact 리포트 HTML(약 10MB)만 받아 반입 → report_id
판독(부품 보고서 씨앗)         →  report_* 도구 — 지금 설계 그대로
```

평상시에는 드라이버가 이미 거는 리포트 잡(pyKooCAE `KooChainRun` 1454-1462)이 끝나기를 기다렸다 HTML 을 **받기만** 하면 됩니다.
DynaForge 가 **직접 후처리 잡을 거는** 것은 리포트가 없거나(부분충격·후처리 실패) 다시 돌릴 때입니다 — 그 길은 부탁 C 입니다.

클러스터로 가는 길은 **대시보드 REST 가 기본, ssh 가 대체**입니다. 리포트 명의는 제출 때 예약한 사람입니다.
DynaForge 쪽 부탁은 KooRemapper `platform/docs/REQUEST-postprocess-operation.md` §7 에 따로 올렸습니다. 이 문서는 그중
**클러스터가 먼저 해 줘야 하는 몫**입니다. 이게 없으면 DynaForge 구현이 인증 결함에 기대거나 "끝났나" 를 짐작하게 됩니다.

## 2. 확인한 현재 상태 (2026-09-17, 이 리포 `351c7787` · pyKooCAE dev 소스 `bf32432` 기준)

코드를 읽고, 파일 REST 는 백엔드 venv 의 Flask 테스트 클라이언트로 **로컬 재현**했습니다(임시 DB·임시 디렉터리, 서버 호출 없음).
운영 nginx·운영 slurm.conf·클러스터에 배포된 KooChainRun 판본은 **확인 못 했습니다.**

| | 지금 | 근거 |
|---|---|---|
| 파일 REST 인증 | `/api/jobs/<id>/…` 8개 라우트가 전부 `@optional_jwt`. SSO 켜짐이어도 토큰이 없거나 틀리면 `g.user=None` 으로 **그대로 진행**, SSO 꺼짐이면 admin | `dashboard/backend_5010/job_logs_api.py` 194·242·349·410·502·575·642·703, `middleware/jwt_middleware.py` 291-293·295-325 |
| 소유 검사 | 모듈 어디에도 `g.user` 대조 없음. 재현: 토큰 없음 200, 쓰레기 토큰 200 | `job_logs_api.py` 전체 |
| 경로 검사 | `startswith` 에 구분자 없음 → 잡 `A_12` 로 `../A_123/output/sphere_report.html` 이 **200**. LOGS_DIR 허용 탓에 남의 잡 로그도 200 | 같은 파일 618-620(download)·538-540(view)·667(download-all) |
| `path=stdout` | download 에서 `job_dir` 가 else 가지에서만 정해져 로그 파일이 **있으면 500**(UnboundLocalError), 없으면 404. `path=stderr` 도 같다. view 는 200. 대시보드의 로그 다운로드 버튼이 바로 이 호출 | 596-602·608-615, `frontend_3010/src/components/JobManagement/JobLogViewer.tsx` 241-247·494·502 |
| 앞단 | 리포 nginx 템플릿의 `/api/` 는 인증 없이 프록시. MCP 읽기 도구는 `/api/me` 로 막지만 REST 를 직접 부르면 안 거침 | `cluster/config/nginx_web_production.conf` 61-63, `dashboard/mcp_slurm/server.py` 141-157 |
| 드라이버 종료코드 | pre·main·post 를 `set -e` 없이 이어 붙임. pre·main 의 명시 `exit 1` 은 실패로 남지만, post_exec 의 collect·postprocess 실패는 `\|\| echo WARN` 이 삼키고 마지막 `echo` 로 **0** | `job_submit_api.py` 872-879, `templates/official/simulation/smarttwin-fullangle-drop.yaml` 207-212·218-221, `smarttwin-partial-impact.yaml` 244-249 |
| 그 WARN 조차 | KooChainRun `postprocess` 는 `sphere_report.sh` 가 rc≠0 이어도 **0 으로 끝남**. 비영 종료는 runner_config·output_dir 가 없거나 잡히지 않은 예외가 날 때뿐이고, `sphere_report.sh` 가 없어도·deep 이 실패해도 0. 실패는 드라이버 로그의 `✗ rc=N, log=…` 한 줄로만 남습니다 | pyKooCAE `KooChainRun` 3186-3203·3272-3277·3281-3283·3292-3295(dev 소스) |
| 완료 알림 | 제출 기록 status 는 INSERT 때 `'submitted'` 이고 UPDATE 0건. `jobcomp/none`, Epilog 주석. `broadcast_job_update` 는 정의만 있고 호출 0건(`websocket_5011` 사본도 같음). `job_completed` 알림은 MOCK·시드 샘플뿐 | `job_submit_api.py` 236-242, `cluster/config/slurm_template.conf` 137·234-238, `backend_5010/websocket_server_enhanced.py` 225, `websocket_5011/websocket_server_enhanced.py` 255, `backend_5010/notifications_api.py` 57-62, `database/schema.sql` 138 |
| 리포트 잡 id | `KooChainRun submit` 이 `→ Sphere Job ID: N`(부분충격은 `Impact`)을 출력하고 드라이버가 `tee submit.log` 로 남김. 드라이버 대기 목록은 `Submitted batch job N` 을 grep 하고 없으면 `jobs.json` 의 job_id 로 폴백하는데, 리포트 잡 id 는 **어느 쪽에도 없어**(리포트 잡 제출은 `jobs.json` 에 기록 안 함) 리포트 잡을 기다리지 않음 | pyKooCAE `KooChainRun` 1454-1462, `smarttwin-fullangle-drop.yaml` 171-173·182-185·193-199 |
| 겹침(추론) | 리포트 잡은 자식들에 `afterany` 로 걸려, 드라이버 대기가 끝나는 무렵 함께 풀림. 그때 post_exec `postprocess --all` 도 같은 `sphere_report.sh` 를 돌릴 수 있고, deep 리포트도 전 Run 에 대해 다시 돈다. **실측 아님** | pyKooCAE `Runner/PostprocessShellGenerator.py` 530-531·551, `KooChainRun` 3279-3296 |
| 후처리 잡 템플릿 | 대시보드 템플릿에 후처리·리포트 전용 잡이 없다(`dashboard/templates` 에 post·report·sphere 이름 0건). `/api/jobs/submit` 은 사용자 JWT 전제 | `job_submit_api.py` 884-885 |
| 결과 폴더 안내 | MCP 는 `{job_name or template_id}_{job_id}` 로 안내. 실제는 빈 이름이면 템플릿 **표시 이름**, 그다음 `\w` 정제 뒤 ASCII 정제. 빈 이름 → 실제 `SmartTwin_________Full-Angle_Drop__<id>`, `낙하_A22` → `___A22_<id>`. 제출 응답에 `result_dir` 없음(DB 에는 기록) | `mcp_slurm/server.py` 1177, `job_submit_api.py` 802·808·1114-1115·1269-1270·1304-1311 |
| 카탈로그 물성 | `_DROP_OPTIONS_DOC` 는 바닥 기본을 `7.85e-9`/`2.0e5` 라 적지만, base 인 각도 프리셋 5종(dev 사본 `/data/scenario/*/scenario.json`)은 **7850 / 2e11**. 이 리포의 `smarttwin_mcp` 사본도 SI 기본값 | `server.py` 717-718·1075-1078, `smarttwin-fullangle-drop.yaml` 98-104, `dashboard/smarttwin_mcp/tools/_shared/scenario_builder.py` 81-82, `…/scenario_full_reference/1.0.0/script.sh` 94-95 |

## 3. 부탁

### A. 대시보드 파일 REST 에 인증·소유 검사를 붙여 주십시오 — REST 기본 길의 선행

- **근거** §2 앞의 네 줄(무인증·무소유·구분자 없는 경로 검사·stdout 500).
- **왜** DynaForge 가 기본 길로 이 REST 를 부르게 됩니다. 지금 모양에 기대면 "토큰 없이도 되더라" 가 설계의 일부가 됩니다.
  결과 폴더에는 남의 잡 산출물도 같은 규칙(`/data/single/<사용자>/…`)으로 놓여 있습니다.
- **어떻게(제안)** ① 토큰 필수(`jwt_required` 계열) ② 잡 소유자 대조(`job_submissions.user_id` 는 제출 때의 정제된 username,
  `job_submit_api.py` 1120-1121·1262). ⚠ `_sanitize_web_user`(657-667)가 `[A-Za-z0-9._-]{1,32}` 밖의 이름(`@` 가 든 이메일 등)을
  모두 `anonymous` 로 바꾸므로, 그대로 대조 키로 쓰면 그런 사용자끼리 서로 열립니다 — **대조 키도 정해 주십시오** ③ 경로 검사를 `real == base or real.startswith(base + os.sep)` 로 ④ download 에서 `job_dir`
  를 분기 전에 정하기. DynaForge 는 **서비스 자격**으로 부를 가능성이 큽니다 — 그때의 신원 모델은 §4 에서 정해 주십시오.
- **주의** 대시보드 다운로드 버튼은 `window.open` 으로 열어 헤더를 못 싣습니다(`JobLogViewer.tsx` 245-246·353). 토큰을
  필수로 하면 그 버튼이 같이 막히니 함께 봐 주십시오.
- **확인** 테스트 클라이언트로 — 토큰 없음 401, 남의 잡 403, `A_12` 에서 `../A_123/…` 403, `path=stdout` 200,
  서비스 자격 + 대리 사용자(허용된 경우) 200.

### B. 귀환 매니페스트 — 드라이버가 리포트 잡을 기다린 뒤 한 장을 써 주십시오

- **근거** 완료 알림이 없고(§2), 후처리 실패는 종료코드·WARN 에는 안 남고 드라이버 로그의 `✗ rc=N, log=…` 한 줄로만 남고,
  드라이버는 리포트 잡을 안 기다립니다.
- **왜** DynaForge 가 "끝났나·무엇이 생겼나·없으면 왜" 를 **한 파일로** 보게 하려는 것입니다. 파일이 생기는 것 자체가 끝남
  신호가 되므로 알림 체계를 새로 만들 필요가 없습니다. REST 든 ssh 든 같은 파일을 읽습니다.
- **어떻게(제안)** post_exec 에서 ① `submit.log` 의 `(Sphere|Impact) Job ID: N` 을 뽑아 기존 `squeue` 대기 방식으로 기다림
  ② `RESULT_DIR/output/return_manifest.json` 을 **임시 파일에 쓰고 `mv`**(반쯤 쓴 파일을 끝남으로 오인하지 않게).
  담을 것 — slurm 잡 id·job_name·대시보드 사용자(`WEB_USER`)·sim_type·작성 시각·후처리 rc·리포트 잡 id 와 그 sacct 상태,
  리포트별 `{경로(RESULT_DIR 기준), 크기, sha256, 있음/없음, 없으면 이유}`. 이유는 rc 가 아니라 **파일 유무**로 판정하고
  `sphere_report.slurm.err` 끝 몇 줄을 붙여 주십시오(rc 는 §2 대로 믿을 수 없습니다).
- **부분충격** 지금은 `impact_report.sh` 가 안 생겨 리포트가 0건입니다(pyKooCAE 쪽 일, 따로 요청). 그 동안에도 매니페스트는
  **"없음·이유"** 로 써 주십시오 — 없는 것을 없다고 말하는 한 장이 필요합니다.
- **확인** 성공 잡 하나·후처리 실패 잡 하나(예: sif 경로를 틀리게)·부분충격 잡 하나에서 매니페스트가 각각 있음/없음·이유로
  나오는지. REST 로 `path=output/return_manifest.json` 이 끝나기 전 404, 끝난 뒤 200 인지.

### C. 끝난 잡의 결과 폴더에 **후처리 잡을 거는** REST 경로를 주십시오

- **근거** 대시보드에 후처리·리포트 전용 잡 템플릿이 없고(§2), `/api/jobs/submit` 은 사용자 JWT 로 새 해석을 제출하는 경로입니다.
  부분충격은 지금 리포트가 안 생기고(pyKooCAE 쪽), 후처리가 실패한 잡은 리포트가 없는 채로 끝납니다.
- **왜** W-93 모양은 "DynaForge 후처리 연산이 클러스터에 후처리 잡을 건다" 입니다. 리포트가 이미 있으면 받기만 하면 되지만,
  **없거나 다시 돌릴 때** DynaForge 가 그 잡의 결과 폴더(`RESULT_DIR`)를 입력으로 후처리 잡(`KooChainRun postprocess --sphere|--impact`
  또는 리포트 sbatch 재제출)을 걸 길이 필요합니다. 명의는 제출 때 예약한 사람이라(W-93) 그 사람 권한 안에서 걸려야 합니다.
- **어떻게(제안)** 후처리 전용 템플릿(입력 = 원 잡 id, 자원 작게) + 원 잡 소유자 대조. 서비스 자격으로 부르면 대리 사용자를 함께 받아
  원 잡의 소유자와 같을 때만 허용. 잡 이름·결과는 원 잡 폴더 안(`output/`)에 쓰고 B 의 매니페스트를 갱신.
- **확인** 리포트 없는 잡에 후처리 잡을 걸면 `output/sphere_report.html`(또는 impact)이 생기고 매니페스트가 "있음" 으로 바뀌는지. 남의 잡에는 403.

### D. 드라이버 종료 상태가 후처리 실패를 말하게 해 주십시오

- **근거** post_exec 가 끝에 늘 `echo` 로 끝나 0 입니다(`smarttwin-fullangle-drop.yaml` 218-221).
- **왜** `slurm_job_results` 가 `COMPLETED 0:0` 을 보여 주면 사람도 에이전트도 성공으로 읽습니다.
- **어떻게** 적어도 B 의 매니페스트에 rc·이유를 남기고, 가능하면 잡 상태에도(비영 종료 등 — 방식은 §4).
- **확인** 후처리 실패 잡이 `slurm_job_results` 에서 실패로 보이는지(또는 매니페스트를 가리키는지).

### E. 카탈로그 기본 물성 문구를 실제와 맞춰 주십시오

- **근거** §2 마지막 줄. KMM 에는 단위계 키가 없어 값이 무변환으로 들어갑니다(W-91). 프리셋은 리포에 없고
  (`git ls-files` 0건) 클러스터 데이터입니다.
- **왜** 카탈로그만 믿은 제출은 "기본값이 tonne-mm 로 맞다" 고 오판해 물성을 안 넣고, 바닥판이 SI 값으로 돕니다.
- **어떻게** 프리셋이 고쳐질 때까지 문구를 "각도 프리셋의 바닥 물성은 SI(7850/2e11)로 들어 있다 — 물성을
  `simulation_params` 로 늘 명시하라" 로. 프리셋 정정은 클러스터 데이터 소유자에게, `smarttwin_mcp` 사본의 SI 기본값은
  정본(이 사본인지 SmartTwinMCP 리포인지)에서 고쳐 주십시오. 부분충격 쪽 이 리포 기본값(`server.py` 922-925,
  `smarttwin-partial-impact.yaml` 135-136)은 tonne-mm 로 맞습니다. 다만 그 템플릿 설명이 가리키는 pyKooCAE 예제(10행)는 SI 입니다.
- **확인** `smarttwin_scenario_options(fullangle_drop)` 문구와, `angle_preset` 을 주고 dry_run 했을 때의 최종 scenario 바닥 값이 서로
  어긋나지 않는지(프리셋·overrides·case_txt 가 모두 없으면 dry_run 은 scenario 를 출력하지 않습니다 — `server.py` 1073·1134-1136·1157-1161).

### F. (작게) 결과 폴더 안내를 실제 이름으로 해 주십시오

- **근거** §2 "결과 폴더 안내" 줄. **어떻게** 제출 응답에 이미 계산한 `result_dir`(1270)를 넣고 MCP 는 그 값을 그대로 안내.
- **왜** 포털 회수 절차는 잡 키(이름·id)로 찾습니다. 안내와 실제가 다르면 사람이 다른 폴더를 찾습니다.
- **확인** 빈 이름·한글 이름으로 제출했을 때 안내와 DB `result_dir` 가 같은지.

## 4. 우리가 **안 정한 것** — 이 리포가 정해 주십시오

- **매니페스트 경로·파일 이름·스키마 이름과 판번호.** 위는 제안입니다. 정해지면 DynaForge 연산이 그대로 따릅니다.
- **서비스 계정 신원 모델.** DynaForge 가 부를 때 ① 서비스 PAT + 대리 사용자 헤더(누구 잡인지 대조) ② 서비스 역할이 모든
  잡 읽기 ③ 사용자별 위임 토큰 — 어느 쪽이 대시보드 권한 모델(role·`kst_` PAT)에 맞는지. 리포트 명의는 DynaForge 가
  예약 원장으로 따로 정하므로(W-93), 여기서 풀 것은 "이 잡 파일을 읽어도 되는가"(A)와 "이 잡에 후처리 잡을 걸어도 되는가"(C) 둘입니다.
- **ssh 대체 길에서 같은 매니페스트를 보는 방식.** 같은 경로를 읽으면 되는지, 권한·마운트 차이로 따로 필요한 것이 있는지.
- **D 의 방식.** 비영 종료로 잡을 FAILED 로 둘지, 해석은 성공했으니 다른 표시(comment 등)로 둘지.
- **B 의 겹침.** 리포트 잡과 post_exec `postprocess --all` 중 누가 종합 리포트를 쓰는 정본인지. 둘 다 쓰면 sha256 이 흔들립니다.

## 5. 급한가

**A·B 가 먼저입니다.** DynaForge 후처리 연산은 아직 구현 전이고, 이 둘이 서야 결함에 기대지 않는 구현이 됩니다.
**C 는 그다음** — 평상시 경로(리포트 잡을 기다렸다 받기)는 A·B 로 서고, C 는 리포트가 없거나 다시 돌릴 때의 길입니다.
D·E·F 는 작고 독립적입니다. E 는 지금도 잘못된 물성으로 도는 잡을 만들 수 있어 문구만이라도 먼저 고치면 좋겠습니다.

---

### 참고 — 이 요청이 나온 경위

포털 절차에서 "실행해 두면 결과가 돌아온다" 를 펴 보다가, 자동은 `sphere_report.html` 생성까지이고 그 뒤는 사람이라는 것이
드러났습니다(W-92, 네 리포 반박 검증). 단위계는 W-91, 귀환 모양과 명의는 W-93 에 적었습니다.
**이미 되는 길이 있으면 알려 주십시오** — 예컨대 인증된 다른 파일 라우트나 완료 훅이 있다면 요청을 접고 그 길을 씁니다.

---

## 6. 회신 (2026-10-28) — A·B·C·D 반영, E·F 는 아직

결정 근거는 [result_return_20261028/context-notes.md](result_return_20261028/context-notes.md), 진행은 같은 폴더 checklist.md.
커밋은 로컬 main 에만 있고 **푸시·운영 배포 전**입니다.

| 부탁 | 커밋 | 들어간 것 |
|---|---|---|
| A | `f8552d8c` | `/api/jobs/<id>/…` 8개 라우트 토큰 필수 + 소유 검사, 구분자 있는 경로 검사, `path=stdout` 500 해소, 다운로드 버튼은 단기 티켓 |
| B·D | `0a8c9cca` | `output/return_manifest.json`, 리포트 잡 대기, 겹침 해소, 리포트가 없으면 드라이버 `exit 3` |
| C | `2e257262` | `POST /api/jobs/<id>/postprocess` |

### 6-1. DynaForge 가 쓸 계약

- **신원** — 예약한 사용자 본인의 `kst_` PAT 를 `Authorization: Bearer` 로 보냅니다(§4 ③). 서비스 PAT + 대리 사용자 헤더(①)는
  만들지 않았습니다. admin role PAT 는 모든 잡이 열리므로(②와 같은 효과) DynaForge 서비스 계정에 admin 을 주는 것은 권하지 않습니다.
- **소유 규칙** — admin 은 전부, 그 밖엔 `job_submissions.user_id == 호출자 username`. `user_id='anonymous'`(정제로 섞이는 키)와
  제출 기록이 없는 잡은 admin 만. 이름에 `[A-Za-z0-9._-]{1,32}` 밖의 글자가 있는 사용자는 결과가 `anonymous` 로 기록되므로 자기 잡도
  열리지 않습니다(fail-closed) — 그런 사용자가 있으면 알려 주십시오.
- **끝남 신호** — `GET /api/jobs/<id>/files/download?path=output/return_manifest.json` 이 404 면 아직, 200 이면 끝. 임시 파일 +
  `os.replace` 라 반쯤 쓴 파일은 보이지 않습니다. 드라이버가 prepare·submit 에서 일찍 죽어도 `stage: "early_exit"` 로 한 장 남습니다.
- **매니페스트** — `schema: "smarttwin.return_manifest"`, `version: 1`. 주요 키:
  `ok`(기대한 리포트가 모두 있나) · `stage`(`complete`|`early_exit`) · `driver_rc` ·
  `job{slurm_job_id, job_name, web_user, sim_type(fullangle_drop|partial_impact), result_dir, output_dir}` ·
  `postprocess{by(report_job|driver|postprocess_job|disabled), rc, report_job{id, state, exit_code}, postprocess_job_id}` ·
  `reports[{kind(sphere|impact), path(RESULT_DIR 기준), present, size, sha256, reason, log_tail{파일: 끝 20줄}}]`.
  있음/없음은 rc 가 아니라 **파일 유무**입니다. 리포트는 KooChainRun 과 같은 규칙으로 찾은 output_dir(`project.output_dir` →
  최상위 `output_dir`(부분충격, 예 `dwi_output`) → `<base_dir>/output`)에서 보며, `reports[].path` 는 그 실제 위치(결과 폴더 기준)입니다.
  매니페스트 자신은 언제나 `output/return_manifest.json` 입니다. `sphere_report.json` 등 JSON 은 v1 에 싣지 않습니다(필요하면
  `reports[]` 에 키를 더하는 식으로 v1 안에서 늘립니다).
- **후처리 잡(C)** — `POST /api/jobs/<원 잡 id>/postprocess`, 본문(모두 선택) `{"mode": "all|deep|sphere|impact", "cpus_per_task": 8,
  "mem": "32G", "time": "12:00:00"}`. 201 이면 `job_id`(후처리 잡)·`result_dir`·`manifest`. 제출 때 이전 매니페스트는
  `return_manifest.prev.json` 으로 옮겨지고, 후처리 잡이 끝나면 `postprocess.by="postprocess_job"`, `postprocess_job_id=<그 잡>` 으로
  다시 생깁니다. 남의 잡 403, 원 잡이나 같은 잡의 후처리 잡이 아직 큐에 있으면 409, KooChainRun 템플릿 잡이 아니면 400.
- **ssh 대체 길** — 같은 파일(`RESULT_DIR/output/return_manifest.json`)을 읽으면 됩니다(/data/single 은 NFS).

### 6-2. §4 의 나머지 결정

- **겹침** — KooChainRun submit 이 건 리포트 잡이 정본입니다. `submit.log` 에 `(Sphere|Impact) Job ID` 가 있으면 post_exec 는 그 잡을
  기다리기만 하고 `postprocess --all` 을 돌리지 않습니다. 리포트 잡이 없을 때(제출 실패)만 예전처럼 드라이버에서 돌립니다.
- **D** — 리포트를 기대했는데(CHAIN_POSTPROCESS=true 이고 scenario `postprocess.enabled`) 없으면 드라이버가 `exit 3` → `FAILED 3:0`.
  해석 산출물은 그대로 있고 까닭은 매니페스트에 있습니다.

### 6-3. 확인한 것과 못 한 것

- 확인 — 백엔드 테스트 34건(`dashboard/backend_5010/tests`, Flask 테스트 클라이언트·임시 DB). §3-A 의 401·403·`A_12`→`../A_123` 403·
  `path=stdout` 200, 티켓 만료·다른 잡·Bearer 전용 거부. 두 템플릿의 post_exec·EXIT trap 을 bash 로 돌려(KooChainRun·squeue·sacct 대역)
  있음 0·없음 3·리포트 잡 FAILED 이유·early_exit. C 가 만든 sbatch 스크립트를 bash 로 돌려 매니페스트가 다시 쓰이는 것. 프런트 `tsc --noEmit`.
- **못 한 것** — 실제 Slurm 에서의 성공 잡·후처리 실패 잡·부분충격 잡(§3-B 확인 항목). dev 박스라 운영 클러스터 재현은 배포 뒤에 해야 합니다.
- **운영 SSO** — SSO 꺼짐이면 미들웨어가 모든 요청을 admin 으로 넣으므로 A 의 검사는 SSO 켜짐에서만 의미가 있습니다.
- **동작 변화** — 남의 잡은 대시보드 로그 뷰어·`mcp_slurm` 읽기 도구에서도 403. 드라이버는 리포트 잡이 있으면 전 Run deep 을 다시
  돌리지 않으므로, inline deep 이 실패한 Run 의 재시도는 C(`mode: "all"`)로 합니다.
- **배포** — 백엔드 재시작, 그리고 두 템플릿을 `$SHARED_BASE/templates/official/simulation/` 에 반영해야 드라이버가 바뀝니다.
- E(카탈로그 물성 문구)·F(제출 응답 `result_dir`)는 이번 범위 밖입니다.
