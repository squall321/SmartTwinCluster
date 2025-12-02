# HPC 클러스터 + 웹 서비스 완전 설치 가이드

## 📋 개요

이 문서는 **Slurm 클러스터 설치**부터 **웹 서비스 배포**까지 전체 시스템을 구축하는 순서를 설명합니다.

**전체 소요 시간**: 약 1-2시간 (자동화 기준)
**수동 작업**: 최소화 (설정 파일 2개만 편집)

---

## 🗂️ 전체 구조

```
HPC 시스템 = Slurm 클러스터 + 웹 서비스

┌─────────────────────────────────────────────────────┐
│  Phase 1: Slurm 클러스터 설치                        │
│  ├─ 스크립트: setup_cluster_full.sh                 │
│  └─ 설정 파일: my_cluster.yaml                      │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│  Phase 2: 웹 서비스 설치                            │
│  ├─ 스크립트: setup_web_services.sh                 │
│  └─ 설정 파일: web_services_config.yaml             │
└─────────────────────────────────────────────────────┘
```

---

## 📝 Phase 1: Slurm 클러스터 설치

### 1.1 필요한 파일

| 파일 | 역할 | 편집 필요 |
|------|------|----------|
| **my_cluster.yaml** | 클러스터 설정 (노드, 파티션 등) | ✅ **필수** |
| `setup_cluster_full.sh` | 자동 설치 스크립트 | ❌ 편집 불필요 |
| `install_slurm_cgroup_v2.sh` | Slurm 컴파일 설치 | ❌ 자동 호출 |
| `configure_slurm_from_yaml.py` | Slurm 설정 생성 | ❌ 자동 호출 |
| `install_munge_auto.sh` | Munge 인증 설치 | ❌ 자동 호출 |

### 1.2 설정 파일: my_cluster.yaml

**편집 위치**: 프로젝트 루트
**편집 내용**: 클러스터 노드 정보, 파티션 설정

```yaml
# ============================================================
# 클러스터 기본 정보
# ============================================================
cluster_info:
  cluster_name: "SmartTwinCluster"          # 클러스터 이름
  domain: "hpc.local"                       # 도메인
  admin_email: "admin@hpc.local"            # 관리자 이메일

# ============================================================
# 노드 구성 (편집 필요!)
# ============================================================
nodes:
  controller:
    hostname: "gpu-master"                  # 컨트롤러 호스트명
    ip_address: "192.168.122.90"            # 컨트롤러 IP
    ssh_user: "koopark"                     # SSH 사용자
    ssh_key_path: "~/.ssh/id_rsa"           # SSH 키 경로

  compute_nodes:
    - hostname: "node001"                   # 계산 노드 1
      ip_address: "192.168.122.91"
      ssh_user: "koopark"
      hardware:
        cpus: 16
        memory_mb: 32768
        gpus: 1

    - hostname: "node002"                   # 계산 노드 2
      ip_address: "192.168.122.92"
      ssh_user: "koopark"
      hardware:
        cpus: 16
        memory_mb: 32768
        gpus: 1

# ============================================================
# Slurm 파티션 설정
# ============================================================
slurm:
  partitions:
    - name: "compute"                       # CPU 파티션
      nodes: "node001,node002"
      default: true
      max_time: "24:00:00"

    - name: "gpu"                           # GPU 파티션
      nodes: "node001,node002"
      default: false
      max_time: "48:00:00"
```

**주요 편집 항목**:
- `controller`: 마스터 노드 IP, 호스트명
- `compute_nodes`: 계산 노드 목록 (IP, CPU, 메모리, GPU)
- `partitions`: Slurm 파티션 구성

### 1.3 설치 명령어

```bash
# 1. 설정 파일 편집
nano my_cluster.yaml

# 2. 자동 설치 실행 (14단계)
chmod +x setup_cluster_full.sh
./setup_cluster_full.sh
```

### 1.4 설치 단계 (14단계)

`setup_cluster_full.sh`가 자동으로 실행하는 단계:

