<!-- stcx(icn401) SmartTwinMCP 운영 배포 요청(2026-10-14)에 대한 개발 측 회신 — 반영 내역·운영 절차 차이·질문 답 -->
# 회신 — stcx(icn401) SmartTwinMCP 운영 배포 요청 (DynaForge 전각도 낙하용)

회신일 2026-10-14 · 회신 KooSlurmInstallAutomationRefactory 개발 측 · 요청 koo.park@ax.samsung.com (2026-10-14)

> **요약** — §2(environment 잠금)와 §3(유닛 예시)은 코드에 반영했습니다. §1(운영 배포)은 저희 쪽에서
> icn401 에 접속할 수 없어 아래 절차로 부탁드립니다. 개통 범위(plat:smarttwin 전원)를 감안해 접근 통제를
> 더 넣었고(§2-2), 그 때문에 **운영 유닛에 env 한 줄**(`STMC_WORK_ROOTS`)이 필요합니다.
> `lstc_license_ip` 는 `dashboard_backend` 의 `LSTC_LICENSE_SERVER` 와 같은 값을 쓰면 됩니다(§4).

---

## 0. 전제 — 운영이 받을 커밋

아래 커밋은 아직 origin 에 올라가지 않았습니다(푸시 대기). 푸시해도 해시는 바뀌지 않으므로
1-1 에서는 운영 `$R` 에 **`5aa61b67` 이 들어 있는지** 보면 됩니다.

```bash
sudo -u koopark git -C $R fetch origin
sudo -u koopark git -C $R merge-base --is-ancestor 5aa61b67 origin/main && echo "포함"
```

| 커밋 | 내용 |
|---|---|
| `05240273` · `b6bb79dc` | §2 environment 잠금 + 덮어쓰기 문자열 안전 토큰 |
| `ac3c5d1d` | §3 유닛 예시 |
| `5aa61b67` | 접근 통제(§2-2) — fullangle·single drop 1.1.2, job_* 소유권, 옛 버전 위임 |

---

## 1. §1 배포 — 요청서와 다른 점만

요청서의 절대 조건(슬럼 무변경, `start_production.sh` 미사용, `mcp-slurm`·nginx 미변경)은 그대로입니다.

### 1-2. 사전 디렉터리·파일 — 추가 한 가지(선택)

DynaForge 경로(`smarttwin-fullangle-drop`)에는 필요 없습니다. 같은 MCP 의 나머지 도구(kmm_*·kam_*·remap_*·
post_*·scenario_*)도 쓰려면 템플릿 두 개를 백엔드 템플릿 폴더에 복사해 주십시오. 백엔드는 제출할 때마다
디스크에서 읽으므로 **재기동이 필요 없습니다**.

```bash
# SHARED_BASE 는 dashboard_backend 의 .env 값(기본 /shared)
cp $R/dashboard/templates/official/simulation/{smarttwin-tool,smarttwin-scenario}.yaml \
   ${SHARED_BASE:-/shared}/templates/official/simulation/
```

컴퓨트 노드에는 `/opt/apptainers/SmartTwinPreprocessor.sif`(전처리 도구)·`SmartTwinPostprocessor.sif`(후처리)가
있어야 합니다. 최신 전처리 SIF 는 v113(`SmartTwinPreprocessor_20261014_v113.tar.gz`)입니다.

### 1-3. 업로드 디렉터리 권한 — dev 에서도 같은 증상 재현

dev 에서 init 을 치면 `[Errno 13] Permission denied: '/shared/uploads'` 가 납니다. 백엔드가 업로드 아래에
`users/<사용자>/<종류>/` 를 만들어야 하는데 베이스가 root 소유라 못 만드는 것입니다. 운영도 같은 원인으로 보입니다.

```bash
sudo chown stcx:stcx /shared/uploads          # 대시보드 서비스 계정 소유로(root 소유 하위 폴더가 이미 있으면 -R)
```

확인(작은 파일, PAT 필요 — `127.0.0.1:5010`):

