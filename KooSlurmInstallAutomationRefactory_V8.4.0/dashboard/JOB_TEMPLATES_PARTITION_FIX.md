# Job Templates Partition 및 CPU 정책 통합 수정

## 🎯 문제 인식

Job Templates에서 사용하는 `partition` 이름과 Cluster Management의 실제 그룹 `partitionName`이 불일치하여 혼란을 야기했습니다.

### 이전 상태 (문제점)
- **Job Templates의 Partition**: `'gpu'`, `'cpu'`, `'compute'`, `'debug'` 등 임의의 이름 사용
- **Cluster Management의 실제 Partition**: `'group1'`, `'group2'`, ... `'group6'`
- **CPU 개수**: 임의의 값 입력 가능 (정책 무시)

## ✅ 수정 내용

### 1. Backend API Mock 데이터 수정 (`templates_api.py`)

모든 Mock 템플릿의 partition을 실제 Cluster Groups와 일치하도록 변경:

```python
# 변경 전
'partition': 'gpu'      # ❌ 존재하지 않는 파티션
'partition': 'cpu'      # ❌ 존재하지 않는 파티션
'partition': 'compute'  # ❌ 존재하지 않는 파티션
'partition': 'debug'    # ❌ 존재하지 않는 파티션

# 변경 후
'partition': 'group1'   # ✅ 실제 파티션
'partition': 'group2'   # ✅ 실제 파티션
'partition': 'group3'   # ✅ 실제 파티션
'partition': 'group6'   # ✅ 실제 파티션
```

**Mock 템플릿별 변경:**
- `PyTorch Training` (tpl-001): `'gpu'` → `'group1'` (allowedCoreSizes: [8192])
  - CPU도 8 → 8192로 변경하여 정책 준수
- `TensorFlow Distributed` (tpl-002): `'gpu'` → `'group2'` (allowedCoreSizes: [1024])
  - CPU도 16 → 1024로 변경하여 정책 준수
- `GROMACS Simulation` (tpl-003): `'cpu'` → `'group3'` (allowedCoreSizes: [1024])
  - CPU도 32 → 1024로 변경하여 정책 준수
- `Data Processing` (tpl-004): `'cpu'` → `'group6'` (allowedCoreSizes: [8, 16, 32, 64])
- `Quick Test` (tpl-005): `'debug'` → `'group6'`, CPU 1 → 8 (유연한 그룹)
- `LS-DYNA Single` (tpl-lsdyna-single): `'compute'` → `'group6'`
- `LS-DYNA Array` (tpl-lsdyna-array): `'compute'` → `'group6'`

### 2. Database Schema 수정 (`schema.sql`)

Production 모드를 위한 초기 템플릿 데이터도 수정:

```sql
-- 변경 전
'{"partition": "compute", "nodes": 1, "cpus": 32, ...}'  -- LS-DYNA Single
'{"partition": "compute", "nodes": 1, "cpus": 16, ...}'  -- LS-DYNA Array

-- 변경 후
'{"partition": "group6", "nodes": 1, "cpus": 32, ...}'   -- LS-DYNA Single ✅
'{"partition": "group6", "nodes": 1, "cpus": 16, ...}'   -- LS-DYNA Array ✅
```

### 3. Frontend는 이미 올바르게 구현됨 ✅

`TemplateEditor.tsx`는 이미 다음 기능들이 올바르게 구현되어 있었습니다:

1. **Partition 자동 로드**: `/api/groups/partitions` API로부터 실제 파티션 목록 가져오기
2. **CPU 정책 준수**: 
   - Partition 선택 시 해당 그룹의 `allowedCoreSizes` 자동 로드
   - CPU 개수를 드롭다운으로만 선택 가능 (정책에 맞는 값만)
   - 잘못된 CPU 값 자동 보정
3. **UI 피드백**: 허용된 CPU 목록을 시각적으로 표시

## 📋 Cluster Groups 정보

현재 클러스터 구성:

| Group ID | Partition Name | Allowed Core Sizes | Description |
|----------|----------------|-------------------|-------------|
| 1 | `group1` | [8192] | Large scale jobs |
| 2 | `group2` | [1024] | Medium jobs |
| 3 | `group3` | [1024] | Medium jobs |
| 4 | `group4` | [128] | Small jobs |
| 5 | `group5` | [128] | Small jobs |
| 6 | `group6` | [8, 16, 32, 64] | Flexible jobs |

## 🔄 적용 방법

### Mock 모드에서 즉시 적용
- 서버 재시작 시 새로운 Mock 데이터 자동 적용
- 기존 Mock 템플릿들이 올바른 partition 사용

### Production 모드 적용
1. **데이터베이스 초기화** (기존 데이터 삭제 주의):
   ```bash
   cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory
   ./reset_database.sh
   ```

2. **서비스 재시작**:
   ```bash
   ./restart_frontend_only.sh  # Frontend만 재시작
   # 또는
   ./stop_all.sh && ./start_all.sh  # 전체 재시작
   ```

### 기존 템플릿 수정 (Production 모드)
기존에 잘못된 partition을 가진 템플릿이 있다면 수동으로 수정 필요:
```sql
UPDATE templates 
SET config = json_replace(config, '$.partition', 'group6')
WHERE json_extract(config, '$.partition') = 'compute';
```

## ✨ 개선 효과

### Before (수정 전)
```
Job Template: PyTorch Training
Partition: gpu  ❌ 존재하지 않는 파티션
CPUs: 8         ❌ Group1 정책(8192 cores)과 불일치
```

### After (수정 후)
```
Job Template: PyTorch Training
Partition: group1  ✅ 실제 파티션
CPUs: 8192         ✅ Group1 정책 준수
```

## 🎯 사용자 경험

1. **Template 생성/수정 시**:
   - Partition 드롭다운에서 실제 그룹 선택
   - 선택한 그룹의 허용 CPU 목록만 표시
   - 잘못된 값 입력 불가

2. **Template 사용 시**:
   - 실제 존재하는 파티션으로 Job 제출
   - CPU 수가 그룹 정책과 일치하여 Job 성공률 향상

## 📝 참고 사항

- Frontend의 `TemplateEditor.tsx`는 이미 올바르게 구현되어 있었음
- Backend의 Mock 데이터만 불일치했던 문제
- Production 환경에서는 데이터베이스 초기화 시 주의 필요
- 기존 사용자가 만든 템플릿은 수동 수정 또는 재생성 권장

## 🔍 검증 방법

1. **API 테스트**:
   ```bash
   # Partitions 조회
   curl http://localhost:5010/api/groups/partitions
   
   # Templates 조회
   curl http://localhost:5010/api/jobs/templates
   ```

2. **UI 테스트**:
   - Job Templates 페이지 접속
   - "New Template" 클릭
   - Partition 드롭다운 확인 (group1-6만 표시)
   - Partition 선택 시 허용 CPU 목록 확인

3. **정책 준수 확인**:
   - group1 선택 → CPU는 8192만 선택 가능
   - group6 선택 → CPU는 8, 16, 32, 64 중 선택 가능

---

**작성일**: 2025-10-11  
**수정 파일**:
- `backend_5010/templates_api.py`
- `backend_5010/database/schema.sql`

**관련 API**:
- `GET /api/groups/partitions` - 파티션 목록 조회
- `GET /api/jobs/templates` - 템플릿 목록 조회
- `POST /api/jobs/templates` - 템플릿 생성
