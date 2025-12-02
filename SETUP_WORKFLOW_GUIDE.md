# 📘 Slurm 클러스터 초기 셋업 가이드 - my_cluster.yaml 사용

## 🎯 목적

`my_cluster.yaml` 설정 파일을 사용하여 Slurm 클러스터를 처음부터 설치하는 완전한 가이드

---

## 📋 진입점 및 실행 순서

### 🔷 방법 1: 권장 방법 (완전 자동화)

**진입점**: `setup_cluster_full.sh`

```bash
# 1. 프로젝트 디렉토리로 이동
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 2. 설정 파일 준비
vim my_cluster.yaml  # IP 주소와 호스트명 수정
# reboot_program: /sbin/reboot 확인

# 3. 실행 권한 설정
chmod +x setup_cluster_full.sh

# 4. 완전 자동 설치 실행
./setup_cluster_full.sh
```

**처리 과정**:
1. `my_cluster.yaml` 검증
2. SSH 연결 확인
3. 필수 패키지 설치
4. Munge 설정
5. Slurm 컴파일 및 설치
6. **slurm.conf 생성** (← `RebootProgram` 여기서 추가됨!)
7. cgroup v2 설정
8. 서비스 시작

---

### 🔷 방법 2: Python 스크립트 (모듈식)

**진입점**: `install_slurm.py`

```bash
# 1. 가상환경 설정
./setup.sh
source venv/bin/activate

# 2. 설정 파일 준비
vim my_cluster.yaml

# 3. 검증
./validate_config.py my_cluster.yaml

# 4. SSH 연결 테스트
./test_connection.py my_cluster.yaml

# 5. 설치 실행 (단계별)
./install_slurm.py -c my_cluster.yaml --stage 1  # 기본 설치
./install_slurm.py -c my_cluster.yaml --stage 2  # 고급 기능
./install_slurm.py -c my_cluster.yaml --stage 3  # 최적화

# 또는 한 번에
./install_slurm.py -c my_cluster.yaml --stage all
```

---

### 🔷 방법 3: 단계별 수동 설치

**진입점**: 여러 스크립트 조합

```bash
# Step 1: 환경 설정
./setup.sh
source venv/bin/activate

# Step 2: SSH 키 설정
./setup_ssh_keys.sh

# Step 3: 설정 파일 검증
python3 validate_config.py my_cluster.yaml

# Step 4: 완전 자동 설정 실행
python3 complete_slurm_setup.py
```

**`complete_slurm_setup.py`가 하는 일**:
```python
# my_cluster.yaml 로드
config = yaml.safe_load(open('my_cluster.yaml'))

# slurm.conf 생성
reboot_program = config['slurm_config'].get('reboot_program', '/sbin/reboot')
# ↑ 여기서 RebootProgram이 slurm.conf에 추가됨!
```

---

## 📂 핵심 파일 구조

```
KooSlurmInstallAutomationRefactory/
│
├── my_cluster.yaml              # ← 메인 설정 파일 (사용자가 수정)
│   └── slurm_config:
│       └── reboot_program: /sbin/reboot
│
├── setup_cluster_full.sh        # ← 진입점 1: 완전 자동화 스크립트
├── install_slurm.py             # ← 진입점 2: Python 메인 스크립트
├── complete_slurm_setup.py      # ← 핵심: slurm.conf 생성 스크립트
│   └── generate_slurm_conf()    # ← RebootProgram 추가되는 함수
│
├── templates/                   # YAML 템플릿들
│   ├── complete_template.yaml
│   ├── stage1_basic.yaml
│   └── ...
│
└── examples/                    # 예제 설정
    ├── 2node_example.yaml
    └── 4node_research_cluster.yaml
```

---

## 🔄 실행 흐름도

```
사용자
  │
  ├─ my_cluster.yaml 작성/수정
  │   └─ reboot_program: /sbin/reboot 설정
  │
  ├─ 방법 선택
  │
  ├─── [방법 1] ./setup_cluster_full.sh
  │       │
  │       ├─ 설정 검증
  │       ├─ SSH 테스트
  │       ├─ Step 4.3: complete_slurm_setup.py 호출 ──┐
  │       │   (--skip-munge --skip-slurm-conf --skip-cgroup --skip-nfs)
  │       │   → /etc/hosts 설정, SSH 키, 방화벽, SELinux, NTP 등
  │       ├─ Slurm 컴파일
  │       └─ ...                                       │
  │                                                    │
  ├─── [방법 2] ./install_slurm.py                    │
  │       (complete_slurm_setup.py 호출 안함)         │
  │                                                    │
  └─── [방법 3] python3 complete_slurm_setup.py       │
                (수동 실행 - 모든 단계 포함)          │
                                             │
                                             ▼
                            generate_slurm_conf() 함수
                                             │
                    ┌────────────────────────┴────────────────────────┐
                    │                                                 │
                    │  # my_cluster.yaml에서 읽기                     │
                    │  reboot_program = config['slurm_config']        │
                    │                    .get('reboot_program',       │
                    │                         '/sbin/reboot')         │
                    │                                                 │
                    │  # slurm.conf에 추가                            │
                    │  RebootProgram=/sbin/reboot                     │
                    │                                                 │
                    └─────────────────────────────────────────────────┘
                                             │
                                             ▼
                                  /usr/local/slurm/etc/slurm.conf
                                             │
                                             ▼
                                    모든 노드에 배포
                                             │
                                             ▼
                                        설치 완료!
```

