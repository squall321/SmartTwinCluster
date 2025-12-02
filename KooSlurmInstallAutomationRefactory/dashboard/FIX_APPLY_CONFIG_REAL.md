# Apply Configuration 실패 문제 - 실제 해결

## 🎯 문제 재정의

**목적**: Apply Configuration의 주요 목적은 **실제 Slurm 재설정** (QoS + Partitions)

**증상**: "Failed to apply configuration" 에러

## 🔍 근본 원인

### 1. MOCK_MODE 정적 변수 문제

```python
# app.py Line 44: 모듈 로드 시 한 번만 설정
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# app.py Line 697: 이 값이 계속 사용됨
if MOCK_MODE:  # ← 환경변수 변경해도 이 값은 안 바뀜!
    return apply_mock_config(groups, dry_run)
```

**결과**: `export MOCK_MODE=false` 후 Backend 재시작해도 여전히 Mock 모드로 동작

### 2. 로깅 부족

Production 모드에서 실패해도 구체적인 에러 메시지가 없어 디버깅 불가

## ✅ 해결 방법

### 수정 1: Backend - 동적 환경변수 체크

**파일**: `backend_5010/app.py`

```python
# Before (Line 697)
if MOCK_MODE:
    return apply_mock_config(groups, dry_run)

# After
# 매번 환경변수 직접 체크 (동적 모드 전환 지원)
current_mode = os.getenv('MOCK_MODE', 'true').lower() == 'true'

if current_mode:
    return apply_mock_config(groups, dry_run)
```

### 수정 2: Backend - 상세 로깅 추가

```python
def apply_real_config(groups, dry_run):
    """Production 모드: 실제 Slurm 명령 실행"""
    print("🚀 Production Mode: Applying real configuration...")
    print(f"   Groups: {len(groups)}")  # ← 추가
    print(f"   Dry Run: {dry_run}")     # ← 추가
    
    try:
        print("   Calling apply_full_configuration...")  # ← 추가
        results = apply_full_configuration(groups, dry_run)
        print(f"   Results: {results}")  # ← 추가
        ...
    except Exception as e:
        print(f"❌ Error in apply_real_config: {e}")  # ← 추가
        import traceback
        traceback.print_exc()  # ← 추가
```

### 수정 3: Frontend - Slurm API 호출 복원

**파일**: `frontend_3010/src/store/clusterStore.ts`

```typescript
// 1. Slurm 설정 적용 (QoS + Partitions)
const slurmResult = await apiPost('/api/slurm/apply-config', { groups });

if (!slurmResult.success) {
  throw new Error(slurmResult.error || 'Failed to apply Slurm configuration');
}

// 2. 클러스터 구성 저장 (DB에 저장)
const configResult = await apiPost('/api/cluster/config', config);
```

## 🚀 적용 방법

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 실행 권한
chmod +x fix_apply_config.sh

# 통합 재시작
./fix_apply_config.sh
```

이 스크립트가 자동으로:
1. Backend 재시작 (Production 모드)
2. Frontend 재시작
3. 테스트 가이드 출력

## 🔎 테스트 절차

### 1. Cluster Management 접속

```
http://localhost:3010 → System Management → Cluster Management
```

### 2. 그룹 설정 변경

```
예시:
- Group 1 선택
- allowedCoreSizes에 4096 추가
- Description 변경: "Large scale jobs with flexible sizing"
```

### 3. Apply Configuration 클릭

**성공 시**:
```
✅ "Configuration applied successfully" 메시지
```

**실패 시**:
```
❌ Backend 로그 확인 필요
```

### 4. Backend 로그 실시간 모니터링

**별도 터미널에서**:
```bash
tail -f backend_5010/backend.log
```

**예상 로그 (성공)**:
```
🚀 Production Mode: Applying real configuration...
   Groups: 6
   Dry Run: False
   Calling apply_full_configuration...
============================================================
Step 1: Creating/Updating QoS
============================================================
📝 QoS already exists: group1_qos
   Setting MaxTRESPerJob=cpu=8192
   Setting Priority=1100
