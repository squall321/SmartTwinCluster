<!-- icn401(운영, Ubuntu 24.04, 오프라인) smarttwin_mcp 배포·컷오버 런북 -->
# RUNBOOK — smarttwin_mcp 운영(icn401) 오프라인 배포

대상. icn401 = **Ubuntu 24.04, 오프라인, Python 3.12+**. 이 박스(staging)에서 검증 완료된 절차를
운영에 적용한다. 스트랭글러 컷오버 — mcp-slurm(:5012) 는 폴백으로 계속 가동.

> ⚠️ 경로 주의. 아래 유닛/스니펫은 이 박스 경로(`/home/koopark/claude/KooSlurmInstallAutomationRefactory`)
> 로 하드코딩돼 있다. icn401 의 **실제 repo 체크아웃 경로·서비스 계정**이 다르면
> `smarttwin-mcp.service` 의 WorkingDirectory/ExecStart/PATH/PYTHONPATH/User/Group 을 먼저 고쳐라.

## 0. 사전 조건
- Python 3.12+ 존재 확인: `python3.12 --version`. 없으면 apt(오프라인)로 설치 —
  `sudo apt install python3.12 python3.12-venv`(offline_packages_2404/apt_packages 체계 사용, pip 아님).
- backend_5010 가동 중(`curl -s localhost:5010/api/jobs/submit/health` → 200).
- `/data/SmartTwinMCP/` 존재 + 서비스 계정 쓰기권한(registry/audit DB 위치). 없으면 `mkdir -p`.

## 1. 코드 반영
```
cd <icn401-repo>
git fetch && git checkout main && git pull      # smarttwin_mcp 이관 커밋들 포함
```

## 2. venv 오프라인 구축 (py3.12, --no-index)
```
cd <icn401-repo>/dashboard/smarttwin_mcp
python3.12 -m venv .venv
WHEELS=<icn401-repo>/offline_packages_2404/python_wheels/python3.12/smarttwin_mcp
.venv/bin/pip install --no-index --find-links "$WHEELS" -r "$WHEELS/requirements.lock"
# 벤더링 패키지 자체는 PYTHONPATH=src 로 로드(유닛에 설정). 별도 설치 불필요.
# 검증:
PYTHONPATH=src .venv/bin/python -c "import fastmcp,smarttwin_mcp.server as s; print(fastmcp.__version__, callable(s.main))"
```

## 3. /data 아티팩트 (드라이버 auto-tune)
```
# auto_tune.py·chain_autotune.py 가 /data/SmartTwinPreprocessor/bin 에 있어야 함(제출 병렬도 sinfo+DOE).
ls -l /data/SmartTwinPreprocessor/bin/{auto_tune.py,chain_autotune.py}
# 없으면 배치: cp tools/_shared/{auto_tune.py,chain_autotune.py} /data/SmartTwinPreprocessor/bin/ && chmod +x ...
# auto-tune 스텝 포함 템플릿(smarttwin-fullangle-drop / smarttwin-partial-impact)을 /data/templates/official 에 동기화.
```

## 4. systemd 유닛 설치 (:5013 loopback)
```
# 경로/계정 수정 후:
sudo cp deploy/smarttwin-mcp.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now smarttwin-mcp
systemctl is-active smarttwin-mcp && curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}' \
  http://127.0.0.1:5013/mcp     # → 200
```

## 5. nginx `/mcp` 컷오버 (5012 → 5013)
```
sudo cp /etc/nginx/conf.d/hpc-portal.conf /etc/nginx/conf.d/hpc-portal.conf.bak.$(date +%s)
# deploy/nginx-mcp.snippet.conf 의 location /mcp 로 교체(또는 아래 2줄 치환):
sudo sed -i -e 's#proxy_pass http://127.0.0.1:5012;#proxy_pass http://127.0.0.1:5013;#' \
            -e 's#proxy_set_header Host 127.0.0.1:5012;#proxy_set_header Host 127.0.0.1:5013;#' \
            /etc/nginx/conf.d/hpc-portal.conf
sudo nginx -t && sudo nginx -s reload
# ★ mcp-slurm.service(:5012) 는 중지하지 말 것 — 폴백.
```

## 6. 라이브 검증 (nginx 443 경유, PAT 필요)
- initialize 200(serverInfo `SmartTwinMCP`), 인증 read(get_cluster_health → mode=production),
  write dry_run(submit_job dry_run → /api/jobs/preview 200). staging 에서 쓴 검증 스크립트 재사용 가능.

## 7. 롤백 (즉시, 무중단)
```
sudo sed -i -e 's#proxy_pass http://127.0.0.1:5013;#proxy_pass http://127.0.0.1:5012;#' \
            -e 's#proxy_set_header Host 127.0.0.1:5013;#proxy_set_header Host 127.0.0.1:5012;#' \
            /etc/nginx/conf.d/hpc-portal.conf
sudo nginx -t && sudo nginx -s reload    # /mcp 가 다시 mcp-slurm(:5012) 로. smarttwin-mcp 는 남겨둬도 무해.
```

## 파리티 확인 후에만
- smarttwin_mcp 가 운영에서 안정적이라 판단되면 그때 mcp-slurm.service disable 검토(그 전엔 유지).
