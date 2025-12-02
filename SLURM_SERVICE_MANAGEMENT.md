# Slurm 서비스 관리 가이드

## 📋 개요

이 문서는 Slurm 클러스터의 모든 서비스를 쉽게 시작하고 정지할 수 있는 스크립트 사용법을 설명합니다.

## 🚀 스크립트

### 1. start_slurm_services.sh
모든 Slurm 관련 서비스를 올바른 순서로 시작합니다.

### 2. stop_slurm_services.sh
모든 Slurm 관련 서비스를 올바른 순서로 정지합니다.

## 📦 관리되는 서비스

### Controller 노드 (smarttwincluster):
1. **Munge** - 인증 서비스 (모든 노드에서 가장 먼저 시작)
2. **MariaDB** - 데이터베이스 (slurmdbd 사용 시)
3. **slurmdbd** - Slurm 데이터베이스 데몬 (accounting 사용 시)
4. **slurmctld** - Slurm 컨트롤러 데몬

### Compute 노드 (node001, node002, viz-node001):
1. **Munge** - 인증 서비스
2. **slurmd** - Slurm 컴퓨트 데몬

## 🔧 사용법

### 서비스 시작

```bash
./start_slurm_services.sh
```

**실행 순서:**
1. Munge (Controller + 모든 Compute 노드)
2. MariaDB (Controller, 있을 경우)
3. slurmdbd (Controller, 있을 경우)
4. slurmctld (Controller)
5. slurmd (모든 Compute 노드)

**예상 출력:**
```
================================================================================
🚀 Slurm 서비스 시작
================================================================================

📋 설정 정보:
  - Controller: smarttwincluster
  - SSH User: koopark
  - Compute Nodes: 3개

1️⃣  Munge 서비스 시작...
--------------------------------------------------------------------------------
  📍 Controller: Munge 시작
    ✅ Munge 시작 완료
  📍 Compute Nodes: Munge 시작
    192.168.122.90: ✅ 시작 완료
    192.168.122.103: ✅ 시작 완료
    192.168.122.252: ✅ 시작 완료

2️⃣  MariaDB 서비스 확인...
--------------------------------------------------------------------------------
  ✅ MariaDB 시작 완료

3️⃣  slurmdbd 서비스 시작...
--------------------------------------------------------------------------------
  📍 slurmdbd 시작
  ✅ slurmdbd 시작 완료

4️⃣  slurmctld 서비스 시작...
--------------------------------------------------------------------------------
  📍 Controller: slurmctld 시작
  ✅ slurmctld 시작 완료
  ✓ 포트 6817 리스닝 확인

5️⃣  slurmd 서비스 시작 (Compute Nodes)...
--------------------------------------------------------------------------------
  ⏱️  slurmctld 준비 대기 중...
  📍 192.168.122.90: slurmd 시작
    ✅ slurmd 시작 완료
  📍 192.168.122.103: slurmd 시작
    ✅ slurmd 시작 완료
  📍 192.168.122.252: slurmd 시작
    ✅ slurmd 시작 완료

6️⃣  서비스 상태 최종 확인...
--------------------------------------------------------------------------------
  📍 Controller 서비스:
    munge: ✅ 실행 중
    slurmctld: ✅ 실행 중
    slurmdbd: ✅ 실행 중

  📍 Compute Nodes 서비스:
    192.168.122.90:
      munge: ✅ 실행 중
      slurmd: ✅ 실행 중
    ...

7️⃣  Slurm 클러스터 상태...
--------------------------------------------------------------------------------
  📊 노드 상태:
  NODELIST    NODES PARTITION STATE
  node001     1     normal    idle
  node002     1     normal    idle
  viz-node001 1     viz       idle

================================================================================
✅ Slurm 서비스 시작 완료!
================================================================================
```

### 서비스 정지

```bash
./stop_slurm_services.sh
```

**실행 순서:**
1. slurmd (모든 Compute 노드)
2. slurmctld (Controller)
3. slurmdbd (Controller, 있을 경우)
4. MariaDB (선택 사항 - 사용자 확인)
5. Munge (선택 사항 - 사용자 확인)

**사용자 입력 필요:**
```
4️⃣  MariaDB 서비스 정지 (선택 사항)...
--------------------------------------------------------------------------------
  ❓ MariaDB도 정지하시겠습니까? (y/N):
```

**권장 답변:**
- **N (기본값)**: 다른 애플리케이션이 MariaDB를 사용할 수 있으므로 유지
- **Y**: 완전 종료를 원할 경우

```
5️⃣  Munge 서비스 정지 (선택 사항)...
--------------------------------------------------------------------------------
  ❓ Munge도 정지하시겠습니까? (y/N):
```

**권장 답변:**
- **N (기본값)**: 다음 Slurm 시작 시 빠르게 사용 가능
- **Y**: 완전 종료를 원할 경우

## 🔍 문제 해결

### 서비스가 시작되지 않을 때

