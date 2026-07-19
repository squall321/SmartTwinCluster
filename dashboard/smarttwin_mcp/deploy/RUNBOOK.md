<!-- icn401(운영, Ubuntu 24.04, 오프라인) smarttwin_mcp 배포·컷오버 런북 — YAML-유도 규약 -->
# RUNBOOK — smarttwin_mcp 운영(icn401) 오프라인 배포

대상. icn401 = **Ubuntu 24.04, 오프라인, Python 3.12+**. 스테이징(이 박스)에서 검증 완료된 절차.
스트랭글러 컷오버 — mcp-slurm(:5012) 는 폴백으로 계속 가동.

경로·계정은 하드코딩하지 않는다. `install_offline.sh --install-service` 가
**계정 = env SERVICE_USER → YAML web_services.service_user → users.ssh_user → cluster_info.head_nodes[0].ssh_user**,
**경로 = repo 위치에서 유도** 하여 `smarttwin-mcp.service.example` 의 placeholder 를 치환한다
(mcp_slurm 의 `.service.example` + install_offline.sh 규약과 동일).

## 0. 사전 조건
- Python 3.12+ 확인: `python3.12 --version`. 없으면 apt(오프라인)로 —
  `sudo apt install python3.12 python3.12-venv`(offline_packages_2404/apt_packages 체계, pip 아님).
- backend_5010 가동(`curl -s localhost:5010/api/jobs/submit/health` → 200).
- `/data/SmartTwinMCP/` 존재 + 서비스 계정 쓰기권한(registry/audit DB). 없으면 `mkdir -p` + chown.

## 1. 코드 반영
```
cd <icn401-repo>   # 표준 레이아웃: ~/claude/KooSlurmInstallAutomationRefactory
git fetch && git checkout main && git pull
```
오프라인 휠 번들 확인: `offline_packages_2404/python_wheels/smarttwin_mcp/python3.12/` (68휠).
(휠은 gitignore — git 으로 안 온다. 저장소 동기화 시 rsync 등으로 offline_packages_2404 를 함께 반입.)

## 2. venv + systemd 유닛 (한 번에, YAML-유도)
```
cd <icn401-repo>/dashboard/smarttwin_mcp
sudo ./install_offline.sh --install-service
```
하는 일: py3.12 venv 를 서비스 계정으로 생성 → `--no-index` 로 requirements.txt(전체 핀) 설치 →
import 검증 → `.service.example` placeholder 치환 → enable + restart → active 확인.
YAML 이 다른 파일이면 `CLUSTER_YAML=/path/to.yaml sudo -E ./install_offline.sh --install-service`.
계정을 강제하려면 `SERVICE_USER=<user> sudo -E ./install_offline.sh --install-service`.

검증:
```
systemctl is-active smarttwin-mcp     # active
grep ^User= /etc/systemd/system/smarttwin-mcp.service   # YAML 계정이어야 함(root 금지)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:5013/mcp \
  -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}'   # → 200
```

## 3. /data 아티팩트 (드라이버 auto-tune)
```
ls -l /data/SmartTwinPreprocessor/bin/{auto_tune.py,chain_autotune.py}
# 없으면: cp tools/_shared/{auto_tune.py,chain_autotune.py} /data/SmartTwinPreprocessor/bin/
# auto-tune 스텝 포함 템플릿(smarttwin-fullangle-drop / smarttwin-partial-impact)을 운영 템플릿 경로에 동기화.
```

## 4. nginx `/mcp` 컷오버 (5012 → 5013)
정본은 `cluster/config/nginx_web_production.conf` 의 `location /mcp` 블록(이미 5013). 운영 라이브
conf 가 별도 파일이면 해당 파일의 /mcp 블록에서 **proxy_pass 와 Host 두 줄**을 5013 으로.
```
sudo cp /etc/nginx/conf.d/hpc-portal.conf /etc/nginx/conf.d/hpc-portal.conf.bak.$(date +%s)
sudo sed -i -e 's#proxy_pass http://127.0.0.1:5012;#proxy_pass http://127.0.0.1:5013;#' \
            -e 's#proxy_set_header Host 127.0.0.1:5012;#proxy_set_header Host 127.0.0.1:5013;#' \
            /etc/nginx/conf.d/hpc-portal.conf
sudo nginx -t && sudo nginx -s reload
# ★ mcp-slurm.service(:5012) 는 중지하지 말 것 — 폴백.
```

## 5. 라이브 검증 (nginx 443 경유, PAT 필요)
initialize 200(serverInfo `SmartTwinMCP`), 인증 read(get_cluster_health), write dry_run(submit_job
dry_run → /api/jobs/preview 200), PAT 없이 호출 시 fail-closed.

## 6. 롤백 (즉시, 무중단)
```
sudo sed -i -e 's#proxy_pass http://127.0.0.1:5013;#proxy_pass http://127.0.0.1:5012;#' \
            -e 's#proxy_set_header Host 127.0.0.1:5013;#proxy_set_header Host 127.0.0.1:5012;#' \
            /etc/nginx/conf.d/hpc-portal.conf
sudo nginx -t && sudo nginx -s reload    # /mcp → mcp-slurm(:5012). smarttwin-mcp 는 남겨둬도 무해.
```

## 파리티 확인 후에만
- smarttwin_mcp 운영 안정 판단 후 mcp-slurm.service disable 검토(그 전엔 유지).

## 알려진 함정
- systemd 지시어 줄의 인라인 주석은 값으로 읽힘 → `User=x # 주석` 은 217/USER 로 기동 실패.
  템플릿은 주석을 별도 줄로 유지한다(치환기에서 grep -v 로 줄 삭제도 금지 — User 줄이 통째로
  사라지면 root 로 실행되는 보안 후퇴).
- nginx 라이브 conf 는 repo 정본(cluster/config/nginx_web_production.conf)과 계보가 다를 수 있음
  (스테이징에서 확인된 드리프트). 컷오버 후 repo 정본도 5013 인지 확인할 것 — 아니면 재배포 시 5012 로 회귀.
