# Slurm 23.11.x + cgroup v2 완전 업그레이드 가이드

## 🎯 목표

**현재 상태**: Slurm 22.05.8 (cgroup v2 미지원)  
**목표 상태**: Slurm 23.11.10 (cgroup v2 완전 지원)

## ⚠️ 중요: 왜 업그레이드가 필요한가?

### 발견된 문제
```
fatal: Could not open/read/parse cgroup.conf file
error: The option "CgroupAutomount" is defunct
error: Parsing error at unrecognized key: TaskAffinity
error: Parsing error at unrecognized key: MemoryLimitEnforce
```

### 원인
- **Slurm 22.05.8**은 cgroup v2 지원이 제한적입니다
- cgroup v2 전용 옵션들이 인식되지 않습니다
- systemd 통합이 불완전합니다

### 해결책
- **Slurm 23.11.x**로 업그레이드 (cgroup v2 완전 지원)
- systemd와 완전 통합
- 실제 리소스 제한 기능 활성화

---

## 🚀 업그레이드 방법

### 방법 1: 자동 업그레이드 (권장)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomation

# 실행 권한 부여
chmod +x upgrade_to_slurm2311_cgroupv2.sh

# 업그레이드 실행
./upgrade_to_slurm2311_cgroupv2.sh
```

**이 스크립트가 하는 일:**
1. ✅ 기존 서비스 중지 및 백업
2. ✅ 컨트롤러에 Slurm 23.11.10 설치
3. ✅ 모든 계산 노드에 Slurm 23.11.10 설치
4. ✅ slurm.conf 생성 (23.11.x 버전)
5. ✅ cgroup.conf 생성 (23.11.x 호환)
6. ✅ systemd 서비스 파일 생성
7. ✅ 설정 파일 배포
8. ✅ 모든 서비스 시작

**예상 소요 시간:** 약 30-40분

---

### 방법 2: 수동 단계별 업그레이드

#### Step 1: 기존 서비스 중지
```bash
# 컨트롤러
sudo systemctl stop slurmctld

# 계산 노드
ssh koopark@192.168.122.90 "sudo systemctl stop slurmd"
ssh koopark@192.168.122.103 "sudo systemctl stop slurmd"
```

#### Step 2: 컨트롤러에 Slurm 23.11.10 설치
```bash
chmod +x install_slurm_cgroup_v2.sh
sudo ./install_slurm_cgroup_v2.sh
```

#### Step 3: 계산 노드에 Slurm 23.11.10 설치
```bash
scp install_slurm_cgroup_v2.sh koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"

scp install_slurm_cgroup_v2.sh koopark@192.168.122.103:/tmp/
ssh koopark@192.168.122.103 "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"
```

#### Step 4: 설정 파일 생성
```bash
chmod +x configure_slurm_cgroup_v2.sh
sudo ./configure_slurm_cgroup_v2.sh
```

#### Step 5: 설정 배포
```bash
# node001
scp /usr/local/slurm/etc/slurm.conf koopark@192.168.122.90:/tmp/
scp /usr/local/slurm/etc/cgroup.conf koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 "sudo mv /tmp/*.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/*.conf"

# node002
scp /usr/local/slurm/etc/slurm.conf koopark@192.168.122.103:/tmp/
scp /usr/local/slurm/etc/cgroup.conf koopark@192.168.122.103:/tmp/
ssh koopark@192.168.122.103 "sudo mv /tmp/*.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/*.conf"
```

#### Step 6: 서비스 시작
```bash
# 계산 노드 먼저
ssh koopark@192.168.122.90 "sudo systemctl start slurmd"
ssh koopark@192.168.122.103 "sudo systemctl start slurmd"

# 컨트롤러
sudo systemctl start slurmctld
```

---

## 📊 Slurm 22.05.8 vs 23.11.x 비교

| 기능 | Slurm 22.05.8 | Slurm 23.11.x |
|------|---------------|---------------|
| cgroup v2 지원 | ⚠️ 제한적 | ✅ 완전 지원 |
| systemd 통합 | ⚠️ 부분적 | ✅ 완전 통합 |
| CPU 제한 | ⚠️ 제한적 | ✅ 완전 작동 |
| 메모리 제한 | ⚠️ 제한적 | ✅ 완전 작동 |
| CgroupAutomount | ❌ defunct | ✅ 자동 처리 |
| TaskAffinity (cgroup.conf) | ❌ 미지원 | ✅ 자동 처리 |
| MemoryLimitEnforce | ❌ 미지원 | ✅ 자동 처리 |

---

## 🔧 주요 설정 변경사항

### slurm.conf
```diff
# Slurm 22.05.8
- 버전: 22.05.8
- AuthType=auth/munge
# (CryptoType 없음)

