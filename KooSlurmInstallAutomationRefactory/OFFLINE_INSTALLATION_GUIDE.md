# Slurm 오프라인 설치 가이드

이 가이드는 인터넷 연결이 없는 환경에서 Slurm 클러스터를 설치하는 방법을 설명합니다.

## 개요

### 설치 시나리오
- **온라인 환경**: 인터넷이 연결된 시스템 (패키지 다운로드)
- **오프라인 환경**: 인터넷이 없는 시스템 (실제 클러스터 설치)

### 주요 특징
- ✅ 완전 오프라인 설치 (인터넷 접근 불필요)
- ✅ 모든 의존성 패키지 포함
- ✅ Slurm 23.11.10 + cgroup v2 지원
- ✅ 기존 `setup_cluster_full.sh` 미수정 (호환성 유지)

---

## Part 1: 온라인 환경에서 패키지 다운로드

### 시스템 요구사항
- Ubuntu 22.04 LTS
- 디스크 공간: 최소 2GB
- 인터넷 연결: 필수

### 1-1. 저장소 다운로드 (온라인)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
```

### 1-2. 패키지 다운로드 실행

```bash
./download_packages_all.sh
```

**실행 내용:**
1. Slurm 23.11.10 소스 다운로드
2. 필수 .deb 패키지 다운로드 (약 200-300개)
3. Python 패키지 다운로드 (PyYAML, paramiko 등)
4. 설치 스크립트 백업
5. 압축 아카이브 생성

**소요 시간:** 약 5-10분 (네트워크 속도에 따라 다름)

### 1-3. 다운로드 결과 확인

```bash
ls -lh slurm-offline-packages-*.tar.gz
```

출력 예시:
```
-rw-r--r-- 1 user user 850M Oct 23 12:34 slurm-offline-packages-20251023.tar.gz
```

---

## Part 2: 오프라인 환경으로 전송

### 2-1. USB로 복사

```bash
# USB 마운트
sudo mount /dev/sdb1 /mnt/usb

# 파일 복사
cp slurm-offline-packages-20251023.tar.gz /mnt/usb/

# 언마운트
sudo umount /mnt/usb
```

### 2-2. SCP로 전송 (네트워크 가능한 경우)

```bash
scp slurm-offline-packages-20251023.tar.gz user@offline-machine:/tmp/
```

---

## Part 3: 오프라인 환경에서 설치

### 시스템 요구사항
- Ubuntu 22.04 LTS
- 디스크 공간: 최소 5GB
- 인터넷 연결: **불필요**

### 3-1. 압축 해제

```bash
cd /tmp
tar -xzf slurm-offline-packages-20251023.tar.gz
cd KooSlurmInstallAutomationRefactory
```

### 3-2. 오프라인 설치 실행

```bash
./setup_cluster_full_offline.sh
```

### 3-3. 설치 단계

스크립트는 다음 단계를 자동으로 실행합니다:

1. ✅ **패키지 검증**: packages/ 디렉토리 확인
2. ✅ **Python 환경**: venv 생성 및 활성화
3. ✅ **Python 패키지**: 오프라인 pip 설치
4. ✅ **시스템 패키지**: .deb 파일 설치
5. ✅ **사용자 생성**: slurm, munge 사용자
6. ✅ **Slurm 빌드**: 소스에서 컴파일 (15-20분)
7. ✅ **Munge 설정**: 인증 시스템
8. ✅ **systemd 서비스**: slurmctld, slurmd 서비스 파일
9. ✅ **slurmdbd 설치**: Accounting 데이터베이스 (선택)
10. ✅ **/etc/hosts 설정**: 모든 노드 호스트명 등록
11. ✅ **계산 노드 설치**: 원격 노드에 Slurm 설치
12. ✅ **설정 파일 생성**: slurm.conf, cgroup.conf
13. ✅ **설정 파일 배포**: 모든 노드에 설정 복사
14. ✅ **서비스 시작**: slurmctld, slurmd 시작

**소요 시간:** 약 30-40분 (빌드 시간 포함)

---

## Part 4: 설치 검증

### 4-1. 서비스 상태 확인

```bash
# 컨트롤러
sudo systemctl status slurmctld

# 계산 노드 (원격)
ssh node001 "sudo systemctl status slurmd"
```

### 4-2. 클러스터 상태 확인

```bash
sinfo
```

정상 출력 예시:
```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 7-00:00:00      2   idle node[001-002]
viz          up 60-00:00:0      1   idle viz-node001
```

### 4-3. 노드 상세 정보

```bash
sinfo -N
```

출력 예시:
```
NODELIST     NODES PARTITION STATE
node001          1   normal* idle
node002          1   normal* idle
viz-node001      1       viz idle
```

### 4-4. 테스트 작업 제출

```bash
cat > test_job.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=test
#SBATCH --output=test_%j.out
#SBATCH --cpus-per-task=2
#SBATCH --mem=1G

