# KooSlurmInstallAutomation

🚀 **자동화된 Slurm 클러스터 설치 도구**

Python 기반의 강력하고 사용하기 쉬운 Slurm 클러스터 자동 설치 도구입니다. 복잡한 Slurm 설치 과정을 간소화하고, 다양한 클러스터 구성에 맞는 설정을 지원합니다.

## ⚡ 5분 빠른 시작

```bash
# 1. 프로젝트 재구성 및 환경 설정 (처음 1회만)
./reorganize.sh

# 2. 가상환경 활성화
source venv/bin/activate

# 3. 설정 파일 준비
cp examples/2node_example.yaml my_cluster.yaml
vim my_cluster.yaml  # IP 주소와 호스트명 수정

# 4. 설치 시작
./install_slurm.py -c my_cluster.yaml
```

**더 자세한 내용은 [QUICKSTART.md](QUICKSTART.md)를 참조하세요!**

## 🌟 주요 기능

### ✨ 핵심 기능
- **🔧 단계별 설치**: 기본 설치부터 고급 기능까지 3단계로 구분
- **📋 설정 파일 기반**: YAML 형식의 직관적인 설정 관리
- **🔍 자동 검증**: 설치 전 시스템 요구사항 및 네트워크 연결성 검증
- **🌐 병렬 처리**: 여러 노드에 동시 설치로 시간 단축
- **📊 실시간 모니터링**: 설치 진행 상황 실시간 확인

### 🎯 설치 단계
- **Stage 1 - 기본 설치**: Slurm 핵심 구성 요소, NFS, 기본 파티션
- **Stage 2 - 고급 기능**: 데이터베이스, 모니터링(Prometheus/Grafana), HA
- **Stage 3 - 운영 최적화**: 성능 튜닝, 전력 관리, 컨테이너 지원, 백업

### 🔧 지원 환경
- **운영체제**: CentOS 7/8/9, RHEL 7/8/9, Ubuntu 18.04/20.04/22.04
- **하드웨어**: CPU, GPU(NVIDIA/AMD), 고성능 네트워크
- **스토리지**: NFS, Lustre, BeeGFS, GPFS

## 📁 프로젝트 구조

```
KooSlurmInstallAutomation/
├── 🔧 실행 스크립트
│   ├── install_slurm.py       # 메인 설치 도구
│   ├── generate_config.py     # 설정 파일 생성
│   ├── validate_config.py     # 설정 파일 검증
│   ├── test_connection.py     # SSH 연결 테스트
│   ├── view_performance_report.py # 성능 리포트 뷰어
│   └── run_tests.py           # 단위 테스트 실행
├── 📦 소스 코드 (src/)
│   ├── main.py                # 메인 설치 로직
│   ├── config_parser.py       # 설정 파일 파싱
│   ├── ssh_manager.py         # SSH 연결 관리
│   ├── os_manager.py          # OS별 패키지 관리
│   ├── slurm_installer.py     # Slurm 설치 코어
│   ├── pre_install_validator.py # 설치 전 검증
│   ├── advanced_features.py   # 고급 기능 설치
│   ├── performance_monitor.py # 성능 모니터링
│   └── utils.py               # 공통 유틸리티
├── 📋 설정 템플릿 (templates/)
│   ├── stage1_basic.yaml      # 기본 설치 템플릿
│   ├── stage2_advanced.yaml   # 고급 기능 템플릿
│   ├── stage3_optimization.yaml # 최적화 템플릿
│   └── complete_template.yaml # 전체 통합 템플릿
├── 📄 예시 설정 (examples/)
│   ├── 2node_example.yaml     # 2노드 기본 구성
│   └── 4node_research_cluster.yaml # 4노드 연구용
├── 🧪 테스트 (tests/)
│   ├── test_config_parser.py  # 설정 파서 테스트
│   ├── test_utils.py          # 유틸리티 테스트
│   └── test_ssh_manager.py    # SSH 관리자 테스트
└── 📚 문서
    ├── README.md              # 이 파일
    ├── requirements.txt       # Python 의존성
    └── .gitignore            # Git 무시 파일
```

---

## 🌐 HPC 웹 서비스 자동화 (NEW!)

### ⚡ ONE-COMMAND 배포 시스템