1. **로그 확인:**
```bash
# Controller
sudo journalctl -u slurmctld -n 50
sudo journalctl -u slurmdbd -n 50

# Compute 노드에서
sudo journalctl -u slurmd -n 50
```

2. **수동 서비스 확인:**
```bash
# Controller
sudo systemctl status slurmctld
sudo systemctl status slurmdbd
sudo systemctl status munge

# Compute 노드에서
sudo systemctl status slurmd
sudo systemctl status munge
```

3. **포트 확인:**
```bash
# Controller에서
sudo ss -tulpn | grep slurm
# 6817 (slurmctld), 6819 (slurmdbd) 확인

# Compute 노드에서
sudo ss -tulpn | grep slurm
# 6818 (slurmd) 확인
```

### SSH 연결 실패

스크립트가 Compute 노드에 SSH로 접속할 수 없을 때:

1. **SSH 키 확인:**
```bash
ssh-copy-id koopark@192.168.122.90
ssh-copy-id koopark@192.168.122.103
ssh-copy-id koopark@192.168.122.252
```

2. **수동 접속 테스트:**
```bash
ssh koopark@192.168.122.90 "hostname"
```

3. **my_cluster.yaml 확인:**
```bash
cat my_cluster.yaml | grep -A 5 compute_nodes
```

### 서비스가 정지되지 않을 때

**강제 종료:**
```bash
# Controller에서
sudo pkill -9 slurmctld
sudo pkill -9 slurmdbd

# Compute 노드에서
sudo pkill -9 slurmd
```

## 📊 상태 확인 명령어

### Slurm 클러스터 상태
```bash
# 노드 상태
sinfo -N -l

# 파티션 상태
sinfo

# 작업 큐
squeue

# 노드 상세 정보
scontrol show node node001
```

### 시스템 서비스 상태
```bash
# Controller
sudo systemctl status slurmctld slurmdbd munge

# Compute 노드에서
sudo systemctl status slurmd munge
```

### 프로세스 확인
```bash
# Controller
ps aux | grep slurm

# Compute 노드에서
ps aux | grep slurmd
```

## ⚙️ 고급 사용법

### 특정 노드만 재시작

**특정 Compute 노드의 slurmd만 재시작:**
```bash
# node001만 재시작
ssh koopark@192.168.122.90 "sudo systemctl restart slurmd"

# 상태 확인
sinfo -N | grep node001
```

### 디버그 모드로 실행

**slurmctld를 포그라운드에서 디버그 모드로 실행:**
```bash
# 기존 서비스 정지
sudo systemctl stop slurmctld

# 디버그 모드 실행
sudo /usr/local/slurm/sbin/slurmctld -D -vvv
```

**slurmd를 포그라운드에서 디버그 모드로 실행:**
```bash
# Compute 노드에서
sudo systemctl stop slurmd
sudo /usr/local/slurm/sbin/slurmd -D -vvv
```

### 설정 변경 후 재로드

**설정 파일 변경 후 slurmctld만 재로드 (다운타임 최소화):**
```bash
# slurm.conf 수정 후
sudo scontrol reconfigure

# 또는 서비스 재시작
sudo systemctl restart slurmctld
```

## 🔒 권한 요구사항

- **sudo 권한**: 모든 systemctl 명령과 프로세스 관리에 필요
- **SSH 접근**: Compute 노드에 비밀번호 없이 접속 가능해야 함
- **Python3 + PyYAML**: my_cluster.yaml 파싱에 필요

## 📝 참고사항

1. **순서 중요**: 서비스는 반드시 정해진 순서대로 시작/정지되어야 합니다.
   - 시작: Munge → MariaDB → slurmdbd → slurmctld → slurmd
   - 정지: slurmd → slurmctld → slurmdbd → MariaDB → Munge

2. **Munge 필수**: Slurm이 작동하려면 모든 노드에서 Munge가 실행 중이어야 합니다.

3. **네트워크 동기화**: 시간 동기화(NTP)가 제대로 되어 있어야 Munge 인증이 정상 작동합니다.

4. **방화벽**: 필요한 포트가 열려 있어야 합니다:
   - 6817 (slurmctld)
   - 6818 (slurmd)
   - 6819 (slurmdbd)

## 🆘 긴급 상황

### 전체 클러스터 긴급 정지
```bash
./stop_slurm_services.sh
# 모든 프롬프트에 'y' 입력

# 또는 강제 종료
sudo pkill -9 slurmctld slurmdbd slurmd
```

### 전체 클러스터 재시작
```bash
./stop_slurm_services.sh
sleep 5
./start_slurm_services.sh
```

### 로그 초기화 (문제 해결 후)
```bash
sudo rm -f /var/log/slurm/*.log
sudo systemctl restart slurmctld slurmdbd
```

## 📞 지원

문제가 지속될 경우:
1. 모든 로그 수집: `sudo journalctl -u slurm* -n 200 > slurm_logs.txt`
2. 설정 파일 확인: `/usr/local/slurm/etc/slurm.conf`
3. 네트워크 연결 확인: `ping <node>`
