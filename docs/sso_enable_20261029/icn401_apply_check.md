# icn401 적용 확인 — 결과 귀환(A·B·C)·위임 창구·화면 수정

**읽는 사람** icn401(운영 헤드)에서 반영을 돌리는 운영자, 그리고 이 내용을 cae00 점검 문서로 옮길 포털 세션.
**반영 대상** origin/main `3f72f4c6` 까지 — 결과 귀환(`f8552d8c`·`0a8c9cca`·`2e257262`·`c41d927e`·`5eb8567e`),
화면 JWT(`f267c127`), 위임 창구(`33bd0da1`·`0eecaea9`).
**모든 명령은 icn401 헤드에서**, 리포 루트(`$R`, 예 `/home/koopark/claude/KooSlurmInstallAutomationRefactory`)를 기준으로 한다.

## 1. 반영

```bash
cd $R && git pull && sudo ./dashboard/start_production.sh 2>&1 | tee /tmp/start_production_$(date +%m%d_%H%M).log
```

## 2. 확인 — 명령과 기대값

| # | 무엇 | 명령 | 기대값 |
|---|---|---|---|
| 1 | 코드 판 | `git -C $R merge-base --is-ancestor 3f72f4c6 HEAD && echo 포함` | `포함` |
| 2 | 템플릿 동기화 | `grep -n '템플릿 동기화' /tmp/start_production_*.log \| tail -1` | `✓ 템플릿 동기화: N개 → /shared/templates/official/` |
| 3 | 드라이버 템플릿이 새 판인가 | `grep -c write_return_manifest /shared/templates/official/simulation/smarttwin-{fullangle-drop,partial-impact}.yaml` | 두 파일 모두 `3`(주석 1 + EXIT trap 1 + post_exec 1) |
| 4 | 라이선스 IP 주입 | `grep -c 'LSTC_LICENSE_SERVER%' /shared/templates/official/simulation/smarttwin-partial-impact.yaml` | `0` |
| 5 | SSO 표시 줄 | `grep -n '→ SSO=' /tmp/start_production_*.log \| tail -1` | 지금은 `→ SSO=false → 정본 conf: hpc-portal.conf` |
| 6 | 프런트 재빌드 | `grep -n 'frontend_3010' /tmp/start_production_*.log \| head -3` | `frontend_3010: 빌드 필요 (소스 변경 감지)` 뒤 빌드 성공 |
| 7 | 백엔드 기동 | `systemctl is-active dashboard_backend` | `active` |
| 8 | C 라우트가 새 코드인가 | `curl -s -w ' %{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:5010/api/jobs/abc/postprocess` | 끝이 `400`, 본문에 `"error_code":9001`(잡 id 형식 거절 — 옛 코드면 404) |
| 9 | 다운로드 티켓 라우트 | `curl -s -X POST http://127.0.0.1:5010/api/jobs/1/files/download-ticket \| head -c 80` | SSO 꺼짐이라 `{"expires_in":120,...,"ticket":"eyJ…` (켜짐이면 토큰 없이 401) |
| 10 | 위임 창구 — 비밀 넣기 전 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:5010/api/auth/sso/verify` | `404`(구성 없음) |

## 3. 위임 창구 열기(공유 비밀)

DynaForge 의 `KOORM_KOOSLURM_SSO_SECRET` 과 **같은 값**을 백엔드 env 파일에 넣는다(git 에 넣지 않는다).
게이트웨이 쪽 비밀은 포털이 사람별 위임을 다시 할 때 넣는다(지금은 보류).

```bash
ENVF=$R/dashboard/backend_5010/.env
grep -q '^HEAX_GATEWAY_SECRET=' $ENVF || printf '\nHEAX_GATEWAY_SECRET=%s\n' '<비밀>' >> $ENVF
chmod 600 $ENVF && sudo systemctl restart dashboard_backend
```

| # | 명령 | 기대값 |
|---|---|---|
| 11 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'X-Heax-Gateway-Secret: <비밀>' http://127.0.0.1:5010/api/auth/sso/verify` | `204` |
| 12 | 같은 명령, 틀린 비밀 | `401` |
| 13 | `curl -s -X POST -H 'X-Heax-Gateway-Secret: <비밀>' -H 'X-Hwax-Delegate-Email: <본인 이메일>' -H 'X-Heax-Client: dynaforge' http://127.0.0.1:5010/api/auth/sso` | `{"access_token":"kst_…","expires_in":3600,"username":"<이메일 @ 앞부분>",…}` |
| 14 | 대시보드 'MCP 토큰' 화면 | 13 의 사용자로 로그인하면 `위임: dynaforge` 가 보인다(SSO 꺼짐이면 화면 사용자는 admin 이라 안 보인다 — SSO 켠 뒤 확인) |

## 4. 운영 첫 실제 전각도 잡 — 귀환 매니페스트(B·D)

전각도 잡이 끝나면(드라이버가 리포트 잡을 기다린 뒤) 결과 폴더에 `output/return_manifest.json` 이 생긴다.

```bash
J=<드라이버 잡 id>
DB="${DATABASE_PATH:-/home/koopark/web_services/backend/dashboard.db}"   # backend_5010/.env 의 DATABASE_PATH
RD=$(python3 -c "import sqlite3,sys;r=sqlite3.connect(sys.argv[1]).execute(\"SELECT result_dir FROM job_submissions WHERE job_id=? ORDER BY id DESC LIMIT 1\",(sys.argv[2],)).fetchone();print(r[0] if r else '')" "$DB" "$J")
sacct -j $J -X -n -P --format=State,ExitCode
tail -15 /shared/logs/$J.out
python3 -m json.tool $RD/output/return_manifest.json | head -40
```

| 볼 것 | 정상 | 리포트가 없을 때 |
|---|---|---|
| `sacct` | `COMPLETED\|0:0` | `FAILED\|3:0` |
| 드라이버 로그 끝 | `=== 귀환 매니페스트 ===` 다음 `[return_manifest] … ok=True` | `ok=False missing=sphere` 와 `리포트 없음 — 드라이버를 rc=3 로 끝낸다` |
| 매니페스트 `stage`·`ok` | `complete`·`true` | `complete`·`false` |
| `postprocess.by`·`report_job` | `report_job`·`{id, state:"COMPLETED", exit_code:"0:0"}` | `report_job` 이면 그 잡의 state, 리포트 잡이 없었으면 `driver` |
| `reports[0]` | `present:true`, `size`, `sha256`(= `sha256sum $RD/output/sphere_report.html`) | `present:false`, `reason`, `log_tail` |

리포트가 없으면 C 로 다시 건다(잡 소유자의 토큰, SSO 꺼짐이면 토큰 없이도 admin):

```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"mode":"sphere"}' http://127.0.0.1:5010/api/jobs/$J/postprocess
```

201 이면 매니페스트가 `return_manifest.prev.json` 으로 옮겨지고, 후처리 잡이 끝나면 `postprocess.by:"postprocess_job"` 으로 다시 생긴다.
부분충격 잡은 같은 방법에 `impact`(리포트 경로는 runner_config 의 output_dir 기준 — 매니페스트 `reports[0].path` 를 본다).

알려진 한계: C 는 prepare 때 만든 리포트 셸을 돌린다 — 이번 판 전에 prepare 한 옛 결과에는 10-26 sphere 개선·JSON 이 없다.
