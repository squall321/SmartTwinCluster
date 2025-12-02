# setup_cluster_full.sh Type=simple 전환 - 최종 실행 가이드

## 📋 전체 계획 완료!

모든 수정 계획이 완성되었습니다. 이제 실행만 하면 됩니다.

---

## 🚀 즉시 실행 (한 줄 명령어)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory && chmod +x run_complete_conversion.sh && ./run_complete_conversion.sh
```

이 명령어가 자동으로:
1. ✅ 실행 권한 부여
2. ✅ Type=notify → Type=simple 전환
3. ✅ 변경사항 검증
4. ✅ 결과 요약

---

## 📂 생성된 파일 목록

### 1. 주요 실행 스크립트

| 파일명 | 설명 | 실행 순서 |
|--------|------|-----------|
| `run_complete_conversion.sh` | **전체 자동 실행** | 1번 |
| `convert_systemd_to_simple.sh` | Type 전환 | 2번 (자동) |
| `verify_setup_cluster_full.sh` | 검증 | 3번 (자동) |

### 2. 수정 대상 파일

| 파일명 | 변경 내용 |
|--------|-----------|
| `create_slurm_systemd_services.sh` | slurmctld, slurmd → Type=simple |
| `install_slurm_accounting.sh` | slurmdbd → Type=simple |

### 3. 문서

| 문서명 | 내용 |
|--------|------|
| Artifact: "전체 분석 및 수정 계획" | 상세 분석 |
| Artifact: "Type=simple 전환 가이드" | 실행 가이드 |
| `EXECUTION_GUIDE.md` (이 파일) | 빠른 실행 가이드 |

---

## 🎯 실행 방법 (상세)

### 방법 1: 전체 자동 실행 (권장)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./run_complete_conversion.sh
```

**이 스크립트가 하는 일:**
1. 실행 권한 자동 부여
2. Type=simple 전환 실행
3. 변경사항 검증
4. 결과 요약 출력

### 방법 2: 단계별 실행

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# Step 1: 실행 권한 부여
chmod +x convert_systemd_to_simple.sh
chmod +x verify_setup_cluster_full.sh

# Step 2: Type=simple 전환
./convert_systemd_to_simple.sh

# Step 3: 검증
./verify_setup_cluster_full.sh
```

---

## ✅ 예상 결과

### 성공 시 출력

```
================================================================================
🎉 Type=simple 전환 완료!
================================================================================

✅ 모든 systemd 서비스가 Type=simple로 전환되었습니다
✅ 기능 손실 없음: 모든 기능 정상 작동
✅ 안정성 향상: 타임아웃 문제 해결

다음 단계:

1️⃣  새 클러스터 설치:
   ./setup_cluster_full.sh

2️⃣  기존 클러스터 업데이트 (선택):
   sudo ./create_slurm_systemd_services.sh
   sudo systemctl daemon-reload
   sudo systemctl restart slurmctld slurmd

3️⃣  설치 후 확인:
   systemctl show slurmctld | grep Type
   sinfo
   sacctmgr show qos  # QoS 설치 시
```

### 변경 확인

```bash
# Type=simple 확인
grep "Type=" create_slurm_systemd_services.sh
grep "Type=" install_slurm_accounting.sh

# 출력 예시:
# Type=simple
# Type=simple
# Type=simple
```

---

## 📦 백업

자동으로 백업이 생성됩니다:

```
backup_YYYYMMDD_HHMMSS_notify_to_simple/
├── create_slurm_systemd_services.sh
└── install_slurm_accounting.sh
```

### 백업 복원 방법

```bash
# 최신 백업 찾기
ls -td backup_*_notify_to_simple | head -1

