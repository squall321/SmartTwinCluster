# 오프라인 HPC 클러스터 설치 - 빠른 시작 가이드

> **🎯 목적**: 계산 노드가 인터넷 차단된 환경에서 완전 자동화된 클러스터 설치
> **⏱️  예상 시간**: 사전 준비 1시간 + 설치 1-1.5시간 (10노드 기준)

---

## 📁 디렉토리 구조

```
KooSlurmInstallAutomationRefactory/
│
├── 🚀 setup_cluster_full_multihead_offline.sh    # 메인 오프라인 설치 스크립트
│
├── offline_packages/                              # 오프라인 패키지 (사전 준비)
│   ├── prepare_offline_packages.sh                # ⭐ 통합 패키징 (온라인 환경)
│   ├── setup_local_apt_mirror.sh                  # 로컬 APT 미러 구축
│   ├── collect_apt_packages.sh                    # APT 패키지 수집
│   │
│   ├── slurm/
│   │   ├── build_slurm_package.sh                 # Slurm 빌드 & 패키징
│   │   └── (생성됨) slurm-23.11.10-prebuilt.tar.gz
│   │
│   ├── apt_packages/                              # APT .deb 패키지들
│   ├── munge/                                     # Munge 인증 키
│   ├── multihead_services/                        # 멀티헤드 서비스 패키지
│   └── apt_mirror/                                # 로컬 APT 미러 (선택)
│
├── offline_deploy/                                # 오프라인 배포 도구
│   ├── deploy_to_compute_node.sh                  # ⭐ 계산 노드 자동 배포
│   └── verify_offline_deployment.sh               # ✓ 배포 검증
│
├── OFFLINE_INSTALLATION_GUIDE.md                  # 📖 상세 가이드 (필독!)
└── my_multihead_cluster.yaml                      # 클러스터 설정
```

---

## 🚀 빠른 시작 (3단계)

### **Step 1️⃣ : 온라인 환경에서 패키징** (1회만, 30-60분)

```bash
# 인터넷이 되는 환경에서 실행
cd KooSlurmInstallAutomationRefactory
sudo ./offline_packages/prepare_offline_packages.sh --all

# 결과: offline_packages/ 디렉토리에 모든 패키지 저장 (~3-5GB)
```

### **Step 2️⃣ : 오프라인 환경으로 전송**

```bash
# 방법 A: 네트워크 전송 (헤드 노드만 인터넷 가능)
rsync -avz --progress offline_packages/ \
    user@offline-headnode:/opt/KooSlurmInstallAutomationRefactory/offline_packages/

# 방법 B: USB 복사
tar -czf /mnt/usb/offline_packages.tar.gz offline_packages/
# USB를 오프라인 환경으로 이동 후
tar -xzf offline_packages.tar.gz
```

### **Step 3️⃣ : 오프라인 설치 실행** (15-25분)

```bash
# 오프라인 환경 (헤드 노드)
cd /opt/KooSlurmInstallAutomationRefactory

# 설정 파일 편집 (YAML)
vim my_multihead_cluster.yaml

# 메인 설치 스크립트 실행
sudo ./setup_cluster_full_multihead_offline.sh --config my_multihead_cluster.yaml
```

### **Step 4️⃣ : 계산 노드 배포** (노드당 3-5분)

```bash
# 헤드 노드에서 실행 (계산 노드 자동 배포)
sudo ./offline_deploy/deploy_to_compute_node.sh \
    --config my_multihead_cluster.yaml \
    --parallel 5
```

### **Step 5️⃣ : 검증**

```bash
# 전체 시스템 검증
sudo ./offline_deploy/verify_offline_deployment.sh --all

# Slurm 클러스터 확인
sinfo
srun -N10 hostname
```

---

## 📊 주요 스크립트 설명

### 🔧 **prepare_offline_packages.sh**
**역할**: 온라인 환경에서 모든 패키지를 사전 준비
**실행 환경**: 인터넷 필요
**소요 시간**: 30-60분

**수행 작업**:
1. Slurm 23.11.10 소스 빌드 (cgroup v2 지원)
2. APT 패키지 수집 (GlusterFS, MariaDB, Redis, Nginx 등)
3. Munge 인증 키 생성
4. 로컬 APT 미러 구축 (선택)

**결과물**:
```
offline_packages/
├── slurm/slurm-23.11.10-prebuilt.tar.gz   (~200MB)
├── apt_packages/*.deb                      (~2GB, 500-800개)
├── munge/munge.key
└── apt_mirror/ (선택)                      (~20-50GB)
```

---

### 🚀 **setup_cluster_full_multihead_offline.sh**
**역할**: 헤드 노드 오프라인 설치 (멀티헤드 클러스터)
**실행 환경**: 인터넷 불필요
**소요 시간**: 15-25분

**수행 작업**:
- ✓ APT 패키지 설치 (로컬 .deb)
- ✓ Slurm 프리빌드 배포 (tarball 압축 해제)
- ✓ Munge 인증 설정
- ✓ GlusterFS, MariaDB, Redis, Keepalived 설치
- ✓ 웹 서비스 (8개) 설치

---

