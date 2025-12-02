# 🎯 Slurm 23.11.x + cgroup v2 완전 지원 가이드

## 📋 개요

Slurm 23.11.x를 cgroup v2 완전 지원으로 설치하는 가이드입니다.
Ubuntu 22.04 + cgroup v2 환경에 최적화되어 있습니다.

---

## ✨ 주요 기능

### cgroup v2가 제공하는 리소스 제어

1. **CPU 코어 제한** (`ConstrainCores`)
   - 사용자가 요청한 CPU 코어만 사용
   - 다른 코어 접근 차단

2. **메모리 제한** (`ConstrainRAMSpace`)
   - Job이 요청한 메모리만 사용
   - 초과 시 자동 종료 (OOM Killer)

3. **CPU 친화성** (`TaskAffinity`)
   - 프로세스가 특정 CPU에 고정
   - 성능 향상 및 예측 가능성

4. **메모리 압박 제어** (`MemoryLimitEnforce`)
   - 메모리 부족 시 강제 종료
   - Swap 사용 제한

---

## 🚀 빠른 설치 (권장)

### 전체 자동 설치 (한 번에 모든 노드)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 실행 권한 부여
chmod +x full_install_cgroup_v2.sh

# 전체 설치 실행
./full_install_cgroup_v2.sh
```

**이 스크립트가 자동으로 수행하는 작업:**
1. ✅ 컨트롤러에 Slurm 23.11.10 설치
2. ✅ 모든 계산 노드에 Slurm 설치
3. ✅ cgroup v2 지원 설정 파일 생성
4. ✅ 모든 노드에 설정 파일 배포
5. ✅ 서비스 시작 및 검증

---

## 🔧 수동 설치 (단계별)

### Step 1: 컨트롤러에 Slurm 설치

```bash
chmod +x install_slurm_cgroup_v2.sh
sudo ./install_slurm_cgroup_v2.sh
```

**설치되는 내용:**
- Slurm 23.11.10 (cgroup v2 지원)
- 필수 의존성 (libdbus-1-dev, libsystemd-dev 등)
- 환경 변수 설정

### Step 2: 계산 노드에 Slurm 설치

```bash
# node001
scp install_slurm_cgroup_v2.sh koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"

# node002
scp install_slurm_cgroup_v2.sh koopark@192.168.122.103:/tmp/
ssh koopark@192.168.122.103 "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"
```

### Step 3: 설정 파일 생성

```bash
chmod +x configure_slurm_cgroup_v2.sh
sudo ./configure_slurm_cgroup_v2.sh
```

**생성되는 파일:**
- `/usr/local/slurm/etc/slurm.conf` (cgroup v2 설정 포함)
- `/usr/local/slurm/etc/cgroup.conf` (cgroup v2 최적화)
- `/etc/systemd/system/slurmctld.service`
- `/etc/systemd/system/slurmd.service`

### Step 4: 설정 파일 배포

```bash
# slurm.conf
scp /usr/local/slurm/etc/slurm.conf koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 "sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf"

# cgroup.conf
scp /usr/local/slurm/etc/cgroup.conf koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 "sudo mv /tmp/cgroup.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/cgroup.conf"

# node002도 동일하게
```

### Step 5: 서비스 시작

```bash
# 컨트롤러
sudo systemctl daemon-reload
sudo systemctl enable slurmctld
sudo systemctl start slurmctld

# 계산 노드
ssh koopark@192.168.122.90 'sudo systemctl daemon-reload && sudo systemctl enable slurmd && sudo systemctl start slurmd'
ssh koopark@192.168.122.103 'sudo systemctl daemon-reload && sudo systemctl enable slurmd && sudo systemctl start slurmd'
```

---

## 🧪 설치 확인

### 1. 서비스 상태 확인

```bash
# 컨트롤러
sudo systemctl status slurmctld

# 계산 노드
ssh 192.168.122.90 'sudo systemctl status slurmd'
ssh 192.168.122.103 'sudo systemctl status slurmd'
```

### 2. 클러스터 상태 확인

```bash
# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

# 노드 상태
sinfo
sinfo -N

# 노드가 DOWN이면 활성화
scontrol update NodeName=node001 State=RESUME
scontrol update NodeName=node002 State=RESUME
```

### 3. cgroup v2 작동 확인

```bash
# cgroup v2 마운트 확인
mount | grep cgroup2

# 결과 예시:
# cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)

# systemd cgroup 컨트롤러 확인
cat /sys/fs/cgroup/cgroup.controllers

# 결과 예시:
# cpuset cpu io memory pids
```

### 4. 테스트 Job 제출

```bash
cat > test_cgroup.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=cgroup_test
#SBATCH --output=cgroup_test_%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=1G

echo "==================================="
echo "cgroup v2 Test Job"
echo "==================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "CPUs allocated: $SLURM_CPUS_PER_TASK"
echo "Memory allocated: $SLURM_MEM_PER_NODE MB"
echo ""

