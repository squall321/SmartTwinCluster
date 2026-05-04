# 클러스터 설치 후 셋업 가이드

`setup_cluster_full_multihead_offline.sh` 실행 완료 후 운영 준비를 위한 단계별 가이드입니다.

대상: Ubuntu 24.04 + 커널 6.8.0-107-generic + 346 컴퓨트 클러스터

---

## 사전 단계: 메인 설치

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
sudo -E ./setup_cluster_full_multihead_offline.sh \
    --config my_multihead_cluster_346.yaml
```

자동 실행되는 phase:

| Phase | 내용 | 대상 |
|-------|------|------|
| pre_cleanup | 기존 설정 정리 | 헤드노드 |
| 0 | GlusterFS 스토리지 구성 | 컨트롤러 3대 |
| 1 | MariaDB Galera 클러스터 | 컨트롤러 3대 |
| 2 | Redis 클러스터 + Sentinel | 컨트롤러 3대 |
| 3 | Slurm 23.11.10 (slurmctld + slurmdbd + slurm.conf + gres.conf) | 컨트롤러 + 컴퓨트 |
| 4 | Keepalived VIP (10.228.128.100) | 컨트롤러 3대 |
| 5 | 웹 서비스 (대시보드 + 인증 포탈 + Nginx SSL) | 컨트롤러 |
| 6 | NVIDIA 드라이버 + CUDA 설치 | GPU 노드 10대 |
| 8 | Apptainer + 컨테이너 런타임 배포 | 전체 |
| 9 | Munge 키 동기화 + 소프트웨어 설정 | 전체 |
| 10 | 컴퓨트 노드 배포 (APT + Slurm + Munge) | 컴퓨트 346대 |

---

## 1. Slurm 검증 (필수)

### 1-1. 노드/파티션 상태

```bash
# 모든 노드 상태 확인 — 359 = 3 컨트롤러 + 346 컴퓨트 + 10 viz
sinfo -N
# 모두 idle 인지 확인. drain/down 있으면 다음 단계.

# 파티션 정의 확인
scontrol show partition
# alpha (100), beta (100), gamma (100), share (46), viz (10) 출력 확인

# 컨트롤러 응답 확인
scontrol ping
# Slurmctld(primary) at icn401-0412-h08 is UP
# Slurmctld(backup1) at icn401-0413-h08 is UP
# Slurmctld(backup2) at icn401-0414-h08 is UP

# 어카운팅 DB 연결
sacctmgr show cluster
```

### 1-2. 비정상 노드 복구

```bash
# 자동 복구 스크립트 (drain/down 노드 진단 + 복구)
sudo bash cluster/utils/fix_all_nodes.sh

# 헬스체크
sudo bash cluster/utils/health_check.sh

# 그래도 안 되면 수동 reboot
scontrol reboot ASAP NODELIST
```

### 1-3. 테스트 잡 제출

```bash
# CPU 잡 (alpha 파티션)
srun --partition=alpha -N 1 hostname
srun --partition=alpha -N 4 -l hostname     # 4 노드 병렬

# GPU 잡 (viz 파티션 — RTX PRO 6000)
srun --partition=viz --gres=gpu:1 nvidia-smi

# 메모리/CPU 사용량 확인
srun --partition=alpha -n 1 --mem=8G stress --cpu 4 --timeout 30
```

---

## 2. 웹 서비스 접속

```bash
# VIP 또는 헤드노드 IP로 접속
# https://10.228.128.100/
```

**로그인 흐름** (SSO disabled 상태 — 기본):

| 항목 | 값 |
|------|-----|
| URL | `https://10.228.128.100/` |
| 자동 리다이렉트 | `/auth_portal/` → 로그인 페이지 |
| Mock 사용자 | `koopark` / `Soseks314!` |

**확인 항목:**
- [x] HTTPS 자체 서명 인증서 경고 → "고급" → "계속 진행"
- [x] 로그인 후 서비스 메뉴 표시 (Smart Twin Flow, Extreme 등)
- [x] 대시보드 진입 → 노드/잡/스토리지 카드 정상 로드
- [x] 실시간 모니터링 페이지 — CPU/Memory/GPU 그래프 동작
- [x] Prometheus Metrics 페이지 — PromQL 쿼리 동작
- [x] Health Check 페이지 — Backend/DB/Redis 모두 OK

---

## 3. Apptainer SIF 이미지 배포 (CAE/VNC 사용 시 필수)

### 3-1. 사전 빌드된 SIF 배포

오프라인 백업 매체에서 SIF 가져와서 배포:

