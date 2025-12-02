# 웹 서비스와 Slurm 연동 상태

## ✅ 완전 연동 확인

웹 서비스 자동화와 Slurm 설치 자동화가 **완전히 통합**되어 있습니다.

---

## 🔗 연동 구조

### 1. 설정 파일 레벨 연동

#### web_services_config.yaml
```yaml
# Dashboard Backend (5010)
services:
  dashboard_backend:
    environment:
      development:
        SLURM_CONTROL_NODE: "gpu-master"
        SLURM_PARTITION_CPU: "compute"
        SLURM_PARTITION_GPU: "gpu"

# CAE Backend (5000, 5001)
  koo_cae_web_server:
    environment:
      development:
        SLURM_CONTROL_NODE: "gpu-master"
        SLURM_PARTITION: "compute"
```

**효과**:
- 환경 변수 자동 생성 시 Slurm 설정 포함
- Development/Production 환경별 Slurm 노드 분리 가능

---

### 2. 코드 레벨 연동

#### Backend (dashboard/backend_5010/app.py)

**Slurm 명령어 통합**:
```python
from slurm_commands import (
    get_sinfo, get_squeue, get_sacct, get_scontrol,
    get_sreport, SBATCH, SCANCEL, check_slurm_installation
)

# Slurm 설치 확인
SLURM_AVAILABLE = check_slurm_installation()
if not SLURM_AVAILABLE:
    print("⚠️  Warning: Slurm commands not available")
```

**Mock 모드 지원**:
```python
# Mock 모드 설정 (환경변수로 제어)
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

if MOCK_MODE:
    print("⚠️  Running in MOCK MODE - No actual Slurm commands")
else:
    print("✅ Running in PRODUCTION MODE - Real Slurm commands")
```

**Slurm 설정 관리**:
```python
from slurm_config_manager import (
    slurm_config,
    create_qos,
    update_partitions,
    reconfigure_slurm,
    apply_full_configuration
)
```

#### Slurm Commands (dashboard/backend_5010/slurm_commands.py)

**명령어 경로 중앙 관리**:
```python
# Slurm 설치 경로 (환경변수로 override 가능)
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')

# 명령어 경로
SINFO = os.path.join(SLURM_BIN_DIR, 'sinfo')
SQUEUE = os.path.join(SLURM_BIN_DIR, 'squeue')
SACCT = os.path.join(SLURM_BIN_DIR, 'sacct')
SCONTROL = os.path.join(SLURM_BIN_DIR, 'scontrol')
SBATCH = os.path.join(SLURM_BIN_DIR, 'sbatch')
SCANCEL = os.path.join(SLURM_BIN_DIR, 'scancel')
```

**Slurm 설치 검증**:
```python
def check_slurm_installation() -> bool:
    """Slurm 설치 여부 확인"""
    result = run_slurm_command([SINFO, '--version'], timeout=5)
    if result.returncode == 0:
        print(f"✅ Slurm found: {result.stdout.strip()}")
        return True
```

---

### 3. 환경 변수 자동 생성

#### .env 파일 자동 생성 (generate_env_files.py)

```bash
python3 web_services/scripts/generate_env_files.py development
```

**생성되는 Slurm 환경 변수**:
```bash
# dashboard/backend_5010/.env
SLURM_CONTROL_NODE=gpu-master
SLURM_PARTITION_CPU=compute
SLURM_PARTITION_GPU=gpu

# dashboard/kooCAEWebServer_5000/.env
SLURM_CONTROL_NODE=gpu-master
SLURM_PARTITION=compute

# dashboard/kooCAEWebAutomationServer_5001/.env
SLURM_CONTROL_NODE=gpu-master
SLURM_PARTITION=compute
```

---

## 🎯 통합 워크플로우

### Slurm + 웹 서비스 통합 설치

