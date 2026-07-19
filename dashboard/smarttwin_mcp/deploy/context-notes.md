<!-- 배포 중 내린 결정과 근거 기록 — 계속 추가 -->
# smarttwin_mcp 배포 컨텍스트 노트

## 환경 사실(2026-07-17 확인)
- 이 박스 = **Ubuntu 22.04(jammy), staging**. 단 python3.12(3.12.12) 사용 가능(3.10/3.11/3.13 도 있음).
- 운영 icn401 = **Ubuntu 24.04, 오프라인, Python 3.12+ 필수**(사용자 지시).
- 업스트림 :5013 dev 서버 = `/home/koopark/claude/SmartTwinMCP/.venv`(py3.10, fastmcp 3.3.1) 를 빌려 씀.
  → 벤더링본 전용 venv 없음. 운영은 이 경로 의존 불가 → 새 venv 필요.
- offline_packages_2404/python_wheels/{python3.12,python3.13} 체계 이미 존재. fastmcp 는 아직 없음(추가 대상).
- /data/SmartTwinPreprocessor/bin/{auto_tune.py,chain_autotune.py} **이미 배포됨**(7/16). 템플릿 동기화는 별도 확인.

## 결정
- **staging venv = python3.12** 로 짓는다(운영 기준 일치, 이 박스에 3.12 있음). 22.04지만 3.12 이므로 faithful.
- **fastmcp==3.3.1 핀**. 이유: :5013 에서 실검증된 버전. 느슨한 `>=0.2.0` 대신 재현성 위해 고정.
- 서비스 실행형태 = mcp-slurm 과 **다름**. mcp-slurm 은 `python server.py`(WorkingDirectory=mcp_slurm).
  smarttwin_mcp 는 `python -m smarttwin_mcp.server serve --transport streamable-http --host 127.0.0.1
  --port 5013 --tools-root <abs>/tools`, PYTHONPATH=src.
- 포트 = **5013 loopback**(mcp-slurm 5012 와 분리). nginx `/mcp` 만 5013 으로 돌려 컷오버.
  mcp-slurm.service 는 계속 가동 → 롤백 = nginx proxy_pass/Host 5013→5012 + reload(1줄).
- DB env = STMC_JOBS_DB/STMC_AUDIT_DB=/data/SmartTwinMCP/*.db (registry/audit 가 여기 씀). 유닛에 명시.
- nginx Host 헤더 = FastMCP DNS-rebinding 보호 때문에 loopback 으로 세팅해야 함(기존 5012 블록과 동일 패턴).
  → 5013 컷오버 시 `proxy_set_header Host 127.0.0.1:5013;` 도 같이 바꿔야 함(빠뜨리면 rebinding 차단).

## 규약화 리팩터 결정(2026-07-19, 사용자 지적 "경로·계정은 YAML 에서")
- 이 프로젝트의 실제 배포 규약(조사로 확정): **코어 웹서비스** = dashboard/systemd/install_services.sh
  가 YAML(web_services.service_user → users.ssh_user)에서 계정, repo 위치에서 경로를 유도해
  /etc/systemd 유닛을 heredoc 생성. **MCP류** = `<svc>.service.example`(__SERVICE_USER__/__PROJECT_HOME__
  placeholder) + per-service install_offline.sh 가 치환(mcp-slurm 이 이 패턴). nginx 는 YAML routes 가
  아니라 파일 정본 — /mcp 블록의 정본은 cluster/config/nginx_web_production.conf.
- smarttwin_mcp 는 MCP류 규약을 채택: smarttwin-mcp.service.example + install_offline.sh
  --install-service. 계정 유도 체인에 cluster_info.head_nodes[0].ssh_user 폴백 추가(이 프로젝트
  YAML 들의 실키). requirements.txt(전체 핀) 를 단일 정본으로 — deploy/requirements.lock·wheels 사본 제거.
- 휠 경로도 mcp_slurm 컨벤션으로: offline_packages_2404/python_wheels/**smarttwin_mcp/python3.12**/.
- ★함정 2건(실측)★: (1) systemd 는 지시어 줄 인라인 주석을 값으로 파싱 — `User=x  # 주석` →
  "Failed to determine user credentials" 217/USER. (2) 치환기에서 `grep -v '# placeholder'` 는 User=
  줄을 통째로 삭제 → User 부재 = **root 실행**(조용한 보안 후퇴, 실제로 발생했다 잡음). 해결 =
  템플릿 주석은 별도 줄, 설치기는 placeholder 3종 sed 치환만.
- nginx 드리프트(기존 상태, 미수정): 라이브 /etc/nginx/conf.d/hpc-portal.conf 는
  dashboard/nginx/hpc-portal.conf 계보인데 /mcp 블록은 라이브에만 수동 추가돼 있었음.
  cluster/config/nginx_web_production.conf(정본, /mcp 있음)만 5013 갱신. 두 계보 통합은 별건.

## 열린 항목
- 오프라인 휠 수집: 22.04 박스에서 cp312/manylinux 타깃으로 `pip download` — 플랫폼 태그 정확성 검증 필요
  (pydantic-core 등 네이티브 휠). B3 의 --no-index 재설치가 진짜 검증.
- 운영 템플릿(auto-tune 스텝 포함) icn401 /data 동기화 여부 미확인 — RUNBOOK 에 포함.
