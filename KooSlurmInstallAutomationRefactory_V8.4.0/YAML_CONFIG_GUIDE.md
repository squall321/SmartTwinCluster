# YAML 기반 Slurm 설정 자동화

## 📋 개요

모든 Slurm 설정을 `my_cluster.yaml`에서 읽어와서 자동으로 생성합니다.
더 이상 하드코딩된 설정이 없습니다! ✨

## 🎯 주요 기능

### ✅ YAML에서 자동으로 읽어오는 항목들

1. **클러스터 정보**
   - ClusterName
   - SlurmctldHost (Controller 호스트명 및 IP)

2. **노드 재부팅**
   - ✨ **RebootProgram** (YAML의 `slurm_config.reboot_program`)

3. **계산 노드**
   - NodeName, NodeAddr (동적 생성)
   - CPUs, Sockets, CoresPerSocket, ThreadsPerCore
   - RealMemory

4. **파티션**
   - PartitionName, Nodes (동적 생성)
   - Default, MaxTime, MaxNodes, State

5. **경로 설정**
   - install_path
   - config_path
   - log_path
   - spool_path

6. **스케줄러**
   - SchedulerType
   - Accounting 설정

## 📂 생성되는 파일

```
/usr/local/slurm/etc/
├── slurm.conf      ← YAML 기반 동적 생성
└── cgroup.conf     ← YAML 기반 동적 생성

/etc/systemd/system/
├── slurmctld.service  ← YAML 경로 사용
└── slurmd.service     ← YAML 경로 사용

/etc/tmpfiles.d/
└── slurm.conf
```

## 🚀 사용 방법

### 방법 1: Python 스크립트 직접 실행 (권장)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 1. 실행 권한 부여
chmod +x configure_slurm_from_yaml.py

# 2. 미리보기 (설정 확인만)
python3 configure_slurm_from_yaml.py --dry-run

# 3. 실제 생성
python3 configure_slurm_from_yaml.py

# 4. 다른 YAML 파일 사용
python3 configure_slurm_from_yaml.py -c custom_cluster.yaml
```

### 방법 2: Bash 래퍼 스크립트 사용

```bash
chmod +x configure_slurm_cgroup_v2_YAML.sh
./configure_slurm_cgroup_v2_YAML.sh
```

### 방법 3: setup_cluster_full.sh에 통합

```bash
# setup_cluster_full.sh 패치 (Step 8을 YAML 기반으로 변경)
chmod +x patch_setup_cluster_full.sh
./patch_setup_cluster_full.sh

# 전체 설치 실행
./setup_cluster_full.sh
```

## 📝 설정 예시 (my_cluster.yaml)

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
        threads_per_core: 1
        memory_mb: 4096

slurm_config:
  version: 22.05.8
  install_path: /usr/local/slurm
  config_path: /usr/local/slurm/etc
  log_path: /var/log/slurm
  
  # ✨ 중요: RebootProgram 설정
  reboot_program: /sbin/reboot
  
  scheduler:
    type: sched/backfill
  
  accounting:
    storage_type: accounting_storage/none
  
  partitions:
    - name: normal
      nodes: node[1-2]
      default: true
      max_time: 7-00:00:00
```

## 🔍 생성된 설정 확인

```bash
# 1. slurm.conf 확인
cat /usr/local/slurm/etc/slurm.conf

# 2. RebootProgram 설정 확인
grep "^RebootProgram" /usr/local/slurm/etc/slurm.conf

# 예상 출력:
# RebootProgram=/sbin/reboot

# 3. 노드 설정 확인
grep "^NodeName" /usr/local/slurm/etc/slurm.conf

# 4. 파티션 설정 확인
grep "^PartitionName" /usr/local/slurm/etc/slurm.conf

# 5. scontrol로 확인
scontrol show config | grep RebootProgram
```

## 📤 계산 노드에 배포

```bash
# 자동으로 생성된 노드 정보를 사용하여 배포

# node001
scp /usr/local/slurm/etc/slurm.conf koopark@192.168.122.90:/tmp/
ssh koopark@192.168.122.90 'sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf'

# node002
scp /usr/local/slurm/etc/slurm.conf koopark@192.168.122.103:/tmp/
ssh koopark@192.168.122.103 'sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf'
```

또는 자동 배포 스크립트:

```bash
# sync_config_to_nodes.sh를 사용 (이미 존재)
./sync_config_to_nodes.sh
```

## 🔄 Slurm 재시작

```bash
# 컨트롤러
sudo systemctl restart slurmctld

# 계산 노드
ssh koopark@192.168.122.90 'sudo systemctl restart slurmd'
ssh koopark@192.168.122.103 'sudo systemctl restart slurmd'
```

## ✅ 장점

### ❌ 이전 (configure_slurm_cgroup_v2.sh)
- 하드코딩된 노드 정보
- 하드코딩된 IP 주소
- RebootProgram 설정 없음
- YAML 변경해도 반영 안됨

### ✅ 현재 (configure_slurm_from_yaml.py)
- 모든 설정을 YAML에서 읽음
- 노드 추가/제거가 YAML만 수정하면 됨
- RebootProgram 자동 반영
- 파티션도 동적 생성
- 확장 가능한 구조

## 🧪 테스트

```bash
# 1. DRY RUN으로 미리보기
python3 configure_slurm_from_yaml.py --dry-run

# 2. 실제 생성
sudo python3 configure_slurm_from_yaml.py

# 3. RebootProgram 확인
grep RebootProgram /usr/local/slurm/etc/slurm.conf

# 4. 노드 재부팅 테스트 (주의!)
scontrol reboot node001 reason="yaml config test"
```

## 📋 트러블슈팅

### Q: YAML 파일을 찾을 수 없다는 오류
```bash
# A: my_cluster.yaml 파일이 있는지 확인
ls -l my_cluster.yaml

# 없으면 생성
cp examples/2node_example.yaml my_cluster.yaml
vim my_cluster.yaml
```

### Q: Permission denied 오류
```bash
# A: sudo로 실행
sudo python3 configure_slurm_from_yaml.py
```

### Q: slurm 사용자가 없다는 오류
```bash
# A: slurm 사용자 생성
sudo groupadd -g 1001 slurm
sudo useradd -u 1001 -g 1001 -m -s /bin/bash slurm
```

### Q: RebootProgram이 반영되지 않음
```bash
# A: YAML 파일 확인
grep reboot_program my_cluster.yaml

# 없으면 추가
# slurm_config:
#   reboot_program: /sbin/reboot

# 다시 생성
python3 configure_slurm_from_yaml.py
```

## 🎯 핵심 요약

1. **모든 설정은 my_cluster.yaml에서!**
2. **더 이상 스크립트 수정 필요 없음**
3. **RebootProgram 자동 반영**
4. **노드/파티션 동적 생성**

## 📚 관련 파일

- `configure_slurm_from_yaml.py` - 메인 Python 스크립트
- `configure_slurm_cgroup_v2_YAML.sh` - Bash 래퍼
- `my_cluster.yaml` - 설정 파일
- `patch_setup_cluster_full.sh` - setup_cluster_full.sh 업데이트

---

**마지막 업데이트:** 2025-10-11