| 단계 | 내용 | 스크립트 | 설정 파일 |
|------|------|----------|----------|
| **Step 1** | Python 가상환경 생성 | 자동 | - |
| **Step 2** | Python 가상환경 활성화 | 자동 | - |
| **Step 3** | 설정 파일 검증 | `validate_config.py` | my_cluster.yaml |
| **Step 4** | SSH 연결 테스트 | `test_connection.py` | my_cluster.yaml |
| **Step 4.3** | **/etc/hosts 자동 설정** | `complete_slurm_setup.py` | my_cluster.yaml |
| **Step 4.5** | RebootProgram 설정 | `setup_reboot_program.sh` | my_cluster.yaml |
| **Step 5** | Munge 인증 설치 | `install_munge_auto.sh` | - |
| **Step 6** | Slurm 컨트롤러 설치 | `install_slurm_cgroup_v2.sh` | - |
| **Step 6.1** | systemd 서비스 생성 | `create_slurm_systemd_services.sh` | - |
| **Step 6.5** | Slurm Accounting 설치 | `install_slurm_accounting.sh` | - |
| **Step 7** | 계산 노드 Slurm 설치 | SSH 원격 실행 | my_cluster.yaml |
| **Step 7.5** | 원격 systemd 서비스 설정 | `setup_slurmd_service_remote.sh` | - |
| **Step 8** | Slurm 설정 파일 생성 | `configure_slurm_from_yaml.py` | my_cluster.yaml |
| **Step 9** | 설정 파일 배포 | SSH 원격 복사 | - |
| **Step 10** | Slurm 서비스 시작 | systemctl | - |
| **Step 11** | PATH 영구 설정 | /etc/profile.d/slurm.sh | - |
| **Step 12** | MPI 설치 (선택) | `install_mpi.py` | - |
| **Step 13** | Apptainer 동기화 (선택) | `sync_apptainers_to_nodes.sh` | - |
| **Step 14** | Apptainer 배포 (선택) | `deploy_apptainers.sh` | - |

**Step 4.3 상세 설명**:
- my_cluster.yaml의 모든 노드 정보를 읽어 /etc/hosts 파일 자동 업데이트
- SSH 키 자동 설정 (컨트롤러 → 모든 노드)
- 방화벽, SELinux, NTP, 필수 패키지, 환경변수 자동 설정
- viz-node 지원 (compute_nodes 외에 viz_nodes 섹션도 인식)
- 중복 단계 자동 건너뛰기 (Munge, slurm.conf, cgroup, NFS는 후속 단계에서 처리)

### 1.5 설치 결과 확인

```bash
# Slurm 명령어 확인
sinfo              # 노드 상태
squeue             # 작업 큐
scontrol show nodes # 노드 상세 정보

# 서비스 상태 확인
sudo systemctl status slurmctld  # 컨트롤러
sudo systemctl status slurmd     # 계산 노드 (각 노드에서)
```

**예상 출력**:
```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
compute*     up 1-00:00:00      2   idle node[001-002]
gpu          up 2-00:00:00      2   idle node[001-002]
```

---

## 📝 Phase 2: 웹 서비스 설치

### 2.1 필요한 파일

| 파일 | 역할 | 편집 필요 |
|------|------|----------|
| **web_services_config.yaml** | 웹 서비스 설정 | ✅ **프로덕션만** |
| `setup_web_services.sh` | 자동 설치 스크립트 | ❌ 편집 불필요 |
| `generate_env_files.py` | .env 파일 생성 | ❌ 자동 호출 |
| `install_dependencies.sh` | 시스템 의존성 설치 | ❌ 자동 호출 |
| `start.sh` | 서비스 시작 | ❌ 편집 불필요 |
| `stop.sh` | 서비스 중지 | ❌ 편집 불필요 |

### 2.2 설정 파일: web_services_config.yaml

**편집 위치**: 프로젝트 루트
**편집 필요**: Development는 기본값 사용, Production만 편집

