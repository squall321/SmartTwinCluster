# Cluster & Dashboard Operations

## 포트 맵

| 서비스 | 포트 | 설명 |
|--------|------|------|
| frontend_3010 | 3010 | 메인 대시보드 UI |
| auth_portal_4430 | 4430 | 인증 백엔드 API |
| auth_portal_4431 | 4431 | 로그인 UI |
| backend_5010 | 5010 | 대시보드 백엔드 API |
| websocket_5011 | 5011 | 실시간 WebSocket |
| kooCAEWebServer_5000 | 5000 | CAE 백엔드 API |
| kooCAEWebAutomationServer_5001 | 5001 | CAE 자동화 서버 |
| kooCAEWeb_5173 | 5173 | CAE 프론트엔드 |
| saml_idp_7000 | 7000 | SAML IdP |
| vnc_service_8002 | 8002 | VNC 세션 관리 |
| moonlight_frontend_8003 | 8003 | Moonlight 스트리밍 UI |
| prometheus_9090 | 9090 | 모니터링 |
| node_exporter_9100 | 9100 | 시스템 메트릭 |
| nginx | 80 / 443 | 리버스 프록시 |

---

## 클러스터 설치 (최초 1회)

```bash
# 1. 노드에 stcx 계정 부트스트랩
sudo bash cluster/utils/bootstrap_spc_oneshot.sh --config my_multihead_cluster_2.yaml

# 2. 전체 설치 (phase 0~10)
sudo bash cluster/start_multihead.sh --config my_multihead_cluster_2.yaml

# 개별 phase 실행
sudo bash cluster/setup/phase3_slurm.sh       --config my_multihead_cluster_2.yaml
sudo bash cluster/setup/phase5_web.sh         --config my_multihead_cluster_2.yaml
sudo bash cluster/setup/phase8_containers.sh  --config my_multihead_cluster_2.yaml
sudo bash cluster/setup/phase9_software.sh    --config my_multihead_cluster_2.yaml
sudo bash cluster/setup/phase10_compute_deploy.sh --config my_multihead_cluster_2.yaml
```

---

## 클러스터 상태

```bash
sudo bash cluster/status_multihead.sh
sudo bash cluster/stop_multihead.sh

# Slurm
sinfo -N -l
squeue -a

# 노드 이상 자동 수정
sudo bash cluster/scripts/fix_all_nodes.sh
sudo bash cluster/scripts/fix_slurm_config_all_nodes.sh
```

---

## Dashboard — 최초 설치 / 재등록

```bash
cd dashboard

# 백엔드 venv + systemd 등록
sudo bash systemd/install_services.sh

# 재설치 (venv 포함)
sudo bash systemd/install_services.sh --reinstall

# 프론트엔드 전체 빌드 + nginx 배포
sudo bash build_all_frontends.sh

# 특정 프론트엔드만
sudo bash build_all_frontends.sh --frontend frontend_3010
```

---

## Dashboard — 코드 업데이트 배포

변경된 서비스만 자동 감지해서 배포. Slurm/munge 등 스케줄러는 건드리지 않음.

```bash
# 변경된 서비스만 자동 배포
sudo bash dashboard/deploy_update.sh

# 전체 강제 재배포
sudo bash dashboard/deploy_update.sh --all

# 특정 서비스만
sudo bash dashboard/deploy_update.sh --service backend_5010
sudo bash dashboard/deploy_update.sh --service frontend_3010

# 뭐가 변경됐는지만 확인 (배포 안 함)
bash dashboard/deploy_update.sh --dry-run

# 배포 상태 확인
bash dashboard/deploy_update.sh --status
```

---

## Dashboard — 서비스 기동 / 중지

```bash
cd dashboard

./start_all.sh          # 전체 기동 (직접 프로세스)
./stop_all.sh           # 전체 중지
./restart_production.sh # 전체 재시작 (stop → start)
```

---

## Dashboard — 상태 점검 + 에러 로그

```bash
cd dashboard

./check_services.sh                        # 전체 상태 + 에러 로그
./check_services.sh --errors-only          # 에러 있는 서비스만
./check_services.sh --service backend_5010 # 특정 서비스
./check_services.sh --lines 50             # 에러 로그 50줄
./check_services.sh --watch                # 5초마다 갱신
```

---

## Dashboard — systemd 개별 제어

```bash
# 상태
sudo systemctl status  dashboard_backend
sudo systemctl status  auth_backend
sudo systemctl status  websocket_service
sudo systemctl status  cae_backend
sudo systemctl status  cae_automation

# 재시작
sudo systemctl restart dashboard_backend
sudo systemctl restart auth_backend

# 실시간 로그
journalctl -u dashboard_backend -f
journalctl -u auth_backend      -f -n 50
journalctl -u websocket_service -f

# systemd 설치 상태 확인
sudo bash dashboard/systemd/install_services.sh --status
```

---

## Apptainer 이미지 배포

```bash
# 전체 노드 배포
sudo bash cluster/setup/phase8_containers.sh --config my_multihead_cluster_2.yaml

# 특정 이미지만
sudo bash cluster/setup/phase8_containers.sh \
    --image LSDynaBasic_aocc420_ompi4.0.5_mpp_s.sif \
    --config my_multihead_cluster_2.yaml
```

---

## 사용자 관리

```bash
# 클러스터 전체 노드에 사용자 추가
sudo bash cluster/utils/add_cluster_user.sh USERNAME \
    --account default --config my_multihead_cluster_2.yaml

# Slurm 어카운팅 등록
sacctmgr -i add user USERNAME account=default
```

---

## nginx

```bash
sudo nginx -t                # 설정 문법 검사
sudo systemctl reload nginx  # 무중단 반영
sudo systemctl restart nginx

tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log
```

---

## 로그 위치

| 서비스 | 로그 경로 |
|--------|-----------|
| auth_portal_4430 | `dashboard/auth_portal_4430/logs/` |
| backend_5010 | `dashboard/backend_5010/backend.log` |
| websocket_5011 | `dashboard/websocket_5011/logs/` |
| cae_backend | `dashboard/kooCAEWebServer_5000/logs/` |
| nginx | `/var/log/nginx/` |
| systemd 서비스 | `journalctl -u <서비스명>` |
| 클러스터 설치 | `/var/log/cluster_multihead_setup.log` |