HPC 클러스터용 웹 서비스 (Auth Portal, Dashboard, CAE, VNC 등)를 **10-15분** 안에 자동으로 배포합니다!

#### 핵심 기능
- **ONE-COMMAND 배포**: 신규 서버에 단 한 번의 명령으로 전체 설치
- **환경 자동 전환**: Development ↔ Production 원클릭 전환 (1-2분)
- **Nginx Reverse Proxy**: 11개 서비스 통합 라우팅 (HTTP/HTTPS)
- **SSL 자동화**: Let's Encrypt 또는 자체 서명 인증서 자동 설정
- **롤백 기능**: 설정 변경 실패 시 10초만에 이전 상태로 복구
- **최소 코드 수정**: 기존 서비스 코드는 거의 수정하지 않음 (5개 파일만)

#### 빠른 시작 (웹 서비스)

```bash
# 1. Phase 0-2: 초기 설정
./collect_current_state.sh
./create_directory_structure.sh
pip3 install pyyaml jinja2

# 2. 환경 변수 생성
./generate_env_files.sh development

# 3. ONE-COMMAND 설치 + 자동 시작 (핵심!)
./setup_web_services.sh development --auto-start

# 또는 수동 시작 방식:
# ./setup_web_services.sh development
# ./start.sh          # Production Mode (실제 Slurm)
# ./start.sh --mock   # Mock Mode (테스트용)

# 4. Phase 4: Nginx 설정 (선택)
./web_services/scripts/setup_nginx.sh development

# 5. 헬스 체크
./health_check.sh

# 6. 서비스 중지 (필요시)
./stop.sh
```

**소요 시간**: 10-15분 (수동 설치 시 2-3시간 → **90% 시간 절감**)

#### 지원 서비스 (11개)

| 서비스 | 포트 | 설명 |
|--------|------|------|
| Auth Portal (Frontend) | 4431 | SSO 로그인 페이지 |
| Auth Portal (Backend) | 4430 | JWT 인증 API |
| Dashboard (Frontend) | 3010 | 메인 대시보드 UI |
| Dashboard (Backend) | 5010 | 대시보드 API |
| Dashboard (WebSocket) | 5011 | 실시간 통신 |
| CAE (Frontend) | 5173 | CAE 웹 인터페이스 |
| CAE (Backend) | 5000 | CAE API |
| CAE Automation | 5001 | CAE 자동화 API |
| VNC Service | 8002 | VNC 세션 관리 |
| Prometheus | 9090 | 시스템 모니터링 |
| Node Exporter | 9100 | 메트릭 수집 |

#### 주요 명령어

```bash
# 서비스 시작
./start.sh

# 서비스 중지
./stop.sh

# 헬스 체크
./health_check.sh

# Job Template 배포 (헤드노드에서 실행)
sudo ./deploy_templates.sh

# 환경 전환
./web_services/scripts/reconfigure_web_services.sh production

# 롤백
./web_services/scripts/rollback.sh --latest

# Nginx 설정
./web_services/scripts/setup_nginx.sh production

# SSL 인증서 (Let's Encrypt)
./web_services/scripts/setup_letsencrypt.sh your-domain.com admin@example.com
```

#### 문서
- **배포 가이드**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **운영 가이드**: [OPERATIONS.md](OPERATIONS.md)
- **문제 해결**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Phase 가이드**: PHASE0_GUIDE.md ~ PHASE5_GUIDE.md

#### 배포 시간 비교

| 작업 | 수동 (Before) | 자동 (After) | 절감률 |
|------|--------------|-------------|--------|
| 새 서버 설치 | 2-3시간 | **10-15분** | 90% |
| 환경 전환 | 30-60분 | **1-2분** | 95% |
| 설정 변경 | 15-30분 | **10초** | 99% |
| 롤백 | 10-20분 | **10초** | 99% |

#### 아키텍처

