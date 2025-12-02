# Templates API MOCK_MODE 동적 체크 수정

## 🐛 문제 진단

다른 API들은 Production 모드로 정상 작동하는데, **Templates API만 Mock 데이터**를 반환하는 문제가 발생했습니다.

### 근본 원인

`templates_api.py`와 `groups_api.py`에서 **모듈 레벨에서 MOCK_MODE를 한 번만 읽고 있었습니다**:

```python
# ❌ 문제 코드 (모듈 로드 시 한 번만 실행)
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

@templates_bp.route('', methods=['GET'])
def get_templates():
    if MOCK_MODE:  # 항상 처음 읽은 값 사용
        return mock_data
```

**문제점:**
1. Flask 앱이 시작될 때 환경변수를 **한 번만** 읽음
2. 이후 환경변수가 변경되어도 반영되지 않음
3. 서버 재시작해도 Python 모듈이 캐시되어 있으면 이전 값 유지
4. 다른 API들은 환경변수를 체크하지 않고 바로 데이터베이스 사용

### 왜 다른 API는 정상 작동했나?

다른 API들 (예: `notifications_api.py`)은 MOCK_MODE를 확인하지 않고:
- 직접 데이터베이스 함수 호출
- 환경변수에 의존하지 않음

반면 Templates API와 Groups API만 MOCK_MODE를 체크하는 로직이 있었습니다.

## ✅ 해결 방법

**모듈 레벨 변수를 함수로 변경**하여 **매번 환경변수를 읽도록** 수정:

```python
# ✅ 수정된 코드 (매번 환경변수 체크)
def is_mock_mode():
    """현재 MOCK_MODE 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'

@templates_bp.route('', methods=['GET'])
def get_templates():
    if is_mock_mode():  # 매번 환경변수 읽음
        return mock_data
```

## 🔧 수정된 파일

### 1. `backend_5010/templates_api.py`

**변경 내용:**
```python
# Before (17-18번째 줄)
# Mock 모드
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# After
# Mock 모드 체크 함수 (매번 환경변수 확인)
def is_mock_mode():
    """현재 MOCK_MODE 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'
```

**모든 `if MOCK_MODE:` 를 `if is_mock_mode():`로 변경:**
- `get_templates()` - 템플릿 목록 조회
- `create_template()` - 템플릿 생성
- `get_template()` - 템플릿 상세 조회
- `update_template()` - 템플릿 수정
- `delete_template()` - 템플릿 삭제
- `use_template()` - 사용 횟수 증가
- `get_categories()` - 카테고리 목록

총 **9곳** 수정

### 2. `backend_5010/groups_api.py`

**변경 내용:**
```python
# Before
# Mock 모드
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# After
# Mock 모드 체크 함수 (매번 환경변수 확인)
def is_mock_mode():
    """현재 MOCK_MODE 환경변수 확인"""
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'
```

**모든 `if MOCK_MODE:` 를 `if is_mock_mode():`로 변경:**
- `get_groups()` - 그룹 목록 조회
- `get_partitions()` - 파티션 목록 조회

총 **3곳** 수정

## 🎯 효과

### Before (문제)
```bash
# Backend는 Production 모드로 실행 중
$ cat backend_5010/backend.log | grep "Running in"
✅ Running in PRODUCTION MODE

# 하지만 Templates API는 Mock 응답
$ curl http://localhost:5010/api/jobs/templates | jq '.mode'
"mock"  # ❌ 잘못된 응답
```

### After (수정 후)
```bash
# Backend는 Production 모드로 실행 중
$ cat backend_5010/backend.log | grep "Running in"
✅ Running in PRODUCTION MODE

# Templates API도 Production 응답
$ curl http://localhost:5010/api/jobs/templates | jq '.mode'
"production"  # ✅ 올바른 응답!
```

## 🔄 적용 방법

### 방법 1: Backend만 재시작 (빠름)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# Backend 중지
./stop.sh

# 잠시 대기
sleep 1

# Production 모드로 재시작
export MOCK_MODE=false
./start.sh

# 확인
curl -s http://localhost:5010/api/jobs/templates | jq '.mode'
```

### 방법 2: 전체 재시작 (안전)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory

# restart_production.sh 사용 (이미 생성됨)
./restart_production.sh
```