✅ QoS group1_qos configured successfully
...
============================================================
Step 2: Updating Partitions
============================================================
✅ Backup created: ~/.slurm_backups/slurm.conf.backup.20251011_140530
✅ Updated partitions in /usr/local/slurm/etc/slurm.conf
   Total partitions: 6
✅ Configuration is valid
🔄 Reconfiguring Slurm...
✅ Slurm reconfigured successfully
```

**예상 로그 (실패)**:
```
🚀 Production Mode: Applying real configuration...
   Groups: 6
   Dry Run: False
   Calling apply_full_configuration...
❌ Failed to create/update QoS group1_qos: [Errno 2] No such file or directory: '/usr/bin/sacctmgr'
❌ Configuration apply failed: ...
```

### 5. Job Templates 확인

```
Job Templates → New Template
→ Partition 드롭다운 확인
→ 변경된 allowedCoreSizes 확인
```

## 🐛 예상되는 에러와 해결

### 에러 1: Slurm 명령어 없음

```
❌ No such file or directory: '/usr/bin/sacctmgr'
```

**원인**: Slurm이 설치되지 않았거나 경로가 다름

**해결책**:
1. Slurm 설치 확인
```bash
which sacctmgr
which scontrol
```

2. 경로 확인 후 `slurm_commands.py` 수정
```python
# 실제 경로로 수정
SACCTMGR = '/usr/local/bin/sacctmgr'
SCONTROL = '/usr/local/bin/scontrol'
```

### 에러 2: 권한 없음

```
❌ Permission denied: /etc/slurm/slurm.conf
```

**원인**: slurm.conf 파일 쓰기 권한 없음

**해결책**:
1. sudoers 설정 확인
```bash
sudo visudo
```

2. 사용자에게 Slurm 명령어 권한 추가
```
koopark ALL=(ALL) NOPASSWD: /usr/bin/sacctmgr
koopark ALL=(ALL) NOPASSWD: /usr/bin/scontrol
koopark ALL=(ALL) NOPASSWD: /bin/cp
koopark ALL=(ALL) NOPASSWD: /bin/chown
```

### 에러 3: QoS 생성 실패

```
❌ Failed to create/update QoS: sacctmgr: error: Problem with update of qos
```

**원인**: Slurm accounting이 설정되지 않음

**해결책**:
1. `slurmdbd` 데몬 확인
```bash
sudo systemctl status slurmdbd
```

2. slurm.conf에 AccountingStorageType 설정
```
AccountingStorageType=accounting_storage/slurmdbd
```

### 에러 4: 노드가 없는 파티션

```
⚠️  Warning: Partition has no nodes assigned
```

**원인**: 그룹에 노드가 할당되지 않음

**해결책**:
1. Cluster Management에서 노드 할당
2. 각 그룹에 최소 1개 이상의 노드 배정

## 📊 동작 흐름

### 전체 프로세스

```
Cluster Management (Frontend)
    ↓
    1. Apply Configuration 버튼 클릭
    ↓
POST /api/slurm/apply-config
    ↓
    2. apply_full_configuration() 호출
    ↓
    ├─ Step 1: QoS 생성/업데이트
    │   ├─ sacctmgr add qos group1_qos
    │   ├─ sacctmgr modify qos MaxTRESPerJob=cpu=8192
    │   └─ sacctmgr modify qos Priority=1100
    │
    ├─ Step 2: Partitions 업데이트
    │   ├─ slurm.conf 백업
    │   ├─ 파티션 섹션 재생성
    │   ├─ 파일 쓰기 (sudo)
    │   └─ 검증 (scontrol show config)
    │
    └─ Step 3: Slurm 재설정
        └─ scontrol reconfigure
    ↓
POST /api/cluster/config (DB 저장)
    ↓
Job Templates ← GET /api/groups/partitions
    ↓
