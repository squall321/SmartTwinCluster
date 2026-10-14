<!-- SmartTwin MCP+REST 커버리지 작업의 결정과 근거 — 계속 추가 -->
# 컨텍스트 노트

## 2026-10-13 착수
- 요청: "smarttwinmcp(5013) 개발을 마저 — SmartTwinPreprocessor·Postprocessor 의 모든 커버리지가 MCP 로" +
  "REST API 로도".
- 재부팅이 있었다(커널 5.15.0-191→198) — /tmp 가 비워져 deploy 노드 파일이 사라졌다. 노드 목록은
  스크래치패드에 둔다. LSTC 서버는 재부팅 후 떠 있었다.
- 기준선: lint 0 error/1 warning(submit_job L070), pytest 46 pass/2 fail(기존 결함). 서비스 venv 에 pytest 가
  없어 시험은 업스트림 `/home/koopark/claude/SmartTwinMCP/.venv`(py3.10, fastmcp 3.3.1)로 돌린다.

## 결정
- **도구는 정본에서 생성.** 손으로 120개를 쓰면 다음 기능 추가 때 바로 어긋난다. 정본 4종(KMM·KAM·KCR
  help 카탈로그, kooremapper_core)과 후처리 argparse 를 생성기가 읽는다. 생성물은 커밋한다 — 운영 머신에는
  pyKooCAE·KooRemapper 소스가 없다.
- **계산은 Slurm 잡(backend 경유).** 헤드에서 KMM/후처리를 돌리면 대형 모델에서 메모리·시간이 터지고,
  권한·감사도 우회한다. 기존 규약((C) 하이브리드: 쓰기는 backend)과 같다.
- **범용 템플릿 하나 + 화이트리스트.** backend 는 template_id·files·slurm_overrides(값 검사)·job_name 만
  받는다(env 를 사용자에게서 받지 않는다). 그래서 실행할 도구는 업로드 파일(request.json)로 전달하고 템플릿이
  고정 목록에서만 고른다. argv 는 배열로 실행해 셸 해석이 없다.
- **경로 허용 루트**: 입력·작업 폴더는 `/data/single/<웹사용자>/` 와 `/data/<웹사용자>/`(있으면) 아래만.
  MCP 서버는 koopark 로 돌기 때문에 검사 없이 경로를 받으면 남의 파일을 읽어 올릴 수 있다. 웹사용자는
  backend `/api/me` 로 얻는다. 템플릿에서도 `$WEB_USER`(backend 가 JWT 로 설정)로 다시 검사한다.
- **REST 는 같은 서버(:5013)의 custom route.** 같은 검증·실행 함수를 부르므로 MCP 와 어긋날 수 없다.
  backend_5010 에 따로 만들면 로직이 둘이 된다. nginx 접두는 `/smarttwin-api/` — `/mcp` 는 접두 일치라
  `/mcp…` 로 시작하는 이름은 피했다.
- **kooremapper_core 는 벤더링**(tools/_shared). 운영에 KooRemapper 리포가 없다. 원본과 같은지 시험한다.
- **search 한글 토큰**: 정규식이 [a-z0-9_] 뿐이라 한글 설명이 검색에 안 걸린다. 카탈로그 설명이 한글이라 필요.

## 기존 결함(발견, 범위 밖 — 기록만)
- MCP 의 네이티브 읽기 도구(job_status·audit_* 등)는 PAT 를 검사하지 않는다. nginx `/mcp` 도 인증이 없다.
  → REST 는 PAT 필수로 만들고, MCP 쪽 게이트는 별건으로 사용자에게 알린다.

## 2026-10-13~14 진행
- **e2e 가 실제 KMM 결함을 잡았다.** kmm_chain(ELASTIC_TO_RIGID *PIDExcept → TRANSFORM)이 rc=0 으로 끝났는데
  출력에 MAT 카드가 하나도 없었다. ExchangetoRigid 가 재질 표를 강체 사본으로 통째로 바꿔 제외 파트 재질이
  사라지고, 제외 파트와 MID 를 같이 쓰는 파트는 둘 다 잃었다. pyKooCAE 7711e10 으로 고쳤다(빌드 대기).
  교훈: e2e 판정은 rc·파일 존재가 아니라 의미(MID 참조가 모두 정의됐는가)로 한다.
- **시나리오 드라이버 교착.** 단일 노드 dev(2 CPU·4G)에서 드라이버 4G + 자식 `--mem=0`(노드 전체)이면 자식이
  못 들어간다. 드라이버 1G 기본 + `driver_mem` 인자, 자식 CPU 는 scenario environment.ncpu 로.
- **LS-DYNA 는 dev 라이선스 만료**("Program license has expired"). 코드 문제가 아니다. KooChainRun diagnose 가
  [라이선스 에러]로 분류하는 것까지 확인했다.
