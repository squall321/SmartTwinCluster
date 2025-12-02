# 클러스터 그룹 동기화 수정

## 🎯 문제 상황

Job Templates에서 사용하는 그룹(Partition)과 실제 Cluster Management에서 관리되는 그룹이 **동기화되지 않는** 문제가 있습니다.

### 문제점
1. **데이터 소스 분리**: 각 API가 독립적인 Mock 데이터 사용
2. **DB 미초기화**: Production 모드에서 `cluster_config` 테이블이 비어있음
3. **동기화 부재**: Cluster Management에서 그룹 변경 시 Job Templates에 반영 안 됨

## 🔍 현재 아키텍처

### API 구조
```
┌─────────────────────────────────────────┐
│  Frontend: Cluster Management           │
│  - 그룹 생성/수정/삭제                    │
│  - 노드 할당                              │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  /api/cluster/config                    │
│  - POST: 그룹 설정 저장                  │
│  - GET: 그룹 설정 조회                   │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  Database: cluster_config 테이블         │
│  - id: 1 (단일 레코드)                   │
│  - config: JSON (전체 클러스터 설정)      │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  /api/groups & /api/groups/partitions  │
│  - GET: 그룹 정보 조회 (Job Templates용) │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  Frontend: Job Templates                │
│  - Partition 선택                        │
│  - Allowed CPUs 선택                     │
└─────────────────────────────────────────┘
```

## ✅ 해결 방법

### 1. 데이터베이스 스키마 수정

**`schema.sql`에 초기 클러스터 설정 추가:**

```sql
-- Default cluster configuration
-- 초기 클러스터 그룹 구성 (initialData.ts와 일치)
INSERT OR IGNORE INTO cluster_config (id, config) VALUES
(1, '{"groups": [
  {
    "id": 1, 
    "name": "Group 1", 
    "partitionName": "group1", 
    "qosName": "group1_qos", 
    "allowedCoreSizes": [8192], 
    "color": "#3b82f6", 
    "description": "Large scale jobs",
    "nodeCount": 64,
    "totalCores": 8192,
    "nodes": []
  },
  ... (6개 그룹)
], 
"totalNodes": 370, 
"totalCores": 47360, 
"clusterName": "HPC-Cluster-370", 
"controllerIp": "192.168.1.10"}');
```

### 2. API 동적 환경변수 체크

**`cluster_config_api.py` 수정:**

```python
# Before
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# After
def is_mock_mode():
    """매번 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'
```

### 3. 데이터 흐름 통일

모든 그룹 관련 API가 **단일 소스(DB의 cluster_config)**에서 데이터를 가져옴:

```
Cluster Management (Frontend)
    ↓ (사용자가 그룹 설정 변경)
POST /api/cluster/config
    ↓ (DB 저장)
cluster_config 테이블
    ↓ (조회)
GET /api/groups → Job Templates
GET /api/groups/partitions → TemplateEditor
```

## 🚀 적용 방법

### 간단 적용 (권장) ⭐

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 실행 권한 부여
chmod +x sync_cluster_groups.sh
chmod +x verify_groups_sync.py

# 자동 동기화 적용
./sync_cluster_groups.sh
```

이 스크립트는 자동으로:
1. ✅ Backend 중지
2. ✅ DB 백업
3. ✅ DB 재생성 (초기 클러스터 설정 포함)
4. ✅ Backend 재시작 (Production)
5. ✅ 그룹 동기화 검증

### 수동 적용

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# 1. Backend 중지
cd backend_5010
./stop.sh

# 2. DB 백업
cp database/dashboard.db database/dashboard.db.backup

# 3. DB 삭제
rm -f database/dashboard.db

# 4. DB 초기화 (새 schema.sql 사용)
cd ..
python3 -c "
import sys
sys.path.insert(0, 'backend_5010')
from database import init_database
init_database()
"

# 5. Backend 재시작
cd backend_5010
export MOCK_MODE=false
./start.sh

# 6. 검증
cd ..
python3 verify_groups_sync.py
```

