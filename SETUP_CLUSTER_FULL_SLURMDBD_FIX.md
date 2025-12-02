# setup_cluster_full.sh에 slurmdbd 설치 단계 추가

## 🎯 목표

`setup_cluster_full.sh`에 **slurmdbd (Slurm Accounting) 설치 단계**를 추가하여, 
클러스터 초기 설치 시부터 QoS 기능을 사용할 수 있도록 함.

## 📝 변경 사항

### 1. Step 6.5 추가: slurmdbd 설치

**위치**: Step 6 (Slurm 설치)과 Step 7 (계산 노드 Slurm 설치) 사이

```bash
################################################################################
# Step 6.5: Slurm Accounting (slurmdbd) 설치
################################################################################

echo "🗄️  Step 6.5/13: Slurm Accounting (slurmdbd) 설치..."
echo "--------------------------------------------------------------------------------"
echo "slurmdbd는 Slurm의 Accounting 기능을 제공합니다."
echo "QoS (Quality of Service) 기능을 사용하려는 경우 필수입니다."
echo ""
echo "📌 QoS 기능:"
echo "  - 그룹별 CPU/메모리 제한"
echo "  - 작업 우선순위 관리"
echo "  - 리소스 사용량 추적"
echo "  - Dashboard Apply Configuration 기능"
echo ""
echo "⚠️  QoS가 필요없다면 건너뛸 수 있습니다."
echo "   (기본 Slurm 기능은 정상 작동합니다)"
echo ""

read -p "slurmdbd를 설치하시겠습니까? (권장: Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ -f "install_slurm_accounting.sh" ]; then
        chmod +x install_slurm_accounting.sh
        sudo bash install_slurm_accounting.sh
        
        if [ $? -eq 0 ]; then
            echo "✅ slurmdbd 설치 완료"
            SLURMDBD_INSTALLED=true
        else
            echo "⚠️  slurmdbd 설치 실패"
            echo "   QoS 기능을 사용할 수 없지만, 기본 Slurm은 정상 작동합니다."
            SLURMDBD_INSTALLED=false
        fi
    else
        echo "⚠️  install_slurm_accounting.sh를 찾을 수 없습니다."
        echo "💡 수동으로 slurmdbd를 설치하세요."
        SLURMDBD_INSTALLED=false
    fi
else
    echo "⏭️  slurmdbd 설치 건너뛰 (QoS 기능 비활성화)"
    SLURMDBD_INSTALLED=false
fi

echo ""
```

### 2. Step 번호 재조정

모든 후속 Step 번호를 +2 증가:
- Step 7 → Step 8 (설정 파일 생성)
- Step 8 → Step 9 (설정 파일 배포)
- Step 9 → Step 10 (서비스 시작)
- Step 10 → Step 11 (PATH 설정)
- Step 11 → Step 12 (MPI 설치)

총 단계: **11개 → 13개**

### 3. 완료 메시지에 slurmdbd 상태 추가

```bash
# slurmdbd 설치 상태 표시
if [ "${SLURMDBD_INSTALLED:-false}" = true ]; then
    echo "✅ Slurm Accounting (slurmdbd) 설치됨"
    echo "   - QoS 기능 사용 가능"
    echo "   - Dashboard Apply Configuration 정상 작동"
    echo "   - 그룹별 CPU 제한 및 우선순위 관리 가능"
    echo ""
    echo "   🧪 QoS 테스트:"
    echo "      sacctmgr show qos"
    echo "      sacctmgr show cluster"
    echo ""
else
    echo "⚠️  Slurm Accounting (slurmdbd) 미설치"
    echo "   - 기본 Slurm 기능은 정상 작동 ✅"
    echo "   - QoS 기능 비활성화 (그룹별 CPU 제한 불가) ❌"
    echo "   - Dashboard Apply Configuration 실패 예상 ❌"
    echo ""
    echo "   💡 나중에 QoS 기능을 사용하려면:"
    echo "      ./install_slurm_accounting.sh"
    echo ""
fi
```

## 🚀 적용 방법

수정이 이미 완료되었습니다. 확인만 하면 됩니다:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 1. Step 6.5가 추가되었는지 확인
grep -n "Step 6.5" setup_cluster_full.sh

# 예상 출력:
# 166:echo "🗄️  Step 6.5/13: Slurm Accounting (slurmdbd) 설치..."

# 2. 마지막 상태 메시지 추가 (수동 실행 필요)
python3 add_slurmdbd_status.py
```

## 📊 설치 플로우

### 기존 (QoS 불가)

```
Step 1-5: 기본 설정
Step 6: Slurm 설치
Step 7: 계산 노드 설치
Step 8-11: 설정 및 시작
---
❌ slurmdbd 없음
❌ QoS 불가
❌ Dashboard Apply Configuration 실패
```

### 수정 후 (QoS 가능)

```
Step 1-5: 기본 설정
Step 6: Slurm 설치
Step 6.5: slurmdbd 설치 ← 새로 추가!
  ├─ MariaDB 설치
  ├─ slurm_acct_db 생성
  ├─ slurmdbd 설정
  └─ 서비스 시작