```bash
# ============================================================
# Phase 0: Slurm 설치 (기존 자동화)
# ============================================================
./install_slurm.py -c my_cluster.yaml --stage all

# ============================================================
# Phase 1: 웹 서비스 설정 준비
# ============================================================
# 1. 초기 설정
./collect_current_state.sh
./create_directory_structure.sh

# 2. Python 의존성
pip3 install pyyaml jinja2

# 3. Slurm 설정 확인 및 web_services_config.yaml 편집
nano web_services_config.yaml
# → SLURM_CONTROL_NODE: "gpu-master" 확인
# → SLURM_PARTITION_CPU: "compute" 확인
# → SLURM_PARTITION_GPU: "gpu" 확인

# ============================================================
# Phase 2: 웹 서비스 자동 설치 + 시작
# ============================================================
# 4. 환경 변수 생성 (Slurm 설정 포함)
python3 web_services/scripts/generate_env_files.py development

# 5. ONE-COMMAND 설치 + 자동 시작
./web_services/scripts/setup_web_services.sh development --auto-start

# 6. 헬스 체크
./web_services/scripts/health_check.sh
```

**소요 시간**: Slurm 설치 + 웹 서비스 설치 = 약 30-45분

---

## 📊 연동된 기능

### 1. Dashboard Backend (5010)

**Slurm 통합 기능**:
- ✅ 실시간 노드 상태 모니터링 (`sinfo`)
- ✅ 작업 큐 조회 (`squeue`)
- ✅ 작업 히스토리 조회 (`sacct`)
- ✅ 작업 제출 (`sbatch`)
- ✅ 작업 취소 (`scancel`)
- ✅ 노드 제어 (`scontrol`)
- ✅ Slurm 설정 관리 (`slurm_config_manager`)
- ✅ Storage 관리 (Slurm 노드 기반)

**API 엔드포인트**:
```
GET  /api/nodes          - Slurm 노드 상태
GET  /api/jobs           - Slurm 작업 목록
POST /api/jobs/submit    - Slurm 작업 제출
POST /api/jobs/{id}/cancel - Slurm 작업 취소
GET  /api/storage        - Slurm 노드별 스토리지 상태
```

### 2. CAE Backend (5000, 5001)

**Slurm 통합**:
- ✅ CAE 시뮬레이션을 Slurm 작업으로 제출
- ✅ Slurm 파티션별 리소스 할당
- ✅ GPU/CPU 파티션 구분

### 3. Frontend (3010, 4431, 5173)

**Slurm 데이터 시각화**:
- ✅ 클러스터 상태 대시보드
- ✅ 작업 큐 시각화
- ✅ 리소스 사용률 차트
- ✅ 노드 토폴로지 3D 시각화

---

## 🔧 환경별 설정

### Development 환경

```yaml
# web_services_config.yaml
environments:
  development:
    domain: "localhost"

services:
  dashboard_backend:
    environment:
      development:
        SLURM_CONTROL_NODE: "gpu-master"  # 개발용 노드
        SLURM_PARTITION_CPU: "compute"
        SLURM_PARTITION_GPU: "gpu"
        MOCK_MODE: "true"  # Mock 모드 활성화
```

**특징**:
- Mock 모드: Slurm 명령어 실제 실행 안함
- 테스트 데이터 사용
- 로컬 개발 환경

### Production 환경

```yaml
# web_services_config.yaml
environments:
  production:
    domain: "hpc.example.com"

services:
  dashboard_backend:
    environment:
      production:
        SLURM_CONTROL_NODE: "production-master"  # 프로덕션 노드
        SLURM_PARTITION_CPU: "production-cpu"
        SLURM_PARTITION_GPU: "production-gpu"
        MOCK_MODE: "false"  # Mock 모드 비활성화
```

**특징**:
- 실제 Slurm 명령어 실행
- 프로덕션 클러스터 연결
- HTTPS, SSO 인증

---

## 🔄 환경 전환 시 Slurm 설정도 자동 전환

```bash
# Development → Production 전환
./web_services/scripts/reconfigure_web_services.sh production

# 결과:
# - SLURM_CONTROL_NODE: gpu-master → production-master
# - SLURM_PARTITION_CPU: compute → production-cpu
# - SLURM_PARTITION_GPU: gpu → production-gpu
# - MOCK_MODE: true → false
```

---

## 📝 설정 관리

### 사용자가 수정할 파일: 1개

**web_services_config.yaml**:
```yaml
services:
  dashboard_backend:
    environment:
      development:
        SLURM_CONTROL_NODE: "gpu-master"      # ← 변경 필요 시
        SLURM_PARTITION_CPU: "compute"        # ← 변경 필요 시
        SLURM_PARTITION_GPU: "gpu"            # ← 변경 필요 시

      production:
        SLURM_CONTROL_NODE: "prod-master"     # ← 변경 필요 시
        SLURM_PARTITION_CPU: "prod-cpu"       # ← 변경 필요 시
        SLURM_PARTITION_GPU: "prod-gpu"       # ← 변경 필요 시
```