```bash
# 백업에서 복원 (외장하드/USB)
sudo tar -xzvf /media/external/sif_v9.3.0.tar.gz -C /opt/apptainers/

# 또는 rsync
sudo rsync -av /media/external/sif/ /opt/apptainers/

# 모든 노드에 자동 배포
sudo ./deploy_apptainers.sh --config my_multihead_cluster_346.yaml
```

### 3-2. 배포 확인

```bash
# 모든 viz 노드에 SIF 존재 확인
for node in icn401-0401-h{06..10} icn401-0402-h{06..10}; do
    echo -n "$node: "
    ssh $node "ls -lh /opt/apptainers/*.sif 2>/dev/null | wc -l"
done
```

### 3-3. SIF가 없으면 빌드 (인터넷 필요)

```bash
cd dashboard/MoonlightSunshine_8004/
sudo apptainer build vnc_xfce4.sif sunshine_xfce4_2404.def
sudo apptainer build vnc_gnome.sif sunshine_gnome_2404.def
sudo apptainer build vnc_gnome_lsprepost.sif sunshine_gnome_lsprepost_2404.def

# 빌드 후 배포
sudo ./deploy_apptainers.sh --config my_multihead_cluster_346.yaml
```

---

## 4. GPU 노드 검증

```bash
# 모든 GPU 노드 nvidia-smi 확인
for node in icn401-0401-h{06..10} icn401-0402-h{06..10}; do
    echo "=== $node ==="
    ssh $node nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
done

# Slurm GRES 등록 확인
scontrol show node icn401-0401-h06 | grep -E "Gres|CfgTRES"
# Gres=gpu:nvidia:2 가 보여야 함

# GPU 잡 큐 확인
squeue -p viz
```

---

## 5. SSO/SSL 운영 모드 전환

### 5-1. SSO 활성화 (사내 SAML/OIDC IdP 연동)

```bash
# my_multihead_cluster_346.yaml 편집
vim my_multihead_cluster_346.yaml

# sso 섹션 수정:
# sso:
#   enabled: true                    # false → true
#   type: saml                       # 또는 oidc
#   saml:
#     idp_metadata_url: "https://사내IdP/metadata"  # ← 입력
#     sp:
#       entity_id: "hpc-dashboard"
#   group_permissions:
#     "사내그룹A": [dashboard, cae, vnc, app]
#     "사내그룹B": [dashboard]

# phase 5만 재실행
sudo bash cluster/setup/phase5_web.sh --config my_multihead_cluster_346.yaml
```

### 5-2. SSL 인증서 — 사내 CA 또는 Let's Encrypt

```bash
# 사내 CA 인증서 사용:
sudo cp 사내_도메인.crt /etc/ssl/certs/
sudo cp 사내_도메인.key /etc/ssl/private/
sudo nano /etc/nginx/snippets/self-signed.conf  # 경로 수정
sudo systemctl reload nginx

# Let's Encrypt (인터넷 연결 시):
sudo certbot --nginx -d hpc.사내도메인.com
```

---

## 6. 사용자 등록 + 잡 템플릿

### 6-1. 클러스터 사용자 추가

```bash
# NFS 홈 자동 생성 + 모든 노드 동기화
sudo bash cluster/utils/add_user.sh USER01

# Slurm 어카운트 등록
sudo sacctmgr add account research-group
sudo sacctmgr add user USER01 account=research-group

# QoS 추가 (선택)
sudo sacctmgr add qos high_priority priority=100
sudo sacctmgr modify user USER01 set qos=high_priority,normal
```

### 6-2. 사용자 간 SSH 키 동기화

```bash
# 헤드노드에서 (USER01 로그인 후)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# 모든 노드에 authorized_keys 배포
for node in $(sinfo -h -N -o "%N" | sort -u); do
    ssh-copy-id -o StrictHostKeyChecking=no $node
done
```

### 6-3. 잡 템플릿 초기화

```bash
# 표준 LS-DYNA 템플릿 등록
sudo bash cluster/setup/init_template_storage.sh

# 대시보드에서 확인:
# https://VIP/dashboard/ → Job Templates 탭
```

---

## 7. 모니터링/알림 설정

### 7-1. Grafana 대시보드

```bash
# Grafana 접속
# http://VIP:3000
# 초기 로그인: admin / Soseks314!

# 대시보드 import:
# Settings → Data Sources → Add Prometheus
#   URL: http://localhost:9090
# Dashboards → Import
#   파일: dashboard/prometheus_9090/grafana_dashboard.json
```

### 7-2. Prometheus 알림 채널

```yaml
# my_multihead_cluster_346.yaml의 environment 섹션:
environment:
  SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/T.../B.../..."

# phase 6 재실행
sudo bash cluster/setup/phase6_gpu.sh --skip-driver --alerting-only
```