```yaml
# ============================================================
# 환경별 설정
# ============================================================
environments:
  development:
    domain: "localhost"                     # 개발 환경
    sso_enabled: false                      # SSO 비활성화

  production:
    domain: "hpc.example.com"               # ← 프로덕션 도메인 변경
    sso_enabled: true                       # SSO 활성화

# ============================================================
# 서비스별 설정 (11개 서비스)
# ============================================================
services:
  # Auth Portal Backend (4430)
  auth_portal_backend:
    environment:
      development:
        JWT_SECRET_KEY: "dev-jwt-secret-please-change"

      production:
        JWT_SECRET_KEY: "CHANGE-THIS-IN-PRODUCTION"  # ← 변경 필요
        SAML_IDP_METADATA_URL: "https://your-idp.com/metadata"  # ← IdP URL

  # Dashboard Backend (5010)
  dashboard_backend:
    environment:
      development:
        SLURM_CONTROL_NODE: "gpu-master"    # ← my_cluster.yaml과 일치
        SLURM_PARTITION_CPU: "compute"      # ← my_cluster.yaml과 일치
        SLURM_PARTITION_GPU: "gpu"          # ← my_cluster.yaml과 일치

      production:
        SLURM_CONTROL_NODE: "gpu-master"    # ← 프로덕션 마스터 노드
        SLURM_PARTITION_CPU: "compute"
        SLURM_PARTITION_GPU: "gpu"

  # ... (나머지 9개 서비스는 기본값 사용)
```

**주요 편집 항목 (프로덕션 배포 시)**:
- `environments.production.domain`: 실제 도메인
- `JWT_SECRET_KEY`: 보안 키 변경
- `SAML_IDP_METADATA_URL`: SSO IdP URL
- `SLURM_CONTROL_NODE`: my_cluster.yaml의 controller와 일치

**Development 환경은 기본값 그대로 사용 가능!**

### 2.3 설치 명령어

**모든 명령어는 프로젝트 루트에서 실행합니다!**

```bash
# ============================================================
# Phase 0-2: 초기 설정
# ============================================================

# 1. 현재 상태 수집
./collect_current_state.sh

# 2. 디렉토리 구조 생성
./create_directory_structure.sh

# 3. Python 의존성 설치
pip3 install pyyaml jinja2

# ============================================================
# Phase 3: 환경 변수 생성
# ============================================================

# 4. 설정 파일 편집 (프로덕션만)
# nano web_services_config.yaml

# 5. 환경 변수 생성 (11개 .env 파일 자동 생성)
./generate_env_files.sh development

# ============================================================
# Phase 4: ONE-COMMAND 설치 + 자동 시작
# ============================================================

# 6. 완전 자동 설치 (의존성 + 서비스 시작)
./setup_web_services.sh development --auto-start

# 또는 수동 시작 방식:
# ./setup_web_services.sh development
# ./start.sh

# ============================================================
# Phase 5: 확인
# ============================================================

# 7. 헬스 체크
./health_check.sh
```

### 2.4 설치 단계 상세

#### Phase 0-2: 초기 설정 (3단계)

| 단계 | 스크립트 | 기능 | 소요 시간 |
|------|----------|------|----------|
| 1 | `collect_current_state.sh` | 현재 시스템 상태 수집 | 10초 |
| 2 | `create_directory_structure.sh` | 디렉토리 구조 생성 | 5초 |
| 3 | `pip3 install pyyaml jinja2` | Python 의존성 설치 | 30초 |

#### Phase 3: 환경 변수 생성 (1단계)

| 스크립트 | 입력 | 출력 | 기능 |
|----------|------|------|------|
| `generate_env_files.sh` | web_services_config.yaml | 11개 .env 파일 | Jinja2 템플릿으로 환경 변수 생성 |

**내부 호출**: `web_services/scripts/generate_env_files.py`