```bash
B=http://127.0.0.1:5010; F=/tmp/probe.k; printf '*KEYWORD\n*END\n' > $F
U=$(curl -s -X POST $B/api/v2/files/upload/init -H "Authorization: Bearer $PAT" -H 'Content-Type: application/json' \
      -d "{\"filename\":\"probe.k\",\"file_size\":$(stat -c %s $F)}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["upload_id"])')
curl -s -X POST $B/api/v2/files/upload/chunk -H "Authorization: Bearer $PAT" -F upload_id=$U -F chunk_index=0 -F chunk=@$F
curl -s -X POST $B/api/v2/files/upload/complete -H "Authorization: Bearer $PAT" -H 'Content-Type: application/json' \
     -d "{\"upload_id\":\"$U\"}"                  # → "file_path": "/shared/uploads/users/<사용자>/…/probe.k"
sudo -u koopark head -c 20 <그 file_path>       # MCP 서비스 계정(koopark)이 읽을 수 있어야 한다
```

🔴 **init 에 `job_id` 를 넣지 마십시오.** 넣으면 `/shared/uploads/jobs/<job_id>/…` 에 저장되는데, 이 경로는
사용자 영역이 아니라서 `fullangle_drop_simulation` 이 `model_file_path` 로 받지 않습니다(§2-2).

### 1-4. venv + 유닛 — 설치 뒤 drop-in 한 줄

설치 명령은 요청서 그대로입니다(`SERVICE_USER=koopark sudo -E ./install_offline.sh --install-service`).
설치 뒤 DynaForge 작업 루트를 허용하는 env 를 drop-in 으로 넣어 주십시오(생성된 유닛은 건드리지 않습니다).

```bash
sudo mkdir -p /etc/systemd/system/smarttwin-mcp.service.d
printf '[Service]\nEnvironment="STMC_WORK_ROOTS=/data/koopark/dynaforge/{user}"\n' \
  | sudo tee /etc/systemd/system/smarttwin-mcp.service.d/dynaforge.conf
sudo systemctl daemon-reload && sudo systemctl restart smarttwin-mcp
```

`{user}` 는 서버가 호출자(PAT 의 웹 사용자)로 바꿉니다. 그래서 DynaForge 의 `work_dir` 은
**`/data/koopark/dynaforge/<사용자>/<잡 id>`** 가 됩니다(작업 루트 1-5 의 아래). 기존 규칙
`/data/koopark/dynaforge/<잡 id>` 를 그대로 쓰려면 `{user}` 없이 `/data/koopark/dynaforge` 로 주면 되지만,
그 경우 같은 루트 안에서는 사용자끼리 폴더가 갈리지 않습니다. env 를 넣지 않으면 `work_dir` 은
`/data/single/<사용자>/…` 아래만 받습니다.

### 1-6. 확인 — 추가 두 줄

```bash
curl -s http://127.0.0.1:5013/api/v1/health          # {"ok":true,"server":"SmartTwinMCP","tools":164}
systemctl show smarttwin-mcp -p Environment | tr ' ' '\n' | grep STMC_WORK_ROOTS
```

`fullangle_drop_simulation` 드라이런은 이제 **PAT 가 있어야** 합니다(경로 검사에 호출자가 필요). REST 로 치면

```bash
curl -s -X POST http://127.0.0.1:5013/api/v1/tools/fullangle_drop_simulation/run \
  -H "Authorization: Bearer $PAT" -H 'Content-Type: application/json' \
  -d '{"args":{"work_dir":"/data/koopark/dynaforge/<사용자>/smoke","model_file_path":"<1-3 의 file_path>",
               "lstc_license_ip":"<§4 의 IP>","num_angles":4,"dry_run":true}}'
# → result.ok=true, result.scenario_path=…/smoke/scenario.json
```

---

## 2. §2 코드 — environment 잠금

### 2-1. 요청하신 것 — 반영

- 두 빌더가 `deep_merge` **전에** `environment`·`mode`·`model_file`·`output_dir`·`project_name` 을 걷어 내고,
  걷어 낸 키를 응답 `locked_overrides_dropped`·`locked_note` 에 적습니다(mcp_slurm 과 같은 집합).
- 요청하신 시험(`{"environment": {"solver_command": "touch /tmp/x"}}` → 써진 `scenario.json` 의 environment 가
  기본값 그대로)은 `tests/test_scenario_lock.py` 에 있습니다.
- 공용 빌더에서 걷어 내므로 **버전을 고정해 옛 버전을 불러도** 같이 막힙니다.
- 더 막은 것 — environment 중 `timeout_*` 정수 3개만 허용하고, 덮어쓰기 값의 문자열은 공백·셸 메타문자 없는
  토큰만 받습니다(일부 postprocess 값이 KooChainRun 셸 스크립트·`#SBATCH` 에 따옴표 없이 들어가기 때문).
  `sif_path_postprocessor` 는 `/opt/apptainers/*.sif` 만.

