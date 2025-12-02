# Phase 1 Critical 개선사항 - 빠른 시작 가이드

## 🚀 5분 만에 시작하기

### 1단계: 실행 권한 부여 (10초)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
chmod +x make_scripts_executable.sh
./make_scripts_executable.sh
```

### 2단계: 설치 전 점검 (1분)

```bash
./pre_install_check.sh
```

모든 항목이 ✓ 표시되면 다음 단계로 진행하세요.

### 3단계: 설정 파일 준비 (2분)

```bash
# 개선된 예시 파일 복사
cp examples/2node_example_improved.yaml my_cluster.yaml

# 편집 (최소한 아래 항목만 수정)
vim my_cluster.yaml
```

**필수 수정 항목**:
```yaml
nodes:
  controller:
    hostname: "YOUR_CONTROLLER_HOSTNAME"    # 수정 필요
    ip_address: "YOUR_CONTROLLER_IP"        # 수정 필요
    
  compute_nodes:
    - hostname: "YOUR_COMPUTE_HOSTNAME"     # 수정 필요
      ip_address: "YOUR_COMPUTE_IP"         # 수정 필요
```

### 4단계: 설치 (2분)

```bash
# 설정 검증
./validate_config.py my_cluster.yaml

# Slurm 설치 (패키지 우선 방식)
./install_slurm.py -c my_cluster.yaml
```

설치가 완료되면 자동으로 Munge 검증도 수행됩니다!

---

## 📦 주요 신기능 사용법

### 1. 패키지 기반 빠른 설치

**기본값**: 자동으로 RPM/DEB 패키지로 설치 시도
```yaml
installation:
  install_method: "package"  # 5-10분 소요
```

**소스 컴파일 강제**:
```yaml
installation:
  install_method: "source"   # 30-60분 소요
```

### 2. 오프라인 설치

**패키지 다운로드** (인터넷 연결된 곳에서):
```bash
python src/offline_installer.py my_cluster.yaml prepare
```

결과: `./offline_packages/` 디렉토리에 모든 파일 다운로드

**폐쇄망으로 이동 후**:
```yaml
# my_cluster.yaml 수정
installation:
  offline_mode: true
  offline_package_dir: "./offline_packages"
```

```bash
./install_slurm.py -c my_cluster.yaml
```

### 3. Munge 검증 강화

**자동 검증** (설치 중 자동 실행):
```yaml
installation:
  munge_validation:
    enabled: true
    verify_key_consistency: true
    test_cross_authentication: true
```

**수동 검증**:
```bash
# 상세한 검증
python src/munge_validator.py my_cluster.yaml

# 빠른 검증
./verify_munge.sh
```

---

## 🔧 문제 해결

### ❌ "패키지를 찾을 수 없음"

**해결책**: 소스 컴파일로 전환
```yaml
installation:
  install_method: "source"
```

### ❌ "Munge 인증 실패"

**해결책**: Munge 재설정
```bash
python src/munge_validator.py my_cluster.yaml
```

### ❌ "컴파일 시간 초과"

**해결책**: 타임아웃 늘리기
```yaml
installation:
  timeouts:
    compile: 7200  # 2시간
```

### ❌ "SSH 연결 실패"

**해결책**: SSH 키 설정 확인
```bash
# 키 생성
ssh-keygen -t rsa -b 4096

# 키 복사
ssh-copy-id root@compute01

# 연결 테스트
ssh root@compute01 "hostname"
```

---

## ✅ 설치 확인

```bash
# 1. 서비스 상태
systemctl status slurmctld  # 컨트롤러
systemctl status slurmd     # 계산 노드

# 2. 노드 상태
sinfo

# 3. Munge 검증
./verify_munge.sh

# 4. 테스트 작업
sbatch --wrap="hostname && date"
squeue
```

---

## 📚 더 자세한 문서

- **Phase 1 완료 보고서**: `PHASE1_COMPLETE.md`
- **전체 README**: `README.md`
- **설정 예시**: `examples/2node_example_improved.yaml`
- **문제 해결**: `PHASE1_COMPLETE.md` 참조

---

## 💡 팁

### 빠른 설치를 위한 팁
1. **패키지 방식 사용** (5-10분)
2. **오프라인 패키지 사전 준비** (폐쇄망인 경우)
3. **설치 전 점검 스크립트 실행**

### 안정성을 위한 팁
1. **Munge 검증 활성화** (반드시!)
2. **타임아웃 여유있게 설정**
3. **로그 파일 모니터링**: `tail -f logs/slurm_install_*.log`

---

**Happy HPC! 🚀**

질문이나 문제가 있으면:
- GitHub Issues 등록
- `PHASE1_COMPLETE.md` 문제 해결 섹션 참조