**생성되는 파일**:
```
dashboard/auth_portal_4430/.env
dashboard/auth_portal_4431/.env
dashboard/frontend_3010/.env
dashboard/backend_5010/.env
dashboard/websocket_5011/.env
dashboard/kooCAEWeb_5173/.env
dashboard/kooCAEWebServer_5000/.env
dashboard/kooCAEWebAutomationServer_5001/.env
dashboard/vnc_service_8002/.env
dashboard/prometheus_9090/.env
dashboard/node_exporter_9100/.env
```

#### Phase 4: ONE-COMMAND 설치 (setup_web_services.sh)

**내부 호출**: `web_services/scripts/setup_web_services.sh`

`setup_web_services.sh`가 자동으로 수행하는 작업:

| 순서 | 작업 | 스크립트 | 소요 시간 |
|------|------|----------|----------|
| 1 | 시스템 의존성 설치 | `install_dependencies.sh` | 3-5분 |
| 2 | .env 파일 백업 | 내장 | 10초 |
| 3 | Python venv 생성 (5개) | 자동 | 2-3분 |
| 4 | Node.js npm install (4개) | 자동 | 3-5분 |
| 5 | 서비스 자동 시작 (옵션) | `./start.sh` | 30초 |
| 6 | 헬스 체크 | `health_check.sh` | 10초 |

**자동으로 설치되는 의존성**:
- ✅ Python3, Node.js, npm
- ✅ Redis (자동 설치 및 시작)
- ✅ Nginx (설정 파일 생성)
- ✅ Python venv (각 서비스별)
- ✅ Python 패키지 (requirements.txt)
- ✅ Node.js 패키지 (npm install)

### 2.5 설치 결과 확인

```bash
# 헬스 체크
./health_check.sh
```

**예상 출력**:
```
🔍 웹 서비스 헬스 체크
====================
✅ Dashboard Frontend             (3010) - HEALTHY
✅ Auth Portal Backend            (4430) - HEALTHY
✅ Auth Portal Frontend           (4431) - HEALTHY
✅ Dashboard Backend              (5010) - HEALTHY
✅ Dashboard WebSocket            (5011) - HEALTHY
✅ CAE Frontend                   (5173) - HEALTHY
✅ CAE Backend                    (5000) - HEALTHY
✅ CAE Automation                 (5001) - HEALTHY
✅ VNC Service                    (8002) - HEALTHY
✅ Prometheus                     (9090) - HEALTHY
✅ Node Exporter                  (9100) - HEALTHY

✅ 전체: 11/11 서비스 정상
```

**브라우저 접속**: http://localhost:4431/

---

## 🔄 전체 설치 순서 (요약)

### 신규 서버 완전 설치

```bash
# ============================================================
# Part 1: Slurm 클러스터 설치 (30-45분)
# ============================================================

# 1. 설정 파일 편집
nano my_cluster.yaml

# 2. Slurm 클러스터 자동 설치
./setup_cluster_full.sh

# 3. Slurm 확인
sinfo

# ============================================================
# Part 2: 웹 서비스 설치 (10-15분)
# ============================================================

# 4. 초기 설정
./collect_current_state.sh
./create_directory_structure.sh
pip3 install pyyaml jinja2

# 5. 환경 변수 생성
./generate_env_files.sh development

# 6. 웹 서비스 ONE-COMMAND 설치
./setup_web_services.sh development --auto-start

# 7. 웹 서비스 확인
./health_check.sh

# ============================================================
# 완료!
# ============================================================
# - Slurm 클러스터: http://localhost:9090 (Prometheus)
# - 웹 대시보드: http://localhost:4431/
```

**총 소요 시간**: 40-60분
**사용자 편집 파일**: 2개 (my_cluster.yaml, web_services_config.yaml)

---

## 📊 설정 파일 매핑

### my_cluster.yaml → Slurm 설정

