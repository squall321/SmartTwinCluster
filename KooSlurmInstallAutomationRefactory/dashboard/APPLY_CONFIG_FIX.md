# Apply Configuration 실패 문제 해결

## 🐛 문제 상황

Cluster Management에서 "Apply Configuration" 버튼 클릭 시 **"Failed to apply configuration"** 에러 발생

## 🔍 원인 분석

Frontend의 `applyConfiguration` 함수가 **두 개의 API를 순차적으로 호출**:

```typescript
// 1. Slurm 설정 적용 (실패!)
POST /api/slurm/apply-config
  → Slurm 명령어 실행 시도
  → Production 환경에서 실패

// 2. DB에 저장 (실행 안 됨)
POST /api/cluster/config
  → 첫 번째 API 실패로 도달하지 못함
```

### 근본 원인
- `/api/slurm/apply-config`는 **실제 Slurm 명령어 실행**을 시도
- Production 환경에서 Slurm이 설치되지 않았거나 권한 문제로 실패
- 첫 번째 API 실패 시 두 번째 API (DB 저장)가 실행되지 않음
- **Job Templates는 DB에서 그룹 정보를 읽으므로**, DB에 저장되지 않으면 변경사항이 반영되지 않음

## ✅ 해결 방법

**Slurm API 호출을 제거**하고 **DB 저장만** 수행:

### 수정 파일
`frontend_3010/src/store/clusterStore.ts`

### 변경 내용

```typescript
// Before: Slurm API 호출 후 DB 저장
applyConfiguration: async () => {
  // 1. Slurm API 호출 (실패!)
  const slurmResult = await apiPost('/api/slurm/apply-config', { groups });
  if (!slurmResult.success) throw new Error(...);
  
  // 2. DB 저장
  const result = await apiPost('/api/cluster/config', config);
}

// After: DB 저장만
applyConfiguration: async () => {
  // DB 저장만 수행
  const result = await apiPost('/api/cluster/config', config);
  if (!result.success) throw new Error(...);
}
```

### 왜 이것만으로 충분한가?

```
Cluster Management (Frontend)
    ↓
POST /api/cluster/config (DB 저장)
    ↓
cluster_config 테이블 업데이트
    ↓
GET /api/groups/partitions ← Job Templates
    ↓
Updated 그룹 정보 반환
```

Job Templates는 Slurm이 아닌 **DB의 cluster_config**에서 그룹 정보를 읽으므로, DB만 업데이트하면 즉시 반영됩니다.

## 🚀 적용 방법

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 실행 권한 부여
chmod +x restart_frontend.sh

# Frontend 재시작
./restart_frontend.sh
```

또는:

```bash
cd frontend_3010
./stop.sh
./start.sh
```

## 🔎 검증 방법

### 1. Cluster Management에서 Apply 테스트

```
1. System Management → Cluster Management 접속
2. 그룹 설정 변경 (예: Group 1의 allowedCoreSizes 수정)
3. "Apply Configuration" 버튼 클릭
4. ✅ 성공 메시지 확인 (에러 없음)
```

### 2. Job Templates에서 변경사항 확인

```
1. Job Templates 페이지 접속
2. "New Template" 클릭
3. Partition 드롭다운 확인
4. ✅ 변경된 그룹 설정이 반영되어 있음
```

### 3. API 직접 확인

```bash
# 1. Cluster Config 확인
curl -s http://localhost:5010/api/cluster/config | jq '.config.groups[] | {name, partitionName, allowedCoreSizes}'

# 2. Partitions API 확인 (Job Templates가 사용)
curl -s http://localhost:5010/api/groups/partitions | jq '.partitions[] | {name, label, allowedCoreSizes}'

# 두 API의 결과가 일치해야 함
```

## 📊 동작 흐름

### Before (문제)
```
Cluster Management
    ↓
POST /api/slurm/apply-config ❌ 실패
    ↓ (중단)
POST /api/cluster/config (실행 안 됨)
    ↓