# cgroup 경로 확인
echo "cgroup path:"
cat /proc/self/cgroup

echo ""
echo "CPU controller:"
cat /sys/fs/cgroup/$(cat /proc/self/cgroup | cut -d: -f3)/cpu.max 2>/dev/null || echo "N/A"

echo ""
echo "Memory limit:"
cat /sys/fs/cgroup/$(cat /proc/self/cgroup | cut -d: -f3)/memory.max 2>/dev/null || echo "N/A"

echo ""
echo "Test completed!"
EOF

sbatch test_cgroup.sh
squeue
```

---

## 🔬 고급 테스트

### 메모리 제한 테스트

```bash
cat > mem_limit_test.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=mem_limit
#SBATCH --output=mem_limit_%j.out
#SBATCH --mem=512M

echo "Attempting to allocate 1GB memory (limit: 512MB)..."
python3 -c 'x = [0] * (1024**3 // 8); import time; time.sleep(10)'
echo "This line should not be reached if cgroup is working"
EOF

sbatch mem_limit_test.sh

# Job이 메모리 초과로 종료되어야 함
# sacct -j <JOB_ID> --format=JobID,State,ExitCode
```

### CPU 제한 테스트

```bash
cat > cpu_limit_test.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=cpu_limit
#SBATCH --output=cpu_limit_%j.out
#SBATCH --cpus-per-task=2

echo "CPUs allocated: $SLURM_CPUS_PER_TASK"
echo "Running CPU-intensive task on 2 cores..."

# stress-ng로 CPU 부하 테스트 (2개 코어만 사용해야 함)
stress-ng --cpu $SLURM_CPUS_PER_TASK --timeout 30s --metrics

# 실제 사용된 CPU 확인
echo ""
echo "Task completed"
EOF

sbatch cpu_limit_test.sh
```

---

## 📊 Dashboard 연동

### Production 모드로 실행

```bash
cd dashboard/backend

# Production 모드 활성화
export MOCK_MODE=false

# Backend 시작
python app.py
```

### Frontend 시작

```bash
cd dashboard
npm run dev
```

### Slurm 노드 동기화

1. 브라우저에서 `http://localhost:3000` 접속
2. "Save/Load" 버튼 클릭
3. "Sync Nodes from Slurm" 클릭
4. 실제 Slurm 노드가 대시보드에 표시됨
5. cgroup을 통한 실시간 리소스 사용량 모니터링 가능

---

## 🐛 문제 해결

### Q1: slurmd가 여전히 cgroup v2 플러그인을 찾지 못해요

```bash
# Slurm이 systemd 지원으로 컴파일되었는지 확인
/usr/local/slurm/sbin/slurmd -V | grep systemd

# 출력 예시:
# --with-systemd

# 없으면 재컴파일 필요
```

### Q2: cgroup v2가 마운트되어 있지 않아요

```bash
# cgroup v2 마운트 확인
mount | grep cgroup2

# 없으면 시스템이 cgroup v1 사용 중
# Ubuntu 22.04는 기본적으로 v2를 사용하므로 확인 필요

# 강제로 cgroup v2 활성화 (재부팅 필요)
sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"/' /etc/default/grub
sudo update-grub
sudo reboot
```

### Q3: Job이 메모리 제한을 무시해요

```bash
# cgroup.conf 확인
cat /usr/local/slurm/etc/cgroup.conf

# ConstrainRAMSpace=yes 인지 확인
# MemoryLimitEnforce=yes 인지 확인

# slurmd 로그 확인
tail -f /var/log/slurm/slurmd.log
```

### Q4: 하드웨어 설정 오류가 발생해요

```bash
# 실제 하드웨어 확인
lscpu | grep -E "CPU\(s\)|Thread|Core|Socket"

# slurm.conf의 노드 설정과 일치시키기
sudo vim /usr/local/slurm/etc/slurm.conf

# 예시:
# CPUs=4 Sockets=4 CoresPerSocket=1 ThreadsPerCore=1
```

---

## 📚 참고 자료

- [Slurm cgroup Guide](https://slurm.schedmd.com/cgroup.html)
- [cgroup v2 Documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
- [Slurm 23.11 Release Notes](https://slurm.schedmd.com/news.html)
- [Dashboard Integration Guide](dashboard/SLURM_INTEGRATION_GUIDE.md)

---

## ✅ 체크리스트

설치 전:
- [ ] Ubuntu 22.04 이상
- [ ] Munge 설치 및 작동 확인
- [ ] SSH 키 설정 완료
- [ ] cgroup v2 마운트 확인

설치 후:
- [ ] slurmctld 서비스 정상 작동
- [ ] slurmd 서비스 정상 작동 (모든 노드)
- [ ] sinfo 명령으로 노드 확인
- [ ] 테스트 Job 제출 성공
- [ ] cgroup 리소스 제한 작동 확인

---

**cgroup v2로 완벽한 리소스 제어를 경험하세요! 🚀**

마지막 업데이트: 2025-10-07
버전: 1.0.0