| my_cluster.yaml | 생성되는 Slurm 설정 |
|-----------------|---------------------|
| `cluster_info.cluster_name` | `/usr/local/slurm/etc/slurm.conf`: ClusterName |
| `nodes.controller` | `/usr/local/slurm/etc/slurm.conf`: SlurmctldHost |
| `nodes.compute_nodes` | `/usr/local/slurm/etc/slurm.conf`: NodeName |
| `slurm.partitions` | `/usr/local/slurm/etc/slurm.conf`: PartitionName |

**생성 스크립트**: `configure_slurm_from_yaml.py`

### web_services_config.yaml → .env 파일

| web_services_config.yaml | 생성되는 .env 파일 |
|--------------------------|-------------------|
| `environments.development` | 각 서비스의 .env (development 섹션) |
| `environments.production` | 각 서비스의 .env (production 섹션) |
| `services.dashboard_backend.SLURM_CONTROL_NODE` | `dashboard/backend_5010/.env`: SLURM_CONTROL_NODE |
| `services.auth_portal_backend.JWT_SECRET_KEY` | `dashboard/auth_portal_4430/.env`: JWT_SECRET_KEY |

**생성 스크립트**: `generate_env_files.py`

### my_cluster.yaml ↔ web_services_config.yaml 연계

**반드시 일치해야 하는 값**:

| 항목 | my_cluster.yaml | web_services_config.yaml |
|------|-----------------|--------------------------|
| 마스터 노드 | `nodes.controller.hostname` | `services.dashboard_backend.SLURM_CONTROL_NODE` |
| CPU 파티션 | `slurm.partitions[0].name` | `services.dashboard_backend.SLURM_PARTITION_CPU` |
| GPU 파티션 | `slurm.partitions[1].name` | `services.dashboard_backend.SLURM_PARTITION_GPU` |

**예시**:
```yaml
# my_cluster.yaml
nodes:
  controller:
    hostname: "gpu-master"  # ← 이 값을

slurm:
  partitions:
    - name: "compute"       # ← 이 값을
    - name: "gpu"           # ← 이 값을
```

```yaml
# web_services_config.yaml
services:
  dashboard_backend:
    environment:
      development:
        SLURM_CONTROL_NODE: "gpu-master"      # ← 여기 동일
        SLURM_PARTITION_CPU: "compute"        # ← 여기 동일
        SLURM_PARTITION_GPU: "gpu"            # ← 여기 동일
```

---

## 🔧 주요 명령어 참조

### Slurm 관련

```bash
# 서비스 제어
sudo systemctl start slurmctld    # 컨트롤러 시작
sudo systemctl stop slurmctld     # 컨트롤러 중지
sudo systemctl status slurmctld   # 컨트롤러 상태

./start_slurm_cluster.sh          # 전체 클러스터 시작
./stop_slurm_cluster.sh           # 전체 클러스터 중지

# 상태 확인
sinfo                             # 노드 상태
sinfo -N                          # 노드별 상세 정보
squeue                            # 작업 큐
scontrol show nodes               # 노드 상세 정보
scontrol show partition           # 파티션 정보

# 작업 제출
sbatch test.sh                    # 배치 작업 제출
srun hostname                     # 대화형 작업 실행
scancel 123                       # 작업 취소

# 설정 재로드
sudo scontrol reconfigure         # 설정 다시 읽기
```

### 웹 서비스 관련

```bash
# 서비스 제어
./start.sh                        # 전체 서비스 시작
./stop.sh                         # 전체 서비스 중지

# 상태 확인
./health_check.sh                 # 헬스 체크

# 설정 재생성
./generate_env_files.sh development          # .env 재생성
./setup_web_services.sh development          # 재설치

# 환경 전환
./web_services/scripts/reconfigure_web_services.sh production  # Dev → Prod
./web_services/scripts/reconfigure_web_services.sh development # Prod → Dev

# 롤백
./web_services/scripts/rollback.sh --latest  # 최신 백업으로 복구

# Nginx 설정
./web_services/scripts/setup_nginx.sh development   # Nginx 설정 생성
./web_services/scripts/setup_letsencrypt.sh <domain> <email>  # SSL 인증서
```

---

## 🎯 환경별 차이점