## 🔎 검증 방법

### 1. 자동 검증 스크립트

```bash
python3 verify_groups_sync.py
```

**예상 출력:**
```
============================================================
🔍 클러스터 그룹 동기화 검증
============================================================

📡 Cluster Config API
Mode: production
📊 Cluster Groups: 6개
  - Group 1 (group1): CPUs [8192]
  - Group 2 (group2): CPUs [1024]
  - Group 3 (group3): CPUs [1024]
  - Group 4 (group4): CPUs [128]
  - Group 5 (group5): CPUs [128]
  - Group 6 (group6): CPUs [8, 16, 32, 64]

📡 Groups API
Mode: production
📊 API Groups: 6개
  - Group 1 (group1): CPUs [8192]
  ...

📡 Partitions API
Mode: production
📊 Partitions: 6개
  - Group 1 (group1): CPUs [8192]
  ...

✅ 동기화 검증
✅ 모든 API가 동기화되어 있습니다!
```

### 2. API 직접 확인

```bash
# Cluster Config 확인
curl -s http://localhost:5010/api/cluster/config | \
  jq '.config.groups[] | {name, partitionName, allowedCoreSizes}'

# Groups API 확인
curl -s http://localhost:5010/api/groups | \
  jq '.groups[] | {name, partitionName, allowedCoreSizes}'

# Partitions API 확인 (Job Templates 사용)
curl -s http://localhost:5010/api/groups/partitions | \
  jq '.partitions[] | {label, name, allowedCoreSizes}'
```

### 3. 브라우저 확인

#### Cluster Management
1. System Management 페이지 접속
2. 6개 그룹 표시 확인
3. 각 그룹의 `allowedCoreSizes` 확인

#### Job Templates
1. Job Templates 페이지 접속
2. "New Template" 클릭
3. Partition 드롭다운 확인
   - ✅ group1 ~ group6 표시
   - ✅ 각 그룹의 허용 CPU 개수 표시
4. Partition 선택 시 CPUs 드롭다운 확인
   - ✅ 해당 그룹의 allowedCoreSizes만 표시

## 📊 그룹 설정 정보

### 현재 클러스터 그룹 구성 (6개)

| ID | Name | Partition | Allowed CPUs | Description |
|----|------|-----------|--------------|-------------|
| 1 | Group 1 | group1 | [8192] | Large scale jobs |
| 2 | Group 2 | group2 | [1024] | Medium jobs |
| 3 | Group 3 | group3 | [1024] | Medium jobs |
| 4 | Group 4 | group4 | [128] | Small jobs |
| 5 | Group 5 | group5 | [128] | Small jobs |
| 6 | Group 6 | group6 | [8, 16, 32, 64] | Flexible jobs |

## 🔄 그룹 변경 시나리오

### 시나리오: Cluster Management에서 그룹 수정

1. **사용자가 Cluster Management에서 Group 1의 allowedCoreSizes를 [8192, 4096]으로 변경**

2. **Frontend가 POST 요청**
   ```javascript
   POST /api/cluster/config
   Body: {
     groups: [
       {id: 1, allowedCoreSizes: [8192, 4096], ...},
       ...
     ]
   }
   ```

3. **Backend가 DB에 저장**
   ```python
   # cluster_config_api.py
   cursor.execute("UPDATE cluster_config SET config = ? WHERE id = 1", 
                  (json.dumps(config),))
   ```

4. **Job Templates가 즉시 반영**
   ```javascript
   GET /api/groups/partitions
   Response: {
     partitions: [
       {name: "group1", allowedCoreSizes: [8192, 4096]},
       ...
     ]
   }
   ```

5. **TemplateEditor에서 새 CPU 옵션 표시**
   - Partition "group1" 선택 시
   - CPUs 드롭다운: 8192 cores, 4096 cores

## 🎓 핵심 개념

### Single Source of Truth