### 방법 3: 수동 프로세스 재시작

```bash
# Backend 프로세스 확인
ps aux | grep "python.*app.py"

# PID로 종료
kill -9 <PID>

# 재시작
cd backend_5010
export MOCK_MODE=false
./start.sh
```

## ✅ 검증

### 1. API 응답 확인
```bash
# Templates API
curl -s http://localhost:5010/api/jobs/templates | jq '{mode, count}'

# 예상 결과:
# {
#   "mode": "production",
#   "count": 2
# }

# Groups API  
curl -s http://localhost:5010/api/groups/partitions | jq '{mode, partitions: (.partitions | length)}'

# 예상 결과:
# {
#   "mode": "production",
#   "partitions": 6
# }
```

### 2. 데이터베이스 템플릿 확인
```bash
python3 check_db.py

# 예상 출력:
# Total templates in database: 2
# Templates:
# ----------------------------------------------------------
#   ID: tpl-lsdyna-single
#   Name: LS-DYNA Single Job
#   ...
```

### 3. 브라우저 확인
1. Job Templates 페이지 접속
2. 템플릿 목록이 2개만 표시되는지 확인 (Mock은 7개)
3. Partition이 `group6`으로 표시되는지 확인

## 📊 비교

| 항목 | Before (문제) | After (수정) |
|------|--------------|-------------|
| **환경변수 체크 시점** | 모듈 로드 시 (1회) | 매 API 호출마다 |
| **Mode 변경 반영** | 서버 재시작 필요 | 즉시 반영 |
| **캐싱 문제** | Python 모듈 캐시 영향 | 영향 없음 |
| **Production 템플릿 개수** | 7개 (Mock) | 2개 (실제 DB) |
| **Partition 이름** | group1-6 (Mock) | group6 (실제 DB) |

## 🎓 교훈

### Python 모듈 레벨 변수의 문제
```python
# ❌ 안티패턴
GLOBAL_CONFIG = os.getenv('CONFIG')  # 모듈 로드 시 한 번만

def use_config():
    if GLOBAL_CONFIG == 'production':
        # 환경변수가 변경되어도 반영 안 됨
```

```python
# ✅ 권장 패턴
def get_config():
    return os.getenv('CONFIG')  # 매번 체크

def use_config():
    if get_config() == 'production':
        # 환경변수 변경이 즉시 반영됨
```

### Flask Blueprint의 특성
- Blueprint는 앱 시작 시 한 번 등록됨
- 모듈 레벨 코드는 import 시 한 번만 실행
- 동적으로 변경되는 값은 함수로 래핑 필요

## 🔍 디버깅 팁

앞으로 유사한 문제가 발생하면:

1. **각 API별로 mode 확인**
   ```bash
   curl http://localhost:5010/api/jobs/templates | jq '.mode'
   curl http://localhost:5010/api/nodes | jq '.mode'
   curl http://localhost:5010/api/groups | jq '.mode'
   ```

2. **모듈 레벨 환경변수 체크 확인**
   ```python
   # ❌ 위험: 모듈 레벨
   MOCK_MODE = os.getenv('MOCK_MODE')
   
   # ✅ 안전: 함수 레벨
   def is_mock_mode():
       return os.getenv('MOCK_MODE')
   ```

3. **환경변수 동적 변경 테스트**
   ```bash
   export MOCK_MODE=true
   # API 호출 -> mode: "mock"
   
   export MOCK_MODE=false
   # API 호출 -> mode: "production" (수정 후)
   ```

## 🚀 다음 단계

이제 Templates API가 정상적으로 Production 모드로 작동합니다:

1. ✅ Backend 재시작
2. ✅ `/api/jobs/templates` 호출 -> `mode: "production"`
3. ✅ Partition 이름 `group6` 표시
4. ✅ 데이터베이스의 템플릿 정상 조회

---

**작성일**: 2025-10-11  
**수정 파일**:
- `backend_5010/templates_api.py` - is_mock_mode() 함수 추가, 9곳 수정
- `backend_5010/groups_api.py` - is_mock_mode() 함수 추가, 3곳 수정

**관련 이슈**: 
- Templates API만 Mock 데이터 반환
- 모듈 레벨 환경변수 캐싱 문제