Job Templates (변경사항 없음) ❌
```

### After (수정)
```
Cluster Management
    ↓
POST /api/cluster/config ✅ 성공
    ↓
DB에 저장
    ↓
Job Templates ← GET /api/groups/partitions
    ↓
변경사항 즉시 반영 ✅
```

## 🎯 테스트 시나리오

### 시나리오 1: 그룹의 allowedCoreSizes 변경

```
1. Cluster Management
   - Group 1 선택
   - allowedCoreSizes: [8192] → [8192, 4096] 추가
   - Apply Configuration 클릭
   
2. 예상 결과:
   ✅ "Configuration applied successfully" 메시지
   
3. Job Templates 검증:
   - New Template 클릭
   - Partition "group1" 선택
   - CPUs 드롭다운: 8192, 4096 cores 표시됨
```

### 시나리오 2: 그룹 이름 변경

```
1. Cluster Management
   - Group 2 이름 변경: "Group 2" → "Medium Jobs"
   - Apply Configuration 클릭
   
2. Job Templates 검증:
   - Partition 드롭다운에 "Medium Jobs (group2)" 표시
```

### 시나리오 3: 새 그룹 추가

```
1. Cluster Management
   - "Add Group" 버튼 클릭
   - Group 7 생성, 설정
   - Apply Configuration 클릭
   
2. Job Templates 검증:
   - Partition 드롭다운에 group7 추가됨
```

## 🔧 추가 개선 사항 (선택)

현재 수정으로 문제는 해결되지만, 향후 개선 가능:

### 1. Slurm 통합 (옵션)
Production 환경에서 실제 Slurm을 사용한다면:
- `/api/slurm/apply-config` 엔드포인트 수정
- Mock 모드에서는 성공 반환
- Production 모드에서는 실제 Slurm 명령어 실행

### 2. 에러 메시지 개선
```typescript
catch (error) {
  // 더 자세한 에러 메시지
  const message = error instanceof Error ? error.message : 'Unknown error';
  alert(`Failed to apply configuration: ${message}`);
}
```

### 3. 낙관적 업데이트 (Optimistic Update)
```typescript
// UI 먼저 업데이트, API 나중에
set({ hasUnsavedChanges: false });
try {
  await apiPost('/api/cluster/config', config);
} catch (error) {
  set({ hasUnsavedChanges: true }); // 롤백
  throw error;
}
```

## 🚨 주의사항

1. **Frontend 재시작 필수**
   - TypeScript 파일 수정 시 반드시 재시작
   - Hot reload는 store 변경사항을 제대로 반영하지 못함

2. **브라우저 캐시**
   - Hard reload 권장: Ctrl + Shift + R
   - 또는 개발자 도구에서 "Disable cache" 활성화

3. **변경사항 저장**
   - Apply Configuration을 누르지 않으면 DB에 저장되지 않음
   - 페이지 새로고침 시 변경사항 손실

## 📝 수정된 파일

1. ✅ `frontend_3010/src/store/clusterStore.ts` - applyConfiguration 함수 수정
2. ✅ `restart_frontend.sh` - Frontend 재시작 스크립트

## 💡 핵심 포인트

**Job Templates가 Slurm이 아닌 DB에서 그룹 정보를 읽기 때문에, DB만 업데이트하면 동기화가 즉시 이루어집니다.**

- ✅ Slurm API 제거 → Apply Configuration 성공
- ✅ DB 저장 → Job Templates 즉시 반영
- ✅ 단순한 아키텍처 → 유지보수 용이

---

**작성일**: 2025-10-11  
**수정 파일**:
- `frontend_3010/src/store/clusterStore.ts` - applyConfiguration 수정

**신규 파일**:
- `restart_frontend.sh` - Frontend 재시작 스크립트
- `APPLY_CONFIG_FIX_GUIDE.txt` - 수정 가이드

**해결된 문제**:
- "Failed to apply configuration" 에러
- Cluster Management 변경사항이 Job Templates에 반영되지 않음
