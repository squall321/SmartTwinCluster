# 해석기 없는 dev E2E — C 후처리 잡 → DynaForge 후처리 예약·반입

**읽는 사람** 이 시험을 함께 돌리는 세션들 — 포털(hwaxportal-a5, VM 담당), KooRemapper(kooremapper-fd, DynaForge 반입 쪽 — 포털 11-12), KooSlurm(이 문서).
**결정** 사용자 11-12 — 해석기 없이 이미 있는 결과 사본으로 한 번 돈다. 노드 VM 은 포털이 켠다(승인은 포털 세션에서 받았다).
**모양** LS-DYNA 를 돌리지 않는다. 결과 사본에 C(`POST /api/jobs/<id>/postprocess`)를 걸어 노드에서 sphere 리포트를 다시 만들고,
DynaForge 후처리 예약이 위임 창구로 토큰을 받아 귀환 매니페스트를 읽고 리포트(·온톨로지 꾸러미)를 반입하는 데까지.

## 0. 준비 — 끝난 것(KooSlurm, 11-12)

| 무엇 | 상태 |
|---|---|
| 공유 비밀 파일 | `/home/koopark/.config/smarttwin/dev_kooslurm_sso_secret`(600, 디렉터리 700). 값은 메시지에 싣지 않는다 — 양쪽이 이 파일을 읽는다 |
| dev 백엔드(:5010) | `dashboard/backend_5010/.env` 에 `HEAX_GATEWAY_SECRET`(위 파일 값), `.env` 를 600 으로, `systemctl restart dashboard_backend` — `/api/auth/sso/verify` 맞음 204·틀림 401 확인 |
| 결과 사본 | `/data/single/e2etest/E2E_drop_9000001` ← `RRVerify_ok_828`(verify_drop2_828 사본, 26 Run, deep 리포트 52개). d3plot 702개는 하드링크(sphere 는 읽기만), 텍스트의 경로를 사본으로 바꿈, 원본을 가리키는 심링크 지움, 매니페스트·리포트는 지워 둠 |
| 시험 잡 기록 | dev DB(`/home/koopark/web_services/backend/dashboard.db`) `job_submissions` id 67 — `job_id=9000001`, `template_id=smarttwin-fullangle-drop`, `user_id=e2etest`, `result_dir`=위 사본. Slurm 에 없는 번호(현재 최대 1223) |
| 노드 이미지 기대값 | 헤드는 이미 Pre v136 `1c973c25…`·Post v51 `32997e9b…` — [image_check.md](image_check.md) |

## 1. 준비 — DynaForge 쪽(kooremapper-fd)

```bash
# P = KooRemapper/platform
printf '\nKOORM_STCX_BACKEND_URL=http://127.0.0.1:5010\nKOORM_KOOSLURM_SSO_SECRET=%s\nKOORM_STCX_POLL_MIN_SEC=10\n' \
       "$(cat /home/koopark/.config/smarttwin/dev_kooslurm_sso_secret)" >> $P/.env
$P/infra/scripts/restart-api-only.sh && curl -s :8700/api/health
```

- 시험 사용자 이메일은 **`e2etest@<아무 도메인>`** — KooSlurm 위임 창구가 `@` 앞부분 `e2etest` 를 사용자 이름으로 쓰고, 시험 잡 기록의 `user_id` 와 같다.
  DynaForge 시드 admin(`admin@…`)은 위임 창구가 거절한다(400).
- 그 사용자로 로그인(`POST /api/auth/signup` 또는 DynaForge `/api/auth/sso`)하고 세션을 하나 만든다.

## 2. VM 켠 뒤(포털이 node001 을 켠다)

```bash
sinfo -n node001 -h -o %T                       # → idle
grep MemAvailable /proc/meminfo                  # 30GB 이상 유지(earlyoom) — 띄우는 노드는 node001 하나
```

**노드 이미지 맞추기 — 11-12 에 끝남(다음엔 건너뛴다).** node001 `/opt/apptainers` 에 Pre v136(1,615,892,480 B, 7초)·
Post v51(1,156,505,600 B, 4초). 노드 홈(vda2, `/opt` 와 같은 파일시스템)에 `.part` 로 올린 뒤 `sudo mv` 로 원자 교체했다 —
node001 은 `/tmp` 가 별도 파일시스템(vda3)이다. **`deploy_apptainers.sh --image` 는 쓰지 않았다**: 헤드 사본을 비교 없이
`sudo cp` 로 제자리에서 덮어(L609-612) 쓰는 중이면 squashfs 가 깨질 수 있고, 헤드는 이미 같은 판이었다. 다시 돌릴 때는 아래 확인 한 줄만.
아래 명령은 참고로 남긴다(헤드 덮어쓰기 위험 — 1번 노드 배포 안전이 고치기 전에는 쓰지 말 것).

```bash
cd $R && echo node001 > /tmp/e2e_nodes.txt
./deploy_apptainers.sh --config my_multihead_cluster_2.yaml --nodes-file /tmp/e2e_nodes.txt --image SmartTwinPreprocessor.sif
./deploy_apptainers.sh --config my_multihead_cluster_2.yaml --nodes-file /tmp/e2e_nodes.txt --image SmartTwinPostprocessor.sif
NODES=node001 EXPECT_PRE_SHA=1c973c25 EXPECT_POST_SHA=32997e9b bash cluster/utils/image_version_check.sh   # 노드 두 줄 OK
```