```
┌─────────────────────────────────────────────────┐
│           Nginx Reverse Proxy (80/443)          │
│  HTTP/HTTPS, SSL, WebSocket, Security Headers   │
└────────────────┬────────────────────────────────┘
                 │
    ┌────────────┼────────────┬──────────────┐
    │            │            │              │
┌───▼───┐  ┌────▼────┐  ┌────▼─────┐  ┌────▼────┐
│ Auth  │  │Dashboard│  │   CAE    │  │   VNC   │
│Portal │  │ (3010)  │  │  (5173)  │  │  (8002) │
│(4431) │  │ (5010)  │  │  (5000)  │  │         │
│(4430) │  │ (5011)  │  │  (5001)  │  │         │
└───────┘  └─────────┘  └──────────┘  └─────────┘
```

**Development**: HTTP (localhost)
**Production**: HTTPS (your-domain.com) + SSO

---

## 🚀 빠른 시작 (Slurm 설치)

### 1. 환경 준비

```bash
# 저장소 클론
cd /home/koopark/claude/KooSlurmInstallAutomation

# 실행 권한 설정
chmod +x make_executable.sh
./make_executable.sh

# 가상환경 설정
./setup_venv.sh

# 가상환경 활성화
source venv/bin/activate

# 의존성 설치
pip install -r requirements.txt
```

### 2. 설정 파일 생성

```bash
# 기본 템플릿과 예시 파일 생성
./generate_config.py

# 특정 디렉토리에 생성
./generate_config.py --output-dir ~/slurm-configs

# 생성된 파일들 확인
ls -la templates/ examples/
```

### 3. 설정 파일 편집

```bash
# 2노드 예시를 기반으로 실제 환경에 맞게 수정
cp examples/2node_example.yaml my_cluster.yaml
vim my_cluster.yaml

# 주요 수정 사항:
# - 호스트네임과 IP 주소
# - SSH 사용자 및 키 경로  
# - 하드웨어 사양 (CPU, 메모리, GPU)
# - 네트워크 설정
```

### 4. 설치 전 검증

```bash
# 설정 파일 검증
./validate_config.py my_cluster.yaml

# SSH 연결 테스트
./test_connection.py my_cluster.yaml

# 상세한 연결 정보 확인
./test_connection.py my_cluster.yaml --timeout 60
```

### 5. Slurm 설치

```bash
# 기본 설치 (Stage 1)
./install_slurm.py -c my_cluster.yaml

# 모든 단계 설치
./install_slurm.py -c my_cluster.yaml --stage all

# 설치 전 검증만 실행
./install_slurm.py -c my_cluster.yaml --validate-only

# 상세 로그와 함께 설치
./install_slurm.py -c my_cluster.yaml --log-level debug
```

## 🔧 상세 사용법

### 설정 파일 구조

#### 필수 섹션
```yaml
# 클러스터 기본 정보
cluster_info:
  cluster_name: "my-cluster"
  domain: "hpc.local"
  admin_email: "admin@hpc.local"

# 노드 구성
nodes:
  controller:
    hostname: "head01"
    ip_address: "192.168.1.10"
    ssh_user: "root"
    ssh_key_path: "~/.ssh/id_rsa"
    os_type: "centos8"
    hardware:
      cpus: 8
      memory_mb: 16384
      
  compute_nodes:
    - hostname: "compute01"
      ip_address: "192.168.1.20"
      # ... 하드웨어 정보
```

#### 고급 기능 설정
```yaml
# Stage 2: 고급 기능
database:
  enabled: true
  host: "head01"
  username: "slurm"
  password: "secure_password"

monitoring:
  prometheus:
    enabled: true
    port: 9090
  grafana:
    enabled: true
    port: 3000
```

### 명령행 옵션

#### 메인 설치 도구
```bash
./install_slurm.py [옵션]

필수 옵션:
  -c, --config FILE     설정 파일 경로

선택 옵션:
  --stage {1,2,3,all}   설치 단계 선택
  --validate-only       검증만 실행
  --dry-run            시뮬레이션 실행
  --log-level LEVEL    로그 레벨 (debug/info/warning/error)
  --max-workers N      병렬 작업 수 (기본: 10)
  --continue-on-error  오류 발생시에도 계속 진행
```

#### 설정 검증 도구
```bash
./validate_config.py config.yaml [옵션]

옵션:
  --detailed    상세한 검증 결과 출력
  --quiet       요약 정보만 출력
```