### 🎯 **deploy_to_compute_node.sh**
**역할**: 계산 노드 자동 배포
**실행 환경**: 헤드 노드에서 실행
**소요 시간**: 노드당 3-5분 (병렬 가능)

**동작 방식**:
1. YAML에서 계산 노드 목록 추출
2. SSH로 각 노드 연결
3. rsync로 패키지 전송 (~800MB)
4. 원격 설치 스크립트 자동 실행

**옵션**:
```bash
# 병렬 5개 노드씩 배포
--parallel 5

# 특정 노드만 배포
--node node001

# 실제 실행 없이 계획만 표시
--dry-run
```

---

### ✅ **verify_offline_deployment.sh**
**역할**: 배포 검증 (설치 후 필수!)
**실행 환경**: 헤드 노드 또는 계산 노드
**소요 시간**: 1-3분

**검증 항목**:
- [x] Slurm 바이너리 및 버전
- [x] Munge 인증 (로컬 + 원격)
- [x] 계산 노드 SSH 연결
- [x] 서비스 상태 (slurmctld, slurmd, munge)
- [x] 설정 파일 존재 여부

**예상 출력**:
```
╔════════════════════════════════════════════════════════════╗
║  검증 결과 요약                                           ║
╚════════════════════════════════════════════════════════════╝

  Total Tests:   45
  Passed:        45 (✓)
  Failed:        0 (✗)
  Pass Rate:     100%

[SUCCESS] All tests passed! 🎉
```

---

## 🆚 온라인 vs 오프라인 비교

| 항목 | 온라인 설치 | 오프라인 설치 |
|------|-----------|-------------|
| **스크립트** | `setup_cluster_full_multihead.sh` | `setup_cluster_full_multihead_offline.sh` |
| **인터넷 필요** | 모든 노드 | 헤드 노드만 (사전 준비 시) |
| **Slurm 설치** | 각 노드 wget + 빌드 (15분) | tarball 압축 해제 (1분) |
| **APT 패키지** | apt-get install (인터넷) | dpkg -i *.deb (로컬) |
| **10노드 총 시간** | 3-5시간 | 1-1.5시간 |
| **네트워크 트래픽** | ~50GB (10노드) | ~5GB (1회 전송) |
| **기존 스크립트** | 유지됨 ✅ | 유지됨 ✅ |

---

## ⚙️ 설정 파일 (my_multihead_cluster.yaml)

```yaml
cluster_info:
  cluster_name: "production-hpc"

nodes:
  controllers:
    - hostname: ctrl01
      ip_address: 192.168.1.10
      ssh_user: koopark
      vip_owner: true

  compute_nodes:
    - hostname: node001
      ip_address: 192.168.1.101
      ssh_user: koopark
      hardware:
        cpus: 64
        memory_mb: 262144
    # ... 추가 노드

environment:
  DB_SLURM_PASSWORD: "your_secure_password"
  REDIS_PASSWORD: "your_secure_password"
  JWT_SECRET_KEY: "your_jwt_secret"
```

---

## 🔧 문제 해결

### 문제 1: APT 패키지 의존성 오류
```bash
cd offline_packages/apt_packages
sudo apt-get install -f
sudo dpkg -i *.deb
```

### 문제 2: Munge 인증 실패
```bash
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
sudo systemctl restart munge
```

### 문제 3: Slurm 노드 DOWN 상태
```bash
ssh node001 'sudo systemctl restart slurmd'
sudo scontrol update nodename=node001 state=resume
```

---

## 📚 더 자세한 정보

- **상세 가이드**: [OFFLINE_INSTALLATION_GUIDE.md](OFFLINE_INSTALLATION_GUIDE.md)
- **온라인 버전**: `setup_cluster_full_multihead.sh` (기존 유지)
- **문제 해결**: 가이드 문서의 "문제 해결" 섹션 참조

---

## 💡 FAQ

**Q: 로컬 APT 미러가 필수인가요?**
A: 아니오, `.deb` 파일만으로도 충분합니다. 수백 개 노드 환경에서만 권장.

**Q: Slurm 버전을 변경하려면?**
A: `offline_packages/slurm/build_slurm_package.sh`에서 `SLURM_VERSION` 수정 후 재빌드

**Q: 기존 온라인 스크립트는 어떻게 되나요?**
A: 그대로 유지됩니다. 환경에 맞게 선택해서 사용하세요.

---

## ✅ 체크리스트

### 사전 준비 (온라인)
- [ ] `prepare_offline_packages.sh --all` 실행
- [ ] offline_packages/ 생성 확인 (3-5GB)
- [ ] 오프라인 환경으로 전송

### 헤드 노드 설치
- [ ] my_multihead_cluster.yaml 편집
- [ ] setup_cluster_full_multihead_offline.sh 실행
- [ ] 서비스 상태 확인

### 계산 노드 배포
- [ ] deploy_to_compute_node.sh 실행
- [ ] verify_offline_deployment.sh --all 실행
- [ ] sinfo로 노드 상태 확인 (모두 idle)

---

**마지막 업데이트**: 2025-11-18
**버전**: 2.0
**작성자**: Claude Code
