<!-- smarttwin_mcp 스테이징 컷오버 + 오프라인(24.04/py3.12) 배포 체크리스트 -->
# smarttwin_mcp 배포 체크리스트

목표. (1) 이 박스(22.04, staging)에 smarttwin_mcp 를 systemd 서비스로 세우고 nginx `/mcp` 를
mcp-slurm(:5012) → smarttwin_mcp(:5013) 로 컷오버(구버전 즉시 폴백 유지). (2) 운영 icn401
(오프라인, Ubuntu 24.04, Python 3.12+) 배포용 오프라인 휠 + 런북 준비.

## A. 스테이징 컷오버 (이 박스, py3.12) — ✅ 완료·검증(2026-07-17)
- [x] A1. py3.12 venv 구축 `dashboard/smarttwin_mcp/.venv` — fastmcp==3.3.1 핀 + 벤더링 패키지 설치.
      검증: venv python=3.12.12, fastmcp 3.3.1, `import smarttwin_mcp.server` OK. system py3.12 엔 fastmcp
      없음 → 서비스가 venv 격리 사용 확인.
- [x] A2. systemd 유닛 `smarttwin-mcp.service` 설치(mcp-slurm.service 미러) — 127.0.0.1:5013 loopback,
      STMC_CLUSTER_URL=http://127.0.0.1:5010, STMC_JOBS_DB/STMC_AUDIT_DB=/data/SmartTwinMCP/*.db.
      검증: 수동 :5013 종료 후 서비스(MainPID)가 5013 점유, active/enabled, /mcp initialize 200.
- [x] A3. nginx `/mcp` 컷오버 5012→5013 (proxy_pass + Host, 백업 .bak.<ts>). mcp-slurm.service 계속 가동(폴백).
      검증(nginx 443 경유): initialize 200(serverInfo SmartTwinMCP 3.3.1), 인증 read(get_cluster_health→
      backend, PAT 패스스루) ok/mode=production/5파티션, write-path dry_run(→/api/jobs/preview) ok/200,
      네이티브 registry read(job_status reg14) ok. → 라우팅+auth+read+write 전부 라이브 확인.
- [x] A4. 롤백 = deploy/nginx-mcp.snippet.conf 참조. /mcp 의 5013 두 곳 → 5012 + `nginx -s reload`.
      mcp-slurm.service(:5012) active/enabled 유지되어 즉시 복구 가능(무중단).

## B. 오프라인 휠 + 운영 런북 (icn401 = 24.04 / py3.12 / cp312)
- [ ] B1. fastmcp==3.3.1 + 전 의존성 폐포를 cp312 manylinux 휠로 수집 →
      offline_packages_2404/python_wheels/python3.12/smarttwin_mcp/
- [ ] B2. requirements.lock(정확한 버전 핀) 생성
- [ ] B3. 신규 py3.12 venv 에 `--no-index --find-links` 로 설치 재현(오프라인 모의) → 성공해야 함
- [ ] B4. RUNBOOK.md — icn401 오프라인 배포 절차(apt install python3.12-venv[offline_packages_2404],
      venv, pip --no-index, 유닛 설치, nginx flip, /data 동기화, 폴백)

## 절대 규칙(재확인)
- mcp-slurm.service 는 컷오버 후에도 **살려둔다**(폴백). 검증 전 삭제/중지 금지.
- 운영(icn401)은 별도 머신. 이 체크리스트 A 는 staging(이 박스)만. 운영 반영은 B + 사용자 승인 후.
- apt 는 apt install(offline_packages_2404), Python 은 3.12+.