#### SSH 연결 테스트
```bash
./test_connection.py config.yaml [옵션]

옵션:
  --max-workers N   병렬 연결 수 (기본: 10)
  --timeout N       연결 타임아웃 (기본: 30초)
  --quiet          간단한 결과만 출력
```

## 🎯 설치 시나리오

### 시나리오 1: 소규모 개발 클러스터 (2노드)
```bash
# 1. 기본 설정 생성
./generate_config.py
cp examples/2node_example.yaml dev_cluster.yaml

# 2. 설정 수정 (IP, 호스트네임 등)
vim dev_cluster.yaml

# 3. 기본 설치만 수행
./install_slurm.py -c dev_cluster.yaml --stage 1
```

### 시나리오 2: 연구용 GPU 클러스터 (4노드)
```bash
# 1. 고급 설정 사용
cp examples/4node_research_cluster.yaml research_cluster.yaml
vim research_cluster.yaml

# 2. 전체 기능 설치
./install_slurm.py -c research_cluster.yaml --stage all

# 3. GPU 작업 테스트
sbatch --gres=gpu:1 gpu_test_job.sh
```

### 시나리오 3: 대규모 프로덕션 클러스터
```bash
# 1. 완전한 템플릿 사용
cp templates/complete_template.yaml production.yaml

# 2. 프로덕션 환경에 맞게 상세 설정
# - 고가용성 컨트롤러
# - 데이터베이스 클러스터
# - 모니터링 시스템
# - 백업 및 복구

# 3. 단계별 설치
./install_slurm.py -c production.yaml --stage 1
./install_slurm.py -c production.yaml --stage 2  
./install_slurm.py -c production.yaml --stage 3
```

## 🔍 문제 해결

### 일반적인 오류와 해결방법

#### SSH 연결 오류
```bash
# 원인: SSH 키 권한 문제
chmod 600 ~/.ssh/id_rsa

# 원인: SSH 에이전트 미설정
ssh-add ~/.ssh/id_rsa

# 원인: 방화벽 차단
# 각 노드에서 SSH 포트 확인
sudo firewall-cmd --list-ports
```

#### 패키지 설치 오류
```bash
# CentOS/RHEL: EPEL 저장소 설치
sudo yum install -y epel-release

# Ubuntu: 패키지 목록 업데이트
sudo apt update

# Python 의존성 재설치
pip install --upgrade -r requirements.txt
```

#### 설정 파일 오류
```bash
# 상세한 검증으로 문제 확인
./validate_config.py config.yaml --detailed

# 템플릿과 비교하여 누락된 섹션 확인
diff templates/stage1_basic.yaml my_config.yaml
```

# 로그 분석

설치 과정에서 생성되는 로그 파일들:
```bash
# 로그 디렉토리 확인
ls -la logs/

# 메인 설치 로그
cat logs/slurm_install_20250105_*.log

# 에러 전용 로그 (에러만 별도 기록)
cat logs/slurm_install_error_20250105_*.log

# 로그 파일에서 ERROR 또는 FAILED 검색
grep -i error logs/slurm_install_*.log
grep -i failed logs/slurm_install_*.log
```

### 롤백 기능 사용법

```bash
# 설치 전 스냅샷 생성 (자동으로 생성됨)
./install_slurm.py -c config.yaml --create-snapshot

# 사용 가능한 스냅샷 목록 표시
./install_slurm.py -c config.yaml --list-snapshots

# 특정 스냅샷으로 롤백
./install_slurm.py -c config.yaml --rollback snapshot_20250105_143022_stage1

# 최신 스냅샷으로 롤백 (snapshot_id 생략)
./install_slurm.py -c config.yaml --rollback
```

### 설치 상태 확인

```bash
# Slurm 서비스 상태
systemctl status slurmctld  # 컨트롤러
systemctl status slurmd     # 계산노드

# 노드 상태 확인
sinfo
sinfo -N

# 파티션 정보
sinfo -s

# 테스트 작업 제출
sbatch --wrap="hostname && date"
squeue
```

## 🧪 테스트

### 단위 테스트 실행
```bash
# 모든 테스트 실행
./run_tests.py

# 특정 테스트만 실행
python -m pytest tests/test_config_parser.py -v
python -m pytest tests/test_utils.py -v
python -m pytest tests/test_ssh_manager.py -v
```