# Slurm 23.11.x
+ 버전: 23.11.10
+ AuthType=auth/munge
+ CredType=cred/munge
+ SlurmUser=slurm
+ SlurmdUser=root
+ SlurmctldPidFile=/run/slurmctld.pid
+ SlurmdPidFile=/run/slurmd.pid
```

### cgroup.conf
```diff
# Slurm 22.05.8
- CgroupAutomount=yes      # defunct!
- TaskAffinity=yes          # 미지원!
- MemorySwappiness=0        # 미지원!
- MemoryLimitEnforce=yes    # 미지원!

# Slurm 23.11.x
+ ConstrainCores=yes
+ ConstrainRAMSpace=yes
+ ConstrainSwapSpace=no
+ ConstrainDevices=no
+ AllowedRAMSpace=100
+ AllowedSwapSpace=0
# systemd가 cgroup v2를 자동 관리
```

---

## ✅ 업그레이드 후 확인사항

### 1. 버전 확인
```bash
/usr/local/slurm/sbin/slurmctld -V
# 출력: slurm 23.11.10
```

### 2. cgroup v2 마운트 확인
```bash
mount | grep cgroup2
# 출력: cgroup2 on /sys/fs/cgroup type cgroup2 ...
```

### 3. 클러스터 상태 확인
```bash
export PATH=/usr/local/slurm/bin:$PATH
sinfo
```

예상 출력:
```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
normal*      up 7-00:00:00      2   idle node[001-002]
debug        up   30:00:00      1   idle node001
```

### 4. 노드 활성화 (DOWN 상태인 경우)
```bash
scontrol update NodeName=node001 State=RESUME
scontrol update NodeName=node002 State=RESUME
```

### 5. cgroup v2 테스트
```bash
cat > test_cgroup.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=cgroupv2_test
#SBATCH --output=test_%j.out
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M

echo "Testing cgroup v2..."
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "Memory: $SLURM_MEM_PER_NODE MB"
cat /proc/self/cgroup
EOF

sbatch test_cgroup.sh
squeue
```

---

## 🐛 트러블슈팅

### Q1: slurmctld가 여전히 시작되지 않음
```bash
# 실시간 디버그
./debug_slurmctld_realtime.sh

# 또는 로그 확인
sudo journalctl -u slurmctld -f
```

### Q2: slurmd가 계산 노드에서 실패
```bash
# 노드에서 직접 확인
ssh node001
sudo journalctl -u slurmd -n 50

# 설정 파일 확인
ls -l /usr/local/slurm/etc/slurm.conf
```

### Q3: cgroup v2가 작동하지 않음
```bash
# cgroup v2 마운트 확인
mount | grep cgroup2

# 만약 cgroup v1을 사용 중이면
sudo vim /etc/default/grub
# GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"
sudo update-grub
sudo reboot
```

### Q4: 노드가 DOWN 상태
```bash
# 노드 로그 확인
scontrol show node node001

# 강제 활성화
scontrol update NodeName=node001 State=RESUME
```

---

## 📚 참고 문서

- [Slurm 23.11 Release Notes](https://slurm.schedmd.com/archive/slurm-23.11.0/news.html)
- [Slurm cgroup Guide](https://slurm.schedmd.com/cgroup.html)
- [cgroup v2 Documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

---

## 🎉 완료 후 기대 효과

✅ **실제 CPU 제한** - Job이 할당된 CPU만 사용  
✅ **실제 메모리 제한** - 초과 시 자동 종료  
✅ **CPU 친화성** - 특정 코어에 고정 가능  
✅ **실시간 모니터링** - Dashboard 연동  
✅ **안정적인 운영** - systemd 완전 통합

---

## 📞 도움말

문제가 발생하면:
1. `./quick_diagnose.sh` 실행
2. `./debug_slurmctld_realtime.sh` 실행
3. 로그 확인: `sudo journalctl -u slurmctld -f`

---

**마지막 업데이트**: 2025-10-07  
**작성자**: Claude AI Assistant