> **11-12 실행 기록** — ① 까지 하고 멈췄다(사용자 결정 「멈추고 VM 끄기」). node001 을 켠 뒤 호스트 MemAvailable 이 30.7 → 28.5 GiB 로
> 내려갔다 — 이미지 2.7 GB 를 받는 동안 VM(qemu) RSS 가 3.9 GiB 로 늘었고 게스트가 비워도 호스트로 돌아오지 않는다. ②·③ 은 VM 을
> 최대 8 GiB 까지 키울 수 있어 「가용 30 GB 이상」 조건을 지킬 수 없었다. **다시 돌릴 때는 호스트 여유 메모리를 넉넉히(VM 최대 8 GiB 를 더해도
> 30 GiB 이상) 확보한 뒤 사용자에게 다시 묻는다.** 결과 사본·시험 잡 9000001·비밀 파일·node001 의 v136/v51 은 그대로 남아 있다.

## 3. C — 결과 사본에 후처리 잡

dev 는 SSO 꺼짐이라 토큰 없이 admin 으로 통과한다. node001 자원(2 CPU · 4096 MB)에 맞춘다.

```bash
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"mode":"sphere","cpus_per_task":2,"mem":"3500M","time":"01:00:00"}' \
     http://127.0.0.1:5010/api/jobs/9000001/postprocess          # → 201 {"job_id": "<pp>", ...}
squeue -n pp_9000001                                               # RUNNING node001 → 사라짐(10-28 에는 62초)
sacct -n -P -X --name=pp_9000001 --format=JobID,State,ExitCode     # COMPLETED|0:0
python3 -m json.tool /data/single/e2etest/E2E_drop_9000001/output/return_manifest.json | head -40
```

기대: `ok:true`, `postprocess.by:"postprocess_job"`, `reports[0].present:true` · `size`·`sha256`, `reports[0].ontology` 칸이 있다
(Post v51 이 꾸러미를 쓰면 `present:true`, 아니면 `false` — 둘 다 시험은 이어간다).

**예약은 이 매니페스트가 생긴 뒤에 건다.** 사본에는 이전 매니페스트가 없어 C 도중에는 `.prev` 가 없다 — 그때 예약하면 DynaForge 가
「끝났는데 매니페스트 없음」으로 2분 뒤 닫는다.

## 4. DynaForge 후처리 예약(kooremapper-fd)

```bash
curl -s -X POST -H "Authorization: Bearer <e2etest 의 토큰>" -H 'Content-Type: application/json' \
     -d '{"operation":"postprocess","args":{"job_key":"stcx:9000001","sim_type":"fullangle_drop","job_name":"E2E_drop"}}' \
     :8700/api/sessions/<sid>/jobs                                 # → 201 data.id
curl -s -H "Authorization: Bearer <토큰>" :8700/api/jobs/<id>      # succeeded 까지(스캔 15초)
curl -s -H "Authorization: Bearer <토큰>" :8700/api/jobs/<id>/diagnostics   # external_ref
```

| 볼 것 | 기대 |
|---|---|
| 잡 상태 | `succeeded`, `resolved_cmd.report_ids[0]` |
| `external_ref.cluster_user` | `e2etest`(KooSlurm 위임 창구가 돌려준 이름) |
| `external_ref.manifest` | `postprocess_by:"postprocess_job"`, `postprocess_job_id:"<pp>"` |
| `external_ref.ontology.state` | 꾸러미가 있으면 `loaded`, 없으면 `absent` |
| 리포트 | `external_job_key:"stcx:9000001"`, `reservation` 이 붙어 있다 |
| KooSlurm 쪽 | `audit_log` 에 `token.delegate`(행위자 `delegate:dynaforge`, 대상 `e2etest`), 'MCP 토큰' 목록(e2etest)에 `위임: dynaforge` |

## 5. 끝나면

- **VM 끄기**(포털) — `virsh shutdown node001`.
- 다시 돌릴 때: DynaForge 는 같은 `job_key` 를 「이미 반입」으로 끝낸다 — 그 리포트를 지우거나(`DELETE /api/reports/<rid>`) 다른 잡 번호로.
- 시험 잡 기록 지우기(원하면): `python3 -I -c "import sqlite3;c=sqlite3.connect('/home/koopark/web_services/backend/dashboard.db');c.execute(\"DELETE FROM job_submissions WHERE job_id IN ('9000001')\");c.commit()"`
  — 후처리 잡도 같은 사용자 명의로 기록되니 `pp` 번호도 함께.
- 사본(`/data/single/e2etest/E2E_drop_9000001`)은 지워도 원본에 영향이 없다(d3plot 은 하드링크).
- dev 백엔드의 위임 비밀은 남겨 둔다 — 지우려면 `.env` 의 `HEAX_GATEWAY_SECRET` 줄을 빼고 재시작.

## 이 시험이 보지 않는 것

- SSO 켜짐의 소유 검사 — dev 를 켜면 같은 박스의 다른 세션(MCP 등)이 깨진다. 소유 검사는 백엔드 시험(45건)이 SSO 켜짐으로 본다.
- 드라이버(B) 끝단 — 해석기가 필요하다.
- 옛 결과 셸: 사본의 `sphere_report.sh` 는 7월 prepare 판이다 — 10-26 sphere 개선이 들어간 셸이 아니다(C 의 알려진 한계).