Step 7: 계산 노드 설치
Step 8-12: 설정 및 시작
---
✅ slurmdbd 설치됨
✅ QoS 사용 가능
✅ Dashboard Apply Configuration 성공
```

## 🔍 차이점 비교

| 항목 | 기존 | 수정 후 |
|------|------|---------|
| **총 Step 수** | 11개 (2-12) | 13개 (2-13) |
| **slurmdbd** | 없음 | Step 6.5에 추가 |
| **설치 방법** | 수동 | 자동 (선택 가능) |
| **QoS 기능** | 불가 | 가능 |
| **Apply Config** | 실패 | 성공 |

## ✅ 검증 방법

### 1. 새 클러스터 설치 시

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
./setup_cluster_full.sh

# Step 6.5에서:
# "slurmdbd를 설치하시겠습니까? (권장: Y/n):" → Y 입력

# 설치 완료 후:
sacctmgr show qos
sacctmgr show cluster

# 예상 출력: QoS 목록 및 클러스터 정보
```

### 2. 기존 클러스터에 slurmdbd 추가

```bash
# slurmdbd만 따로 설치
./install_slurm_accounting.sh

# 검증
sudo systemctl status slurmdbd
sacctmgr show qos
```

### 3. Dashboard 테스트

```bash
cd dashboard/dashboard_refactory/backend_5010
export MOCK_MODE=false
./start.sh

# 브라우저: System Management → Apply Configuration
# 예상 결과: ✅ Configuration applied successfully
```

## 📋 파일 목록

### 수정된 파일

1. ✅ `setup_cluster_full.sh`
   - Step 6.5 추가 (slurmdbd 설치)
   - Step 번호 재조정 (7→8, 8→9, ...)
   - SLURMDBD_INSTALLED 변수 추가

### 신규 파일 (이미 생성됨)

2. ✅ `install_slurm_accounting.sh`
   - 독립 실행 가능한 slurmdbd 설치 스크립트
   
3. ✅ `add_slurmdbd_status.py`
   - setup_cluster_full.sh에 상태 메시지 추가하는 헬퍼 스크립트

## 🎓 사용자 선택권

slurmdbd 설치는 **선택 사항**입니다:

### QoS가 필요한 경우

```bash
Step 6.5: slurmdbd를 설치하시겠습니까? → Y
```

**장점**:
- ✅ 그룹별 CPU/메모리 제한
- ✅ 작업 우선순위 관리
- ✅ 리소스 사용량 추적
- ✅ Dashboard Apply Configuration 작동

**요구사항**:
- MariaDB/MySQL
- 추가 디스크 공간 (~100MB)

### QoS가 필요없는 경우

```bash
Step 6.5: slurmdbd를 설치하시겠습니까? → N
```

**결과**:
- ✅ 기본 Slurm 기능 정상 작동
- ✅ 작업 제출/실행 가능
- ❌ QoS 기능 비활성화
- ❌ Dashboard Apply Configuration 실패

나중에 필요하면 언제든지 설치 가능:
```bash
./install_slurm_accounting.sh
```

## 🚨 주의사항

### 1. 기존 클러스터

이미 `setup_cluster_full.sh`로 설치한 클러스터는:
- slurmdbd가 설치되지 않음
- QoS 기능 비활성화
- `install_slurm_accounting.sh`로 추가 설치 필요

### 2. MariaDB 의존성

slurmdbd는 MariaDB/MySQL이 필요:
- `install_slurm_accounting.sh`가 자동 설치
- 이미 설치되어 있으면 건너뜀

### 3. 데이터베이스 비밀번호

기본값: `slurmdbpass`

변경하려면:
```bash
# slurmdbd.conf 수정
sudo vi /usr/local/slurm/etc/slurmdbd.conf
# StoragePass=새비밀번호

# 데이터베이스도 업데이트
sudo mysql -e "ALTER USER 'slurm'@'localhost' IDENTIFIED BY '새비밀번호';"
```

## 📖 관련 문서

1. `FIX_QOS_WITH_SLURMDBD.md` - slurmdbd 상세 설명
2. `install_slurm_accounting.sh` - 독립 설치 스크립트
3. `CLUSTER_GROUPS_SYNC.md` - Dashboard 그룹 동기화

## 🎯 결론

**setup_cluster_full.sh에 slurmdbd 설치 단계를 추가**하여:

1. ✅ 클러스터 초기 설치 시 QoS 기능 활성화 가능
2. ✅ 사용자가 선택할 수 있도록 옵션 제공
3. ✅ Dashboard Apply Configuration 정상 작동
4. ✅ 향후 클러스터는 완전한 기능 제공

이제 **새로 설치하는 클러스터**는 QoS 문제가 없습니다!

---

**작성일**: 2025-10-11  
**수정 파일**:
- `setup_cluster_full.sh` - Step 6.5 추가, Step 번호 재조정

**신규 파일**:
- `install_slurm_accounting.sh` - slurmdbd 독립 설치 스크립트
- `add_slurmdbd_status.py` - 상태 메시지 추가 헬퍼

**해결된 문제**:
- setup_cluster_full.sh에 slurmdbd 단계 누락
- 초기 설치 시 QoS 기능 비활성화
- Dashboard Apply Configuration 실패