알림 규칙 (yaml에 정의됨):
- NodeDown (30초+ critical)
- HighCPU (90%+ 5분 warning)
- HighDisk (80%+ 1분 warning)
- GaleraNodeDown (10초+ critical)
- VIPFailover (info)

---

## 8. 백업 정책

### 8-1. 데이터베이스 일일 백업

```bash
# crontab 등록
sudo crontab -e
# 추가:
# 0 2 * * * /usr/bin/mysqldump --all-databases | gzip > /mnt/gluster/backup/db_$(date +\%Y\%m\%d).sql.gz
# 0 3 * * * find /mnt/gluster/backup/ -name "db_*.sql.gz" -mtime +30 -delete
```

### 8-2. GlusterFS 스냅샷

```bash
# 스냅샷 활성화 (LVM thin 필요)
sudo gluster snapshot config snap-max-hard-limit 30
sudo gluster snapshot config auto-delete enable

# 일일 스냅샷
sudo crontab -e
# 0 1 * * * /usr/sbin/gluster snapshot create snap_$(date +\%Y\%m\%d) shared_data
```

### 8-3. Slurm 잡 이력

```bash
# Slurm DB 자동 백업 (slurmdbd)
sudo crontab -e
# 0 4 * * 0 /usr/local/slurm/bin/sacctmgr dump cluster smart-twin-cluster file=/mnt/gluster/backup/slurm_acct_$(date +\%Y\%m\%d).cfg
```

---

## 9. 노드 추가/제거

### 9-1. 새 컴퓨트 노드 추가

```bash
# 1. YAML에 노드 정의 추가
vim my_multihead_cluster_346.yaml
# nodes.compute_nodes: 섹션에 새 노드 블록 추가

# 2. phase 10만 재실행 (컴퓨트 배포)
sudo ./setup_cluster_full_multihead_offline.sh \
    --config my_multihead_cluster_346.yaml \
    --phase 10

# 3. Slurm 재구성
sudo systemctl restart slurmctld
sudo bash cluster/utils/fix_all_nodes.sh
```

### 9-2. 노드 제거

```bash
# 1. 노드 드레인
scontrol update NodeName=NODE state=drain reason="decommission"

# 2. 잡이 끝날 때까지 대기
squeue -w NODE

# 3. YAML에서 제거 + slurm.conf 재생성
sudo bash cluster/setup/phase3_slurm.sh --regenerate-conf
```

---

## 10. 트러블슈팅 빠른 참조

| 증상 | 명령 |
|------|------|
| 노드 down/drain | `sudo bash cluster/utils/fix_all_nodes.sh` |
| Slurmctld 응답 없음 | `sudo systemctl restart slurmctld; scontrol ping` |
| 잡 PartitionConfig | `scontrol show partition` 확인, max_nodes/max_mem 조정 |
| GPU 미인식 | `nvidia-smi` 확인, `gres.conf` 점검 |
| Munge auth 실패 | `sudo bash cluster/utils/sync_munge_key.sh` |
| 웹 503 에러 | `systemctl status dashboard_backend nginx` |
| VNC 세션 안 뜸 | `journalctl -u dashboard_backend -n 50` |
| Galera split-brain | `sudo bash cluster/utils/galera_auto_recover.sh` |

---

## 운영 시작 후 주기적 작업

| 주기 | 작업 |
|------|------|
| **매일** | DB 백업, 잡 이력 확인, 알림 모니터링 |
| **매주** | `fix_all_nodes.sh` 실행, GlusterFS 스냅샷 |
| **2~3일마다** | Apptainer SIF 재배포 (전후처리 자동화 업데이트 시) |
| **매월** | Munge 키 회전, 보안 패치 검토 |
| **분기** | OS 패키지 업데이트 (오프라인 패키지 재수집) |

---

## 최소 필수 흐름 요약

```
1. setup_cluster_full_multihead_offline.sh   # phase 0~10 자동 (1~3시간)
   ↓
2. sinfo / 테스트 잡 → 정상 확인 (5분)
   ↓
3. https://VIP 접속 → 로그인 → 대시보드 동작 확인 (5분)
   ↓
4. deploy_apptainers.sh → SIF 배포 (30분~1시간)
   ↓
5. SSO 활성화 (선택) — 사내 IdP 연동 시
   ↓
6. 사용자/잡 템플릿 추가 (필요 시)
   ↓
   클러스터 운영 시작
```

이 가이드 + [BACKUP_TRANSFER_GUIDE.md](BACKUP_TRANSFER_GUIDE.md) + [INSTALL_GUIDE_346.md](INSTALL_GUIDE_346.md) 세 문서가 풀 라이프사이클을 커버합니다.
