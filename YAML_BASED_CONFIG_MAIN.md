# YAML 기반 Slurm 설정 - 메인 가이드

## 🎯 핵심 요약

**문제**: `configure_slurm_cgroup_v2.sh`가 하드코딩되어 `my_cluster.yaml`의 `reboot_program` 설정이 반영되지 않음

**해결**: YAML 기반 Python 스크립트로 모든 설정을 동적으로 생성

---

## ❓ 자주 묻는 질문

### Q1: setup_cluster_full.sh는 이제 안 쓰나요?

**A: 아닙니다! 여전히 메인 설치 스크립트입니다.**

- `setup_cluster_full.sh`의 11단계 중 **Step 8만** YAML 기반으로 개선
- 나머지 10개 단계는 **그대로 유지**
- 전체 기능 **모두 포함**

### Q2: patch_setup_cluster_full.sh는 언제 실행하나요?

**A: 딱 한 번만 실행하면 됩니다.**

```bash
./patch_setup_cluster_full.sh  # 최초 1회만
```

- 실행하면 `setup_cluster_full.sh` 파일이 **수정**됨
- Step 8이 YAML 기반으로 변경됨
- 백업 파일 자동 생성 (`.backup_날짜시간`)

### Q3: 모든 기능이 포함되어 있나요?

**A: 네! 모든 기능이 그대로 있습니다.**

| 단계 | 기능 | 변경 여부 |
|------|------|----------|
| Step 1-7 | YAML검증, SSH테스트, Munge, Slurm설치 | ✅ 변경 없음 |
| **Step 8** | **설정 파일 생성** | **⭐ YAML 기반으로 개선** |
| Step 9-12 | 설정배포, 서비스시작, PATH, MPI | ✅ 변경 없음 |

---

## 📊 Step 8 개선 내용

### ❌ 이전 (configure_slurm_cgroup_v2.sh)
```bash
# 하드코딩
ClusterName=mini-cluster
SlurmctldHost=smarttwincluster(192.168.122.1)
NodeName=node001 NodeAddr=192.168.122.90 CPUs=2 ...
# RebootProgram 설정 없음!
```

### ✅ 현재 (configure_slurm_from_yaml.py)
```yaml
# my_cluster.yaml에서 읽음
cluster_info:
  cluster_name: mini-cluster

slurm_config:
  reboot_program: /sbin/reboot  # ← 자동 반영!

nodes:
  compute_nodes:  # ← 동적 생성!
    - hostname: node001
```

---

## 🚀 사용 방법

### 방법 1: 새로운 클러스터 전체 설치

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 1. 패치 적용 (최초 1회만)
./patch_setup_cluster_full.sh

# 2. 전체 설치
./setup_cluster_full.sh

# ✅ 완료! Step 8에서 자동으로 YAML 기반 설정 사용
```

### 방법 2: 설정만 변경 (기존 클러스터)

```bash
# 1. YAML 수정
vim my_cluster.yaml

# 2. 설정 재생성
python3 configure_slurm_from_yaml.py

# 3. 배포 및 재시작
./sync_config_to_nodes.sh
sudo systemctl restart slurmctld

# ✅ 완료!
```

### 방법 3: 빠른 시작

```bash
# 올인원 스크립트
./quickstart_yaml_config.sh
```

---

## 📁 생성된 파일 목록

### 실행 파일 (10개)

1. **`configure_slurm_from_yaml.py`** ⭐
   - 메인 Python 스크립트
   - YAML → Slurm 설정 파일 변환
   - RebootProgram 자동 반영

2. `quickstart_yaml_config.sh`
   - 빠른 시작 (대화형)

3. `setup_yaml_all_in_one.sh`
   - 올인원 메뉴

4. `configure_slurm_cgroup_v2_YAML.sh`
   - Bash 래퍼

5. `patch_setup_cluster_full.sh`
   - setup_cluster_full.sh 패치

6. `FINAL_SETUP_YAML.sh`
   - 최초 설정

7. `YAML_CONFIG_SUMMARY.sh`
   - 요약 정보

8. `FAQ_YAML_CONFIG.sh`
   - FAQ 표시

9. `SHOW_FAQ.sh`
   - FAQ + 권한 부여

10. `chmod_yaml_scripts.sh`
    - 권한 일괄 부여

### 문서 (3개)

11. `YAML_CONFIG_GUIDE.md`
    - 완전한 사용 가이드

12. `YAML_CONFIG_README.md`
    - 빠른 참조

13. `SETUP_CLUSTER_FULL_INTEGRATION.md`
    - setup_cluster_full.sh 통합 가이드

---

## 🎯 YAML → slurm.conf 변환 예시

### Input: my_cluster.yaml
```yaml
cluster_info:
  cluster_name: mini-cluster

nodes:
  controller:
    hostname: smarttwincluster
    ip_address: 192.168.122.1
  
  compute_nodes:
    - hostname: node001
      ip_address: 192.168.122.90
      hardware:
        cpus: 2
        sockets: 1
        cores_per_socket: 2
        memory_mb: 4096

slurm_config:
  reboot_program: /sbin/reboot  # ⭐ 핵심!
  
  partitions:
    - name: normal
      nodes: node[001-002]
      default: true
      max_time: 7-00:00:00
```

### Output: /usr/local/slurm/etc/slurm.conf
```conf
ClusterName=mini-cluster
SlurmctldHost=smarttwincluster(192.168.122.1)