DynaForge 는 `extra_scenario_overrides` 를 보내지 않으므로 영향이 없습니다.

### 2-2. 추가 — 개통 범위 때문에 넣은 접근 통제 (DynaForge 확인 부탁)

HWAX 가 접근을 좁히지 않기로 해서, 서비스 계정(koopark) 권한으로 남의 잡이나 임의 경로를 다룰 수 있던
도구를 호출자 기준으로 묶었습니다. 인자 스키마는 바뀌지 않았습니다.

| 대상 | 바뀐 점 | DynaForge 영향 |
|---|---|---|
| `fullangle_drop_simulation`·`single_drop_simulation` (1.1.2, latest) | PAT 필수(드라이런 포함). `work_dir` 은 `/data/single/<사용자>/` 또는 `STMC_WORK_ROOTS` 아래만. `model_file_path` 는 `/data/single/<사용자>/`·`/shared/uploads/users/<사용자>/`·`/data/scenario` 안만. `model_file` 은 파일 이름만 | `work_dir` 규칙(1-4)과 업로드 init 의 `job_id` 미사용(1-3)만 맞추면 그대로 |
| `job_status` 등 job_* 전부·`get_job_details`·`my_jobs`·`batch_cancel_jobs` | PAT 호출자의 잡(잡 폴더가 `/data/single/<사용자>/` 안)만 | 제출한 사용자의 PAT 로 `job_status(registry_id)` 를 부르면 그대로 |
| 옛 버전(`version` 고정 호출) | backend 권한·감사나 새 검사를 건너뛰던 옛 버전은 최신 버전을 그대로 실행 | 없음(DynaForge 는 버전을 고정하지 않음) |

---

## 3. §3 유닛 예시 — 반영

`mcp-slurm.service.example` 의 `User=` 인라인 주석을 별도 줄로 옮기고, 두 예시의 `Wants=` 를
`dashboard_backend.service` 로 고쳤습니다. 이미 설치된 유닛은 바뀌지 않습니다(다시 설치할 때 반영).

---

## 4. 질문 — `lstc_license_ip` 를 `dashboard_backend` 의 `LSTC_LICENSE_SERVER` 와 같게 써도 되는가

**네, 같은 값이 맞습니다.** 두 값은 같은 자리로 갑니다.

- `fullangle_drop_simulation` 의 `lstc_license_ip` → scenario.json 의
  `environment.lsdyna_apptainer_env.LSTC_LICENSE_SERVER` → **컴퓨트 노드**의 LS-DYNA 컨테이너 env.
- 백엔드의 `LSTC_LICENSE_SERVER` → 백엔드가 직접 내는 LS-DYNA 잡 스크립트의
  `apptainer exec --env LSTC_LICENSE_SERVER=…` → 역시 **컴퓨트 노드**에서 읽힘.

주의 세 가지.

1. 도구 인자는 **IPv4 만** 받습니다. 유닛 값이 호스트 이름이거나 `port@host` 형식이면 IP 부분만 넘겨 주십시오.
2. `127.0.0.1`·`localhost` 는 안 됩니다 — 컴퓨트 노드에서는 그 노드 자신을 가리켜 LS-DYNA 가 라이선스를 못 찾습니다.
3. 컴퓨트 노드에서 그 IP 의 라이선스 포트(LSTC 기본 31010)가 열려 있어야 합니다.

---

## 5. 그 밖에 알려 드릴 것

- 개통하면 이 MCP 의 도구 164개가 모두 보입니다. 생성 도구(kmm_*·kam_*·remap_*·post_*·scenario_*)는 1-2 의
  템플릿이 없으면 제출 단계에서 "template not found" 로 끝납니다(드라이런은 됨).
- `list_recent_jobs` 는 관측용(`mode-read-all`)이라 모든 사용자의 잡 목록(이름·경로)을 보여 줍니다. 개통 범위를
  감안해 막을지 정해 주시면 반영하겠습니다.
- MCP `/mcp` 엔드포인트 자체는 PAT 를 검사하지 않습니다. 잡을 내거나 다루는 도구(낙하·생성 도구·job_*)는 위처럼
  각자 PAT 를 확인하지만, 카탈로그 검색·설명과 일부 관측 도구(`audit_*`·`list_recent_jobs`·클러스터 상태 등)는
  PAT 없이 됩니다. 1차 관문은 게이트웨이(Teleport 터널)입니다.
