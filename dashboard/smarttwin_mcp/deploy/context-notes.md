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

## 열린 항목
- 오프라인 휠 수집: 22.04 박스에서 cp312/manylinux 타깃으로 `pip download` — 플랫폼 태그 정확성 검증 필요
  (pydantic-core 등 네이티브 휠). B3 의 --no-index 재설치가 진짜 검증.
- 운영 템플릿(auto-tune 스텝 포함) icn401 /data 동기화 여부 미확인 — RUNBOOK 에 포함.