### 통합 테스트
```bash
# 전체 설치 프로세스 테스트 (dry-run)
./install_slurm.py -c examples/2node_example.yaml --dry-run

# 네트워크 연결성 종합 테스트
./test_connection.py examples/2node_example.yaml
```

## 📊 성능 및 확장성

### 권장 하드웨어 사양

#### 컨트롤러 노드
- **CPU**: 8+ 코어
- **메모리**: 16GB+ RAM  
- **스토리지**: 500GB+ (OS + Slurm + 로그)
- **네트워크**: 1Gbps+

#### 계산 노드
- **CPU**: 16+ 코어 (워크로드에 따라 조정)
- **메모리**: 2-8GB per CPU 코어
- **스토리지**: 100GB+ (OS), 고속 스크래치 공간
- **네트워크**: 1Gbps+ (HPC 워크로드시 InfiniBand 권장)

### 확장성 고려사항

- **노드 수**: 테스트된 최대 100노드 (이론적으로는 수천 노드 지원)
- **동시 사용자**: 500+ 사용자
- **동시 작업**: 10,000+ 작업
- **파티션 수**: 50+ 파티션

## 🔒 보안 고려사항

### 네트워크 보안
- 관리 네트워크와 계산 네트워크 분리
- 방화벽 규칙 최소 권한 원칙 적용
- VPN 또는 전용선을 통한 외부 접근 제한

### 인증 및 권한
- SSH 키 기반 인증 사용
- Munge 키 정기적 로테이션
- 사용자별 리소스 제한 설정
- sudo 권한 최소화

### 데이터 보안
- 사용자 데이터 암호화 저장
- 정기적인 백업 및 복구 테스트
- 감사 로그 활성화

## 🤝 기여하기

### 개발 환경 설정
```bash
# 개발용 의존성 설치
pip install -r requirements-dev.txt

# pre-commit hook 설정
pre-commit install

# 코드 스타일 검사
black --check src/
flake8 src/

# 타입 힌트 검사  
mypy src/
```

### 기여 방법
1. **이슈 등록**: 버그 리포트나 기능 요청
2. **Pull Request**: 코드 개선이나 새 기능 추가
3. **문서 개선**: README, 코멘트, 예시 개선
4. **테스트 추가**: 테스트 커버리지 향상

## 📚 참고 자료

### Slurm 공식 문서
- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [Slurm Configuration Guide](https://slurm.schedmd.com/slurm.conf.html)
- [Slurm Quick Start](https://slurm.schedmd.com/quickstart.html)

### 관련 도구
- [Ansible Slurm Role](https://github.com/ansible/ansible)
- [Slurm Docker Images](https://hub.docker.com/r/schedmd/slurm/)
- [OpenHPC](https://openhpc.community/)

### 커뮤니티
- [Slurm User Mailing List](https://lists.schedmd.com/cgi-bin/dada/mail.cgi/list/slurm-users/)
- [Google Groups](https://groups.google.com/forum/#!forum/slurm-users)

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 👨‍💻 개발팀

**KooSlurmInstallAutomation Team**
- 주 개발자: Koo Automation Team
- 버전: 1.1.0 (개선판)
- 이메일: support@kooautomation.com

---

## 🆕 최신 업데이트 (v1.1.0)

### 주요 개선사항
- ✅ SSH 재시도 로직 추가 (최대 3회, 지수 백오프)
- ✅ 향상된 로깅 시스템 (에러 전용 로그 분리)
- ✅ 설정 파일 버전 관리 (config_version)
- ✅ 롤백 기능 (스냅샷 기반)
- ✅ 테스트 커버리지 70% 달성 (47개 테스트)
- ✅ 성능 모니터링 자동화

자세한 내용은 [IMPROVEMENTS.md](IMPROVEMENTS.md) 참조

---

## ⭐ 마지막으로

KooSlurmInstallAutomation이 여러분의 HPC 환경 구축에 도움이 되기를 바랍니다! 

🐛 **버그 발견시**: GitHub Issues에 등록해 주세요  
💡 **기능 제안**: Discussion에서 의견을 나눠주세요  
⭐ **도움이 되었다면**: Star를 눌러서 응원해 주세요  

**Happy Computing! 🚀**