---

## ✅ 실행 순서 체크리스트

### □ 1. 초기 준비
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
chmod +x chmod_all.sh
./chmod_all.sh
```

### □ 2. 설정 파일 준비
```bash
# 예제에서 복사
cp examples/2node_example.yaml my_cluster.yaml

# 또는 직접 수정
vim my_cluster.yaml
```

**필수 수정 항목**:
- [ ] `cluster_info.cluster_name`
- [ ] `nodes.controller.hostname`
- [ ] `nodes.controller.ip_address`
- [ ] `nodes.compute_nodes[].hostname`
- [ ] `nodes.compute_nodes[].ip_address`
- [ ] `slurm_config.reboot_program` ← **중요!**

### □ 3. 검증
```bash
# 설정 파일 검증
./validate_config.py my_cluster.yaml

# SSH 연결 테스트
./test_connection.py my_cluster.yaml
```

### □ 4. 설치 방법 선택

**옵션 A: 한 번에 자동 설치 (권장)**
```bash
./setup_cluster_full.sh
```

**옵션 B: Python 스크립트**
```bash
./setup.sh
source venv/bin/activate
./install_slurm.py -c my_cluster.yaml --stage all
```

**옵션 C: 단계별 설치**
```bash
./setup.sh
source venv/bin/activate
./install_slurm.py -c my_cluster.yaml --stage 1
# 검증
./install_slurm.py -c my_cluster.yaml --stage 2
# 검증
./install_slurm.py -c my_cluster.yaml --stage 3
```

### □ 5. 설치 완료 확인
```bash
# Slurm 명령어 경로 확인
which sinfo
which sbatch

# 클러스터 상태 확인
sinfo
sinfo -N

# slurm.conf에서 RebootProgram 확인
grep RebootProgram /usr/local/slurm/etc/slurm.conf
# 출력: RebootProgram=/sbin/reboot

# 테스트
scontrol show config | grep RebootProgram
```

### □ 6. Reboot 기능 테스트
```bash
# Backend Dashboard에서 테스트
# 또는 CLI로:
scontrol reboot node001 reason="test"
```

---

## 🎯 각 스크립트의 역할

| 스크립트 | 역할 | my_cluster.yaml 사용 |
|----------|------|---------------------|
| `setup.sh` | Python 가상환경 설정 | ❌ |
| `chmod_all.sh` | 실행 권한 일괄 부여 | ❌ |
| `validate_config.py` | 설정 파일 검증 | ✅ |
| `test_connection.py` | SSH 연결 테스트 | ✅ |
| `install_slurm.py` | **메인 진입점** | ✅ |
| `complete_slurm_setup.py` | **slurm.conf 생성** | ✅ |
| `setup_cluster_full.sh` | **완전 자동화 진입점** | ✅ |

---

## 💡 핵심 포인트

### 1. `my_cluster.yaml`이 모든 것의 중심
```yaml
slurm_config:
  reboot_program: /sbin/reboot  # ← 이 설정이 핵심!
```

### 2. `complete_slurm_setup.py`가 실제로 적용
```python
def generate_slurm_conf(self):
    reboot_program = self.config['slurm_config'].get('reboot_program', '/sbin/reboot')
    slurm_conf = f"""
    ...
    RebootProgram={reboot_program}
    ...
    """
```

### 3. 자동 배포
- 컨트롤러에 생성
- 모든 계산 노드에 자동 복사
- 권한 설정 자동화

---

## 🔧 문제 해결

### RebootProgram이 slurm.conf에 없는 경우

**원인**: 이전 버전의 설정 파일 사용

**해결**:
```bash
# 1. my_cluster.yaml에 추가
vim my_cluster.yaml
# slurm_config 섹션에 추가:
#   reboot_program: /sbin/reboot

# 2. slurm.conf 재생성
python3 complete_slurm_setup.py

# 3. 또는 수동으로 추가
sudo vim /usr/local/slurm/etc/slurm.conf
# 추가:
# RebootProgram=/sbin/reboot

# 4. Slurm 재시작
sudo systemctl restart slurmctld
```

---

## 📚 참고 문서

- **시작 가이드**: `START_HERE.md`
- **빠른 시작**: `QUICKSTART.md`
- **전체 문서**: `README.md`
- **Reboot 설정**: `REBOOT_PROGRAM_GUIDE.md`
- **설정 템플릿**: `templates/complete_template.yaml`

---

**작성일**: 2025-10-10  
**버전**: 1.0  
**작성자**: KooSlurmInstallAutomation