```
                    ┌─────────────────────┐
                    │  cluster_config DB  │  ← Single Source
                    │   (id = 1)          │
                    └──────────┬──────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
         ┌──────▼─────┐ ┌─────▼──────┐ ┌────▼──────┐
         │ Cluster    │ │ Groups     │ │ Partitions│
         │ Config API │ │ API        │ │ API       │
         └────────────┘ └────────────┘ └───────────┘
                │              │              │
         ┌──────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐
         │ Cluster     │ │ (미사용)  │ │ Job        │
         │ Management  │ │          │ │ Templates  │
         └─────────────┘ └──────────┘ └────────────┘
```

### 데이터 일관성 보장

1. **쓰기**: Cluster Management만 데이터 수정 가능
2. **읽기**: 모든 API가 같은 DB 테이블 조회
3. **검증**: verify_groups_sync.py로 일관성 확인

## 🚨 주의사항

1. **데이터 손실**: 
   - 스크립트 실행 시 기존 DB 삭제
   - 자동 백업 생성됨
   - 중요한 설정이 있다면 수동 백업 권장

2. **사용자 생성 템플릿**: 
   - DB 재생성 시 사용자가 만든 템플릿도 삭제됨
   - Production 환경에서는 신중히 진행

3. **서비스 중단**: 
   - Backend 재시작으로 1-2분 서비스 중단

4. **그룹 변경 영향**:
   - Cluster Management에서 그룹 변경 시
   - 기존 Job Templates의 partition이 삭제된 그룹을 참조할 수 있음
   - 템플릿 재검토 필요

## 📝 생성/수정된 파일

### 수정
1. ✅ `backend_5010/database/schema.sql` - 초기 클러스터 설정 추가
2. ✅ `backend_5010/cluster_config_api.py` - 동적 환경변수 체크

### 신규 생성
3. ✅ `verify_groups_sync.py` - 그룹 동기화 검증 스크립트
4. ✅ `sync_cluster_groups.sh` - 자동 동기화 적용 스크립트

### 기존 (변경 없음)
5. ✅ `backend_5010/groups_api.py` - 이미 DB에서 조회하도록 구현됨
6. ✅ `frontend_3010/src/components/JobTemplates/TemplateEditor.tsx` - 이미 동적 파티션 로드

## 🎯 Before vs After

| 항목 | Before | After |
|------|--------|-------|
| **데이터 소스** | 각 API별 Mock 데이터 | DB cluster_config 통합 |
| **동기화** | 불가능 ❌ | 자동 동기화 ✅ |
| **초기 DB** | 비어있음 | 초기 설정 포함 |
| **그룹 변경** | 반영 안 됨 | 즉시 반영 ✅ |
| **환경변수** | 모듈 로드 시 1회 | 매 요청마다 체크 |

## 🔧 문제 해결

### 문제: 동기화 검증 실패

```bash
# 데이터베이스 상태 확인
python3 -c "
import sys
sys.path.insert(0, 'backend_5010')
from database import get_db_connection
with get_db_connection() as conn:
    cursor = conn.cursor()
    cursor.execute('SELECT config FROM cluster_config WHERE id = 1')
    row = cursor.fetchone()
    if row:
        import json
        config = json.loads(row[0])
        print(f\"Groups in DB: {len(config.get('groups', []))}\")
    else:
        print('No cluster config in DB')
"
```

### 문제: API가 여전히 Mock 데이터 반환

```bash
# 환경변수 확인
cat /proc/$(cat backend_5010/.backend.pid)/environ | tr '\0' '\n' | grep MOCK_MODE

# Backend 재시작
cd backend_5010
./stop.sh
export MOCK_MODE=false
./start.sh
```

---

**작성일**: 2025-10-11  
**수정 파일**:
- `backend_5010/database/schema.sql` - 초기 클러스터 설정 추가
- `backend_5010/cluster_config_api.py` - 동적 환경변수 체크

**신규 파일**:
- `verify_groups_sync.py` - 동기화 검증
- `sync_cluster_groups.sh` - 자동 적용

**해결된 문제**:
- Job Templates와 Cluster Management 그룹 불일치
- DB 초기화 시 cluster_config 누락