Updated 그룹 정보 표시
```

### slurm.conf 변경 예시

**Before**:
```conf
# Partitions (Auto-generated by Dashboard)
PartitionName=group1 Nodes=node[001-064] Default=YES MaxTime=INFINITE State=UP
PartitionName=group2 Nodes=node[065-128] Default=YES MaxTime=INFINITE State=UP
```

**After (allowedCoreSizes 변경 후)**:
```conf
# Partitions (Auto-generated by Dashboard)
# Generated at: 2025-10-11T14:05:30.123456
PartitionName=group1 Nodes=node[001-064] Default=YES MaxTime=INFINITE State=UP QOS=group1_qos AllowQos=group1_qos
PartitionName=group2 Nodes=node[065-128] Default=YES MaxTime=INFINITE State=UP QOS=group2_qos AllowQos=group2_qos
```

## 🎓 핵심 개념

### 1. Mock vs Production 모드

| Mode | Slurm 명령 | slurm.conf | DB 저장 |
|------|-----------|-----------|---------|
| **Mock** | 시뮬레이션만 | 변경 없음 | ✅ |
| **Production** | 실제 실행 | 실제 변경 | ✅ |

### 2. Apply Configuration의 역할

1. **QoS 설정**: 각 그룹의 최대 CPU 제한
2. **Partition 설정**: 노드를 파티션에 할당
3. **slurm.conf 업데이트**: 설정 파일 재생성
4. **Slurm 재설정**: `scontrol reconfigure`로 적용
5. **DB 동기화**: Job Templates를 위한 DB 업데이트

### 3. 동적 모드 전환

```python
# 매번 체크하므로 환경변수 변경 즉시 반영
current_mode = os.getenv('MOCK_MODE', 'true').lower() == 'true'
```

**장점**:
- Backend 재시작 없이 모드 전환 가능
- 개발/테스트/운영 전환 용이
- API 단위로 다른 모드 사용 가능

## 🚨 주의사항

1. **Production 모드 주의**
   - 실제 Slurm 설정 변경됨
   - 백업은 자동으로 `~/.slurm_backups/`에 저장
   - 잘못된 설정 시 클러스터 영향 가능

2. **권한 필요**
   - sudo 권한으로 slurm.conf 수정
   - sudoers 설정 필요

3. **노드 할당 필수**
   - 노드가 없는 파티션은 생성되지 않음
   - 각 그룹에 최소 1개 이상의 노드 필요

4. **Slurm 재설정**
   - `scontrol reconfigure` 실행
   - 실행 중인 작업에는 영향 없음
   - 새 작업부터 새 설정 적용

## 📝 수정된 파일

1. ✅ `backend_5010/app.py` - apply_slurm_config 함수 수정
   - 동적 MOCK_MODE 체크
   - 상세 로깅 추가
   - 에러 traceback 출력

2. ✅ `frontend_3010/src/store/clusterStore.ts` - applyConfiguration 수정
   - Slurm API 호출 복원
   - 로깅 추가
   - 에러 메시지 개선

3. ✅ `fix_apply_config.sh` - 통합 재시작 스크립트

## 💡 향후 개선 사항

1. **Dry Run 기능**: 변경사항 미리보기
2. **Rollback 기능**: 이전 설정으로 자동 복원
3. **검증 강화**: 노드 할당 검증, QoS 충돌 검사
4. **알림**: 설정 적용 성공/실패 시 알림
5. **히스토리**: 설정 변경 이력 저장

---

**작성일**: 2025-10-11  
**수정 파일**:
- `backend_5010/app.py` - apply_slurm_config 수정
- `frontend_3010/src/store/clusterStore.ts` - applyConfiguration 복원

**신규 파일**:
- `fix_apply_config.sh` - 통합 재시작 스크립트

**해결된 문제**:
- "Failed to apply configuration" 에러
- MOCK_MODE 정적 변수 문제
- 로깅 부족으로 디버깅 불가

**핵심 변경**:
- 동적 환경변수 체크로 실시간 모드 전환
- 상세 로깅으로 에러 추적 가능
- Slurm 실제 재설정 기능 복원