echo "Test job running on $(hostname)"
echo "CPUs: $SLURM_CPUS_PER_TASK"
sleep 10
echo "Job completed successfully"
EOF

sbatch test_job.sh
squeue
```

---

## 트러블슈팅

### 문제 1: 패키지 누락

**증상:**
```
dpkg: dependency problems prevent configuration
```

**해결:**
```bash
cd packages/deb
sudo dpkg -i *.deb
sudo apt-get install -f -y
```

### 문제 2: Slurm 빌드 실패

**증상:**
```
configure: error: systemd support requested but libsystemd not found
```

**해결:**
```bash
# 의존성 확인
dpkg -l | grep libsystemd-dev

# 누락 시 packages/deb에서 재설치
cd packages/deb
sudo dpkg -i libsystemd-dev*.deb
```

### 문제 3: slurmd 등록 실패

**증상:**
```
error: Unable to register: Unable to contact slurm controller
```

**해결:**
```bash
# 1. /etc/hosts 확인
cat /etc/hosts | grep smarttwincluster

# 2. 없으면 추가
echo "192.168.122.1 smarttwincluster" | sudo tee -a /etc/hosts

# 3. slurmd 재시작
sudo systemctl restart slurmd
```

### 문제 4: 노드가 DOWN 상태

**증상:**
```
NODELIST     STATE
node001      down
```

**해결:**
```bash
# 노드 활성화
scontrol update NodeName=node001 State=RESUME

# 상태 확인
sinfo
```

---

## 온라인 vs 오프라인 비교

| 항목 | setup_cluster_full.sh | setup_cluster_full_offline.sh |
|------|----------------------|------------------------------|
| 인터넷 필요 | ✅ 필수 | ❌ 불필요 |
| 사전 준비 | 없음 | download_packages_all.sh 실행 |
| 설치 시간 | 30-40분 | 30-40분 (동일) |
| 패키지 다운로드 | 실행 중 | 사전 완료 |
| 기존 파일 수정 | 없음 | 없음 |
| 호환성 | 완전 동일 | 완전 동일 |

---

## FAQ

### Q1: packages/ 디렉토리 크기는?

**A:** 압축 전 약 800MB - 1.2GB, 압축 후 약 400MB - 600MB

### Q2: 다른 Ubuntu 버전에서 사용 가능한가요?

**A:** Ubuntu 22.04 기준으로 패키지가 다운로드됩니다.
다른 버전(20.04, 24.04)에서는 패키지 호환성 문제가 발생할 수 있습니다.

### Q3: 패키지를 업데이트하려면?

**A:** 온라인 환경에서 `./download_packages_all.sh`를 다시 실행하세요.

### Q4: 기존 온라인 설치 스크립트와 차이점은?

**A:**
- `setup_cluster_full.sh`: 인터넷에서 실시간 다운로드
- `setup_cluster_full_offline.sh`: packages/에서 읽음
- 기능과 결과는 완전히 동일합니다

### Q5: 일부 노드만 오프라인인 경우?

**A:**
컨트롤러는 `setup_cluster_full.sh` (온라인)으로 설치하고,
오프라인 노드는 packages/만 복사하여 설치 가능합니다.

---

## 부록: packages/ 디렉토리 구조

```
packages/
├── deb/                          # .deb 패키지 (200-300개)
│   ├── build-essential_*.deb
│   ├── gcc_*.deb
│   ├── munge_*.deb
│   ├── libsystemd-dev_*.deb
│   └── ...
├── source/                       # 소스 코드
│   └── slurm-23.11.10.tar.bz2
├── python/                       # Python 패키지
│   ├── PyYAML-*.whl
│   ├── paramiko-*.whl
│   └── ...
├── scripts/                      # 설치 스크립트
│   ├── my_cluster.yaml
│   ├── install_slurm_cgroup_v2.sh
│   ├── install_munge_auto.sh
│   ├── complete_slurm_setup.py
│   └── src/
└── README.md
```

---

## 지원 및 문의

문제 발생 시:
1. 로그 확인: `/var/log/slurm/slurmctld.log`
2. systemd 로그: `sudo journalctl -u slurmctld -n 100`
3. GitHub Issues: https://github.com/anthropics/claude-code/issues

---

**마지막 업데이트:** 2025-10-23
**Slurm 버전:** 23.11.10
**대상 OS:** Ubuntu 22.04 LTS