- **보안 관찰(범위 밖, 사용자에게 보고)**: dev 의 LSTC 서버가 0.0.0.0:31010 으로 열려 있고 LSTC 로그에 외부
  IP(45.133.173.173, 85.217.149.10)의 접속 시도가 있다.

## 결정 (후속 도구)
- **tool_result 는 direct.** 생성 도구 116종의 응답이 전부 `tool_result(job_id=…)` 를 가리킨다. catalog 전용이면
  약한 LLM 이 결과를 못 찾는다.
- **소유권은 경로로.** registry 의 user 열은 MCP 서비스 계정(koopark)이라 쓸 수 없다. 잡 폴더가
  `/data/single/<호출자>/` 안인지로 판단한다(backend RESULT_DIR 규칙과 같다). 큐 대기 잡은 폴더가 아직 없으므로
  registry 로 찾은 경우 상위 폴더만 확인한다.
- **reprioritize apply 는 admin 전용 + release_held 동봉.** 네이티브 apply 는 top(공유 계정이면 다른 웹사용자
  잡과의 순서까지 바꿈) + 먼 잡 hold(해제 경로 없음 → 자식이 영영 안 돌아 드라이버가 끝나지 않음). dev 는
  enable_user_top 이 없고 koopark 이 운영자가 아니라 top 은 실패하고 hold 만 걸린다. 그래서 계획은 누구나,
  적용은 admin, 해제는 소유자.
- **jobs.json 은 믿지 않는다.** 사용자 폴더에 있어 고칠 수 있다(예: post_* 의 output 을 jobs.json 으로). scontrol
  전에 큐에 있는 잡의 배치 스크립트(`squeue %o`, 상대경로로 내도 절대경로로 나옴)가 캠페인 폴더 안인지 보고,
  하나라도 밖이면 전체를 거절한다. Slurm 잡 ID 는 이 클러스터에서 재사용된 적이 있다(3월의 1188~1190) —
  registry 의 job_id 조회는 최신 행이 이긴다.
- **harvest 출력 경로는 고정**(캠페인 폴더 risk_<kind>.json). 임의 경로를 받으면 캠페인 파일을 덮어쓸 수 있다.

## 2026-10-14 개통 전 접근 통제
- **발견**: 손작성 낙하 도구(fullangle·single)가 work_dir·model_file·model_file_path 를 검사 없이 서비스 계정
  권한으로 썼고, job_* 는 registry_id 만 맞으면 누구의 잡이든 다뤘다. 옛 버전 일부는 version 을 고정하면
  backend 권한·감사를 건너뛰고 서비스 계정으로 sbatch/scancel 을 직접 불렀다. HWAX 가 접근을 좁히지 않기로 해서
  개통 전에 막아야 했다.
- **결정(사용자)**: ① 허용 루트로 묶기 — work_dir 은 /data/single/<호출자> + STMC_WORK_ROOTS({user} 치환),
  운영은 drop-in 으로 DynaForge 루트를 준다. ② job_* 소유권을 이번에. ③ 옛 버전은 최신으로 위임.
- **admin 예외 없음**: dev 는 SSO 꺼짐이라 모든 웹 사용자가 admin 으로 보인다. 규칙을 "잡 폴더가 호출자 영역 안"
  하나로 둔다(남의 잡 지원은 대시보드·셸로).
- **소유권 검사는 공용 함수에.** 모든 버전의 job_* 가 resolve_job 을 지나므로 한 곳만 고치면 핀 우회가 없다.
  낙하 도구는 경로 처리가 버전별 스크립트에 있어서 옛 버전을 고정 버전(1.1.2) 실행으로 바꿨다(최신 심링크가
  아니라 고정 — 뒤에 스키마가 바뀌어도 옛 인자로 깨지지 않게).
- **업로드 init 의 job_id** 를 주면 /shared/uploads/jobs/<id>/ 에 저장돼 사용자 영역이 아니다 — 입력 루트에
  넣지 않고 회신에 "job_id 없이"로 안내했다(넣으면 사용자 간 경계가 없어진다).
- dev 업로드도 운영 1-3 과 같은 이유로 실패한다(/shared → /mnt/gluster root 755, uploads 없음). 바꾸지 않았다.
- KooRemapper 원본 catalog_data.json 이 앞서 나가 벤더링 시험이 깨졌다 — 바뀐 것은 외부 op stcx_fullangle_drop
  뿐(도구 대상 아님)이라 재벤더링만 했다(206f9489). KooRemapper 리포 최신 커밋이 "stcx→SmartTwinMCP 설계"
  문서다 — 다른 세션이 같은 주제를 보고 있으니 그쪽 설계와 회신 내용이 어긋나지 않는지 사용자 확인 필요.