### Development 환경

```bash
# 환경 변수 생성
./generate_env_files.sh development

# 웹 서비스 설치
./setup_web_services.sh development --auto-start
```

**특징**:
- HTTP (포트 80)
- SSO 비활성화
- MOCK_MODE=true (Slurm 없이 테스트 가능)
- localhost 도메인
- 디버그 모드 활성화

**접속 URL**: http://localhost:4431/

### Production 환경

```bash
# 1. 설정 파일 편집
nano web_services_config.yaml
# → domain: "hpc.example.com"
# → JWT_SECRET_KEY 변경
# → SAML_IDP_METADATA_URL 설정

# 2. 환경 변수 생성
./generate_env_files.sh production

# 3. SSL 인증서 설정
./web_services/scripts/setup_letsencrypt.sh hpc.example.com admin@example.com

# 4. Nginx 설정
./web_services/scripts/setup_nginx.sh production

# 5. 웹 서비스 설치
./setup_web_services.sh production --auto-start

# 6. 방화벽 설정
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**특징**:
- HTTPS (포트 443)
- SSO 활성화
- MOCK_MODE=false (실제 Slurm 사용)
- 실제 도메인
- 프로덕션 모드

**접속 URL**: https://hpc.example.com/

---

## 📚 관련 문서

### Slurm 관련
- [README.md](README.md) - Slurm 자동 설치 개요
- `CGROUP_V2_INSTALLATION_GUIDE.md` - cgroup v2 설치 가이드
- `dashboard/SLURM_INTEGRATION_GUIDE.md` - Slurm 통합 가이드

### 웹 서비스 관련
- [QUICKSTART_WEB.md](QUICKSTART_WEB.md) - 5분 빠른 시작 가이드
- [AUTOMATION_SUMMARY.md](AUTOMATION_SUMMARY.md) - 자동화 개선 요약
- [WEB_SLURM_INTEGRATION.md](WEB_SLURM_INTEGRATION.md) - 웹/Slurm 연동 가이드
- [DEPLOYMENT.md](DEPLOYMENT.md) - 웹 서비스 배포 가이드
- [OPERATIONS.md](OPERATIONS.md) - 웹 서비스 운영 가이드
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - 문제 해결 가이드

---

## 💡 핵심 요약

### 사용자가 해야 할 일

| 단계 | 작업 | 파일 |
|------|------|------|
| 1 | Slurm 설정 편집 | `my_cluster.yaml` |
| 2 | Slurm 설치 실행 | `./setup_cluster_full.sh` |
| 3 | 웹 서비스 설정 편집 (프로덕션만) | `web_services_config.yaml` |
| 4 | 웹 서비스 설치 실행 | `./setup_web_services.sh development --auto-start` |

**총 편집 파일**: 2개 (my_cluster.yaml, web_services_config.yaml)
**총 실행 명령**: 6개 (초기 설정 3개 + Slurm 1개 + 웹 서비스 2개)

**모든 명령은 프로젝트 루트에서 실행!**

### 자동으로 처리되는 것

**Slurm 클러스터**:
- ✅ Munge 인증 설치
- ✅ Slurm 컴파일 및 설치
- ✅ cgroup v2 설정
- ✅ slurm.conf 자동 생성
- ✅ 계산 노드 원격 설치
- ✅ systemd 서비스 설정
- ✅ Accounting (slurmdbd) 설치
- ✅ PATH 영구 설정

**웹 서비스**:
- ✅ 시스템 의존성 설치 (Python3, Node.js, Redis)
- ✅ Python venv 생성 (5개 서비스)
- ✅ Node.js npm install (4개 서비스)
- ✅ .env 파일 생성 (11개 서비스)
- ✅ 서비스 자동 시작 (--auto-start 옵션)
- ✅ Nginx 설정 생성
- ✅ 헬스 체크

---

**작성일**: 2025-10-20
**버전**: 1.0
**결론**: 설정 파일 2개만 편집하면, 나머지는 **완전 자동화**!