SlurmUser=slurm
SlurmdUser=root

AuthType=auth/munge
CredType=cred/munge

# ⭐ YAML에서 자동으로 읽어옴!
RebootProgram=/sbin/reboot

SchedulerType=sched/backfill
SelectType=select/cons_tres
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity

# 노드 동적 생성!
NodeName=node001 NodeAddr=192.168.122.90 CPUs=2 Sockets=1 CoresPerSocket=2 ThreadsPerCore=1 RealMemory=4096 State=UNKNOWN

# 파티션 동적 생성!
PartitionName=normal Nodes=node[001-002] Default=YES MaxTime=7-00:00:00 State=UP
```

---

## 🔍 확인 방법

```bash
# 1. RebootProgram 설정 확인
grep "^RebootProgram" /usr/local/slurm/etc/slurm.conf
# 출력: RebootProgram=/sbin/reboot

# 2. scontrol로 확인
scontrol show config | grep RebootProgram
# 출력: RebootProgram         = /sbin/reboot

# 3. 전체 설정 확인
cat /usr/local/slurm/etc/slurm.conf

# 4. 노드 재부팅 테스트
scontrol reboot node001 reason="YAML config test"
```

---

## 📋 사용 시나리오

### 시나리오 1: 완전히 새로운 클러스터 설치

```bash
# 1. YAML 준비
cp examples/2node_example.yaml my_cluster.yaml
vim my_cluster.yaml

# 2. 패치 적용 (최초 1회)
./patch_setup_cluster_full.sh

# 3. 전체 설치
./setup_cluster_full.sh

# ✅ 완료!
```

### 시나리오 2: RebootProgram 변경

```yaml
# my_cluster.yaml 수정
slurm_config:
  reboot_program: /usr/local/bin/custom-reboot.sh
```

```bash
# 재생성 및 배포
python3 configure_slurm_from_yaml.py
./sync_config_to_nodes.sh
sudo systemctl restart slurmctld

# 확인
grep RebootProgram /usr/local/slurm/etc/slurm.conf
```

### 시나리오 3: 노드 추가

```yaml
# my_cluster.yaml에 노드 추가
nodes:
  compute_nodes:
    - hostname: node003
      ip_address: 192.168.122.104
      hardware:
        cpus: 4
        memory_mb: 8192
```

```bash
# 1. 새 노드에 Slurm 설치
scp install_slurm_cgroup_v2.sh koopark@192.168.122.104:/tmp/
ssh koopark@192.168.122.104 'sudo bash /tmp/install_slurm_cgroup_v2.sh'

# 2. 설정 재생성
python3 configure_slurm_from_yaml.py

# 3. 배포 및 재시작
./sync_config_to_nodes.sh
sudo systemctl restart slurmctld
ssh node003 'sudo systemctl restart slurmd'

# ✅ 완료!
```

---

## ✅ 체크리스트

### 초기 설정
- [ ] `my_cluster.yaml` 준비
- [ ] `reboot_program` 설정 확인
- [ ] `./patch_setup_cluster_full.sh` 실행 (최초 1회)
- [ ] `./setup_cluster_full.sh` 실행
- [ ] `grep RebootProgram /usr/local/slurm/etc/slurm.conf` 확인

### 설정 변경 시
- [ ] `my_cluster.yaml` 수정
- [ ] `python3 configure_slurm_from_yaml.py` 실행
- [ ] `./sync_config_to_nodes.sh` 실행
- [ ] Slurm 재시작
- [ ] `scontrol show config | grep RebootProgram` 확인

---

## 🔧 트러블슈팅

### Q: YAML 파일을 찾을 수 없다는 오류
```bash
cp examples/2node_example.yaml my_cluster.yaml
vim my_cluster.yaml
```

### Q: Permission denied 오류
```bash
sudo python3 configure_slurm_from_yaml.py
```

### Q: RebootProgram이 반영되지 않음
```bash
# YAML 확인
grep reboot_program my_cluster.yaml

# 없으면 추가
vim my_cluster.yaml
# slurm_config:
#   reboot_program: /sbin/reboot

# 재생성
python3 configure_slurm_from_yaml.py
```

---

## 📚 관련 문서

- **완전한 가이드**: `YAML_CONFIG_GUIDE.md`
- **빠른 참조**: `YAML_CONFIG_README.md`
- **통합 가이드**: `SETUP_CLUSTER_FULL_INTEGRATION.md`
- **FAQ**: `./FAQ_YAML_CONFIG.sh`

---

## 🎯 핵심 정리

1. ✅ `setup_cluster_full.sh`는 **여전히 메인 스크립트**
2. ✅ **Step 8만** YAML 기반으로 개선
3. ✅ `./patch_setup_cluster_full.sh` **한 번만** 실행
4. ✅ `RebootProgram` 자동 반영
5. ✅ YAML만 수정하면 **모든 설정 자동**

---

## 🚀 지금 바로 시작!

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# FAQ 및 사용법 보기
chmod +x SHOW_FAQ.sh
./SHOW_FAQ.sh

# 또는 빠른 시작
chmod +x quickstart_yaml_config.sh
./quickstart_yaml_config.sh
```

---

**작성일**: 2025-10-11  
**위치**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/`  
**문의**: 이 문서 또는 `YAML_CONFIG_GUIDE.md` 참조