# 복원
cp backup_YYYYMMDD_HHMMSS_notify_to_simple/*.sh ./
```

---

## 🔍 변경 내용 요약

### 1. create_slurm_systemd_services.sh

**Before:**
```ini
Type=notify
ExecStart=/usr/local/slurm/sbin/slurmctld -D $SLURMCTLD_OPTIONS
```

**After:**
```ini
Type=simple
ExecStart=/usr/local/slurm/sbin/slurmctld $SLURMCTLD_OPTIONS
```

### 2. install_slurm_accounting.sh

**Before:**
```ini
Type=notify
ExecStart=/usr/local/slurm/sbin/slurmdbd -D $SLURMDBD_OPTIONS
```

**After:**
```ini
Type=simple
ExecStart=/usr/local/slurm/sbin/slurmdbd $SLURMDBD_OPTIONS
```

### 주요 변경점

1. ✅ `Type=notify` → `Type=simple`
2. ✅ `-D` 옵션 제거 (foreground → background)
3. ✅ `TimeoutStartSec=120` 유지
4. ✅ 기타 모든 설정 유지

---

## 🧪 검증 항목

`verify_setup_cluster_full.sh`가 확인하는 항목:

- [x] 필수 파일 존재 (15개)
- [x] Type=simple 설정
- [x] Type=notify 제거
- [x] -D 옵션 제거
- [x] Step 구성 (Step 2~12)
- [x] SSH timeout 설정
- [x] QoS 기능 (slurmdbd)
- [x] cgroup v2 지원
- [x] 기타 필수 기능

---

## 🚀 다음 단계

### 전환 후 (즉시)

```bash
# 1. 새 클러스터 설치
./setup_cluster_full.sh
```

### 설치 중 주요 Step

- **Step 6.1**: systemd 서비스 생성 (Type=simple)
- **Step 6.5**: slurmdbd 설치 (QoS) - 선택 가능
- **Step 7.5**: 원격 systemd 배포
- **Step 10**: 원격 서비스 시작 (timeout 60초)

### 설치 후 확인

```bash
# 서비스 Type 확인
systemctl show slurmctld | grep Type
# 출력: Type=simple

# Slurm 작동 확인
sinfo
squeue

# QoS 확인 (설치 시)
sacctmgr show qos
```

---

## 🛠️ 기존 클러스터 업데이트 (선택)

**주의**: 기존 클러스터는 이미 작동 중이므로 업데이트는 **선택 사항**입니다.

### 업데이트가 필요한 경우

- 서비스 시작 시 타임아웃 발생
- systemd hanging 문제
- 원격 노드 배포 실패

### 업데이트 방법

```bash
# 1. 백업
sudo cp /etc/systemd/system/slurm*.service /tmp/

# 2. 서비스 재생성
sudo ./create_slurm_systemd_services.sh

# 3. systemd 리로드
sudo systemctl daemon-reload

# 4. 서비스 재시작
sudo systemctl restart slurmctld
sudo systemctl restart slurmd

# 5. 확인
systemctl show slurmctld | grep Type
sudo systemctl status slurmctld
```

---

## 📊 체크리스트

### 실행 전
- [ ] `/home/koopark/claude/KooSlurmInstallAutomationRefactory` 디렉토리 확인
- [ ] `run_complete_conversion.sh` 파일 존재 확인

### 실행 중
- [ ] `run_complete_conversion.sh` 실행
- [ ] 백업 생성 확인
- [ ] Type=simple 전환 완료
- [ ] 검증 통과

### 실행 후
- [ ] Type=simple 확인
- [ ] -D 옵션 제거 확인
- [ ] 백업 위치 확인
- [ ] `./setup_cluster_full.sh` 준비 완료

---

## 🎯 한눈에 보기

```
실행 흐름:
  
  run_complete_conversion.sh
         ↓
         ├─→ convert_systemd_to_simple.sh
         │      ├─ 백업 생성
         │      ├─ create_slurm_systemd_services.sh 수정
         │      └─ install_slurm_accounting.sh 수정
         │
         ├─→ verify_setup_cluster_full.sh
         │      ├─ 필수 파일 확인
         │      ├─ Type=simple 확인
         │      └─ 전체 검증
         │
         └─→ 결과 요약 출력

성공!
   ↓
./setup_cluster_full.sh (새 클러스터 설치)
```

---

## 💡 팁

### 빠른 확인
```bash
# Type 확인
grep "Type=" create_slurm_systemd_services.sh install_slurm_accounting.sh

# -D 옵션 확인 (없어야 함)
grep -- "-D" create_slurm_systemd_services.sh install_slurm_accounting.sh
```

### 문제 발생 시
```bash
# 백업 복원
BACKUP=$(ls -td backup_*_notify_to_simple | head -1)
cp $BACKUP/*.sh ./

# 다시 실행
./run_complete_conversion.sh
```

---

## 📞 지원

- **상세 분석**: Artifact "전체 분석 및 수정 계획"
- **완전 가이드**: Artifact "Type=simple 전환 가이드"
- **백업 위치**: `backup_YYYYMMDD_HHMMSS_notify_to_simple/`

---

## ✅ 최종 확인

전환 완료 후:

```bash
# 1. Type 확인
grep "Type=simple" create_slurm_systemd_services.sh
# 최소 2개 출력 (slurmctld, slurmd)

grep "Type=simple" install_slurm_accounting.sh
# 최소 1개 출력 (slurmdbd)

# 2. Type=notify 없음 확인
! grep "Type=notify" create_slurm_systemd_services.sh
! grep "Type=notify" install_slurm_accounting.sh

# 3. 검증 스크립트 실행
./verify_setup_cluster_full.sh
# 출력: 🎉 모든 검사 통과!
```

---

## 🎉 완료!

이제 다음 명령어 하나만 실행하면 모든 것이 자동으로 처리됩니다:

```bash
./run_complete_conversion.sh
```

**성공 후**:
```bash
./setup_cluster_full.sh
```

---

**작성일**: 2025-10-12  
**버전**: 1.0  
**상태**: ✅ 실행 준비 완료