### 자동 생성되는 파일: 11개

모든 서비스의 `.env` 파일에 Slurm 설정이 자동으로 포함됩니다.

---

## 🧪 Mock 모드 vs Production 모드

### Mock 모드 (개발용)

```bash
# .env 파일
MOCK_MODE=true
```

**동작**:
- Slurm 명령어를 실제로 실행하지 않음
- 샘플 데이터 반환
- Slurm 없이 개발 가능

**사용 시나리오**:
- 로컬 개발
- Slurm 미설치 환경
- 프론트엔드 개발

### Production 모드 (운영용)

```bash
# .env 파일
MOCK_MODE=false
```

**동작**:
- 실제 Slurm 명령어 실행
- 실시간 클러스터 데이터
- `/usr/local/slurm/bin/*` 명령어 사용

**사용 시나리오**:
- 프로덕션 배포
- 실제 HPC 클러스터 관리
- 실시간 모니터링

---

## 🔍 Slurm 명령어 경로 커스터마이징

### 환경 변수로 경로 변경

```bash
# 기본값: /usr/local/slurm/bin
export SLURM_BIN_DIR=/opt/slurm/bin

# 웹 서비스 시작
./start.sh
```

### 서비스별 설정

```yaml
# web_services_config.yaml
services:
  dashboard_backend:
    environment:
      development:
        SLURM_BIN_DIR: "/usr/local/slurm/bin"  # 커스텀 경로
```

---

## 🎯 통합 검증

### 1. Slurm 설치 확인

```bash
# Slurm 명령어 확인
/usr/local/slurm/bin/sinfo --version
/usr/local/slurm/bin/squeue --version
```

### 2. 웹 서비스 시작

```bash
./start.sh
```

### 3. Slurm 연동 테스트

```bash
# Backend 로그 확인
tail -f dashboard/backend_5010/logs/backend.log

# 예상 출력:
# ✅ Slurm found: slurm 23.11.4
# ✅ Running in PRODUCTION MODE - Real Slurm commands
```

### 4. API 테스트

```bash
# 노드 상태 조회
curl http://localhost:5010/api/nodes

# 작업 목록 조회
curl http://localhost:5010/api/jobs
```

---

## 📚 관련 문서

- **Slurm 설치**: [README.md](README.md) - Slurm 자동 설치 가이드
- **웹 서비스 설치**: [QUICKSTART_WEB.md](QUICKSTART_WEB.md) - 웹 서비스 빠른 시작
- **자동화 개선**: [AUTOMATION_SUMMARY.md](AUTOMATION_SUMMARY.md) - 자동화 개선 요약
- **배포 가이드**: [DEPLOYMENT.md](DEPLOYMENT.md) - 통합 배포 가이드

---

## 💡 핵심 요약

### ✅ 연동 상태

| 항목 | 상태 | 설명 |
|------|------|------|
| **설정 파일** | ✅ 통합 | web_services_config.yaml에서 Slurm 설정 관리 |
| **환경 변수** | ✅ 자동 | .env 파일에 Slurm 설정 자동 생성 |
| **Backend 코드** | ✅ 완전 통합 | slurm_commands.py, slurm_config_manager.py |
| **Mock 모드** | ✅ 지원 | 개발 환경에서 Slurm 없이 작동 |
| **Production 모드** | ✅ 지원 | 실제 Slurm 명령어 실행 |
| **환경 전환** | ✅ 자동 | Dev ↔ Prod 전환 시 Slurm 설정도 전환 |

### 🚀 사용자가 할 일

1. **Slurm 설치** (기존 자동화)
   ```bash
   ./install_slurm.py -c my_cluster.yaml --stage all
   ```

2. **웹 서비스 설치** (신규 자동화)
   ```bash
   python3 web_services/scripts/generate_env_files.py development
   ./web_services/scripts/setup_web_services.sh development --auto-start
   ```

**끝!** 모든 연동이 자동으로 완료됩니다.

---

**작성일**: 2025-10-20
**버전**: 1.0 (Slurm + Web Services 완전 통합)
**결론**: 웹 서비스 자동화는 Slurm과 **완전히 연동**되어 있으며, 별도 수동 작업 불필요
