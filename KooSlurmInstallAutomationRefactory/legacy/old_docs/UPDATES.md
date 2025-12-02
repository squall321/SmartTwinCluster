# 업데이트된 기능 사용 가이드

## 🆕 새로운 기능

### 1. 기존 Slurm 자동 제거 및 초기화

기존에 설치된 Slurm을 완전히 제거하고 깨끗한 상태에서 새로 설치할 수 있습니다.

#### 사용법

```bash
# 확인 후 제거
./install_slurm.py -c config.yaml --cleanup

# 강제 제거 (확인 없이)
./install_slurm.py -c config.yaml --force-cleanup

# 제거 후 새로 설치
./install_slurm.py -c config.yaml --cleanup --stage all
```

#### 제거되는 항목
- ✅ Slurm 서비스 (slurmctld, slurmd, slurmdbd)
- ✅ Slurm 패키지 (yum/apt로 설치된 것)
- ✅ Slurm 디렉토리 (/usr/local/slurm, /var/log/slurm 등)
- ✅ Slurm 설정 파일
- ✅ Munge 키 (재생성됨)
- ✅ cron 작업
- ✅ 환경변수 설정

#### 주의사항
⚠️ **백업이 자동으로 생성됩니다**
- 디렉토리: `{path}.backup.YYYYMMDD_HHMMSS`
- Slurm 사용자는 기본적으로 삭제되지 않습니다

---

### 2. Apptainer 지원 (권장)

Singularity의 공식 후속 프로젝트인 Apptainer를 지원합니다.

#### 설정 파일 (YAML)

```yaml
container_support:
  # Apptainer (권장)
  apptainer:
    enabled: true
    version: "1.2.5"
    install_path: "/usr/local"
    image_path: "/share/apptainer"
    cache_path: "/tmp/apptainer"
    bind_paths:
      - "/home"
      - "/share"
      - "/scratch"
  
  # Singularity (레거시)
  singularity:
    enabled: false
    version: "3.10.0"
  
  # Docker (선택)
  docker:
    enabled: false
    rootless: true
```

#### 특징
- ✅ Singularity와 100% 호환
- ✅ 더 나은 성능과 보안
- ✅ 활발한 개발 및 지원
- ✅ 자동 Go 설치 및 빌드
- ✅ 환경변수 자동 설정

#### 사용 예시

```bash
# 이미지 다운로드
apptainer pull docker://ubuntu:22.04

# 컨테이너 실행
apptainer run ubuntu_22.04.sif

# Slurm과 함께 사용
sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=container_job
#SBATCH --output=output.log

apptainer exec ubuntu_22.04.sif python3 my_script.py
EOF
```

---

## 📝 전체 설치 예시

### 시나리오 1: 완전히 새로운 설치

```bash
# 1. 설정 파일 준비
cp examples/2node_example.yaml my_cluster.yaml
vim my_cluster.yaml

# 2. 설정 검증
./validate_config.py my_cluster.yaml

# 3. SSH 연결 테스트
./test_connection.py my_cluster.yaml

# 4. 전체 설치 (Stage 1-3)
./install_slurm.py -c my_cluster.yaml --stage all
```

### 시나리오 2: 기존 Slurm 재설치

```bash
# 1. 기존 설치 제거 후 새로 설치
./install_slurm.py -c my_cluster.yaml --cleanup --stage all

# 2. 강제 제거 (확인 없이)
./install_slurm.py -c my_cluster.yaml --force-cleanup --stage all
```

### 시나리오 3: Apptainer 포함 설치

```bash
# 1. 설정 파일에 Apptainer 활성화
cat >> my_cluster.yaml <<EOF
container_support:
  apptainer:
    enabled: true
    version: "1.2.5"
    bind_paths:
      - "/home"
      - "/share"
EOF

# 2. Stage 3까지 설치 (컨테이너 지원 포함)
./install_slurm.py -c my_cluster.yaml --stage 3

# 3. 또는 단계별 설치
./install_slurm.py -c my_cluster.yaml --stage 1  # 기본
./install_slurm.py -c my_cluster.yaml --stage 2  # 고급 기능
./install_slurm.py -c my_cluster.yaml --stage 3  # 최적화 + 컨테이너
```

---

## 🔧 새로운 CLI 옵션

### 초기화 관련

| 옵션 | 설명 |
|------|------|
| `--cleanup` | 기존 Slurm 제거 (확인 후) |
| `--force-cleanup` | 기존 Slurm 강제 제거 |

### 기존 옵션

| 옵션 | 설명 |
|------|------|
| `-c, --config FILE` | 설정 파일 경로 (필수) |
| `--stage {1,2,3,all}` | 설치 단계 선택 |
| `--validate-only` | 검증만 실행 |
| `--skip-validation` | 검증 건너뛰기 |
| `--dry-run` | 시뮬레이션만 실행 |
| `--log-level LEVEL` | 로그 레벨 (debug/info/warning/error) |
| `--max-workers N` | 병렬 작업 수 (기본: 10) |
| `--continue-on-error` | 오류 발생 시에도 계속 진행 |

---

## 🐛 문제 해결

### Apptainer 설치 오류

```bash
# Go가 설치되지 않은 경우
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# 의존성 패키지 설치 (CentOS)
yum groupinstall -y 'Development Tools'
yum install -y openssl-devel libuuid-devel libseccomp-devel

# 의존성 패키지 설치 (Ubuntu)
apt install -y build-essential libssl-dev uuid-dev libseccomp-dev
```

### Slurm 제거 확인

```bash
# Slurm 프로세스 확인
ps aux | grep slurm

# Slurm 디렉토리 확인
ls -la /usr/local/slurm /var/log/slurm /var/spool/slurm

# 서비스 상태 확인
systemctl status slurmctld slurmd slurmdbd
```

---

## 💡 권장 사항

### Apptainer vs Singularity

**Apptainer를 권장하는 이유:**
- ✅ Linux Foundation 프로젝트
- ✅ Singularity의 공식 후속
- ✅ 더 나은 보안 및 성능
- ✅ 활발한 개발 및 커뮤니티
- ✅ 100% Singularity 호환

**Singularity는 언제 사용하나요?**
- 기존 Singularity 이미지가 많은 경우
- 특정 버전의 Singularity가 필요한 경우

### 초기화 시기

다음과 같은 경우 `--cleanup` 사용을 권장합니다:
- ✅ 설치가 실패하고 재시도할 때
- ✅ 설정을 크게 변경했을 때
- ✅ Slurm 버전을 업그레이드할 때
- ✅ 테스트 후 프로덕션 설치 전

---

## 📚 추가 자료

- [Apptainer 공식 문서](https://apptainer.org/docs/)
- [Slurm 공식 문서](https://slurm.schedmd.com/documentation.html)
- [컨테이너 지원 설정 예시](templates/container_support_example.yaml)

---

## 🎯 다음 단계

설치가 완료되면:

1. **노드 상태 확인**
   ```bash
   sinfo
   sinfo -N
   ```

2. **테스트 작업 제출**
   ```bash
   sbatch --wrap="hostname"
   squeue
   ```

3. **Apptainer 테스트** (설치한 경우)
   ```bash
   apptainer --version
   apptainer pull docker://hello-world
   apptainer run hello-world_latest.sif
   ```

4. **모니터링 설정** (Stage 2를 설치한 경우)
   - Prometheus: http://controller:9090
   - Grafana: http://controller:3000

Happy Computing! 🚀
