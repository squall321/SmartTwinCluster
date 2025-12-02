# Template & Job Submit 통합 구현 계획

**작성일**: 2025-11-14
**목적**: Template v2.0 포맷과 Job Submit 시스템 완전 통합
**현재 상태**: Backend 80% 구현, Frontend 100% 구현, 통합 30%

---

## 📊 Gap 분석 요약

### 이미 구현된 것들 ✅

| 컴포넌트 | 파일 | 완성도 | 비고 |
|---------|------|--------|------|
| POST `/api/jobs/submit` 엔드포인트 | job_submit_api.py:304-421 | 85% | sbatch 실행만 TODO |
| TemplateValidator | template_validator.py | 100% | normalize + file 검증 완벽 |
| Slurm 스크립트 생성 | job_submit_api.py:168-301 | 95% | file_key 매핑 완성 |
| Frontend Template Browser | JobManagement.tsx:424-540 | 100% | 완벽히 작동 |
| Frontend File Upload UI | JobManagement.tsx:907-913 | 100% | file_key 기반 |
| Blueprint 등록 | app.py:275 | 100% | 이미 등록됨 |

### 누락/미완성 항목 ❌

| Gap | 심각도 | 파일 | 라인 | 설명 |
|-----|--------|------|------|------|
| **#1** GET API에 apptainer_normalized 없음 | 🔴 Critical | templates_api_v2.py | 143-165 | Frontend가 Template 선택 시 받지 못함 |
| **#2** POST API sbatch 실행 안됨 | 🔴 Critical | job_submit_api.py | 394-402 | Mock Job ID만 반환 |
| **#3** DB에 Job 기록 없음 | 🟠 Important | job_submit_api.py | 405 | Job 이력 관리 불가 |
| **#4** Frontend normalize fallback 불완전 | 🟡 Medium | JobManagement.tsx | 626-638 | GET API 수정으로 해결됨 |
| **#5** Frontend 파일 사전 검증 없음 | 🟢 Low | JobManagement.tsx | - | Backend만 검증 |

---

## 🎯 종합 구현 계획

### Phase 0: 준비 작업 (1시간)

**목표**: 구현 전 환경 확인 및 백업

**작업 목록**:
1. [ ] 현재 Backend 백업
   ```bash
   cp -r dashboard/backend_5010 dashboard/backend_5010.backup_$(date +%Y%m%d)
   ```

2. [ ] Frontend 백업
   ```bash
   cp -r dashboard/frontend_3010 dashboard/frontend_3010.backup_$(date +%Y%m%d)
   ```

3. [ ] DB 백업
   ```bash
   cp /home/koopark/web_services/backend/dashboard.db \
      /home/koopark/web_services/backend/dashboard.db.backup_$(date +%Y%m%d)
   ```

4. [ ] 테스트 Template 준비
   - `/shared/templates/official/structural/angle_drop_simulation_v2.yaml` 확인
   - 테스트용 작은 STL 파일 준비 (1MB 이하)
   - 테스트용 config.json 준비

5. [ ] 로그 디렉토리 확인
   ```bash
   mkdir -p /shared/logs
   chmod 777 /shared/logs
   ```

**예상 시간**: 1시간

---

### Phase 1: Backend Normalization (Gap #1 해결) ⭐⭐⭐⭐⭐

**목표**: GET API에서 `apptainer_normalized` 반환하도록 수정

**작업 파일**: `dashboard/backend_5010/templates_api_v2.py`

**현재 코드** (Line 143-165):
```python
@templates_v2_bp.route('/api/v2/templates/<template_id>', methods=['GET'])
def get_template(template_id: str):
    try:
        loader = get_template_loader()
        template = loader.get_template(template_id)  # ← Raw YAML만

        if not template:
            return jsonify({'error': 'Template not found'}), 404

        return jsonify(template), 200  # ← normalize 없음
```

**수정 코드**:
```python
from template_validator import TemplateValidator

@templates_v2_bp.route('/api/v2/templates/<template_id>', methods=['GET'])
def get_template(template_id: str):
    """
    템플릿 상세 조회 (정규화 포함)

    Returns:
        JSON: {
            ...template YAML 전체...,
            "apptainer_normalized": {
                "mode": "partition" | "specific" | "any" | "fixed",
                "partition": "compute" | "viz",
                "allowed_images": [...],
                "user_selectable": true/false,
                "bind": [...],
                "env": {...}
            }
        }
    """
    try:
        loader = get_template_loader()
        template = loader.get_template(template_id)

        if not template:
            return jsonify({'error': 'Template not found'}), 404

        # ✅ Template 정규화 추가
        validator = TemplateValidator()
        valid, normalized_template, errors = validator.validate_and_normalize(template)

        if not valid:
            # 검증 실패 시 경고 로그 + 원본 반환
            logger.warning(f"Template {template_id} validation failed: {errors}")
            return jsonify(template), 200  # 원본 반환 (하위 호환)

        # ✅ 정규화된 Template 반환
        return jsonify(normalized_template), 200

    except Exception as e:
        logger.error(f"Failed to get template {template_id}: {e}")
        return jsonify({'error': str(e)}), 500
```

**테스트 방법**:
```bash
# Terminal 1: Backend 재시작
cd dashboard/backend_5010
python app.py

# Terminal 2: API 테스트
curl -X GET http://localhost:5010/api/v2/templates/angle-drop-simulation-v2 | jq .apptainer_normalized

# 예상 결과:
# {
#   "mode": "partition",
#   "partition": "compute",
#   "required": true,
#   "user_selectable": true,
#   "bind": [...],
#   "env": {...}
# }
```

**검증 체크리스트**:
- [ ] `apptainer_normalized` 필드가 응답에 포함되는가?
- [ ] `mode` 값이 올바른가? (partition/specific/any/fixed)
- [ ] Legacy template (image_name만)도 정상 작동하는가? (mode='fixed')
- [ ] 검증 실패 시 원본 template 반환하는가?

**예상 시간**: 1-2시간

---

### Phase 2: Backend Job Submission (Gap #2 해결) ⭐⭐⭐⭐⭐

**목표**: POST API에서 실제로 sbatch 실행하여 Job 제출

**작업 파일**: `dashboard/backend_5010/job_submit_api.py`

**현재 코드** (Line 393-412):
```python
# 7. Slurm에 제출
# TODO: 실제 sbatch 실행
script_path = os.path.join(UPLOAD_DIR, f"job_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sh")
with open(script_path, 'w') as f:
    f.write(script)

logger.info(f"Slurm script generated: {script_path}")

# Mock Job ID (실제로는 sbatch 결과)
job_id = f"mock_{datetime.now().strftime('%Y%m%d%H%M%S')}"

# 8. DB에 Job 정보 저장
# TODO: DB 저장 로직 추가

return jsonify({
    'success': True,
    'job_id': job_id,
    'message': 'Job submitted successfully',
    'script_path': script_path  # 디버깅용
}), 201
```

**수정 코드**:
```python
import subprocess
import shutil

# 7. Slurm 스크립트 저장
# 스크립트 저장 디렉토리 (영구 보관용)
SCRIPT_DIR = '/shared/slurm_scripts'
os.makedirs(SCRIPT_DIR, exist_ok=True)

timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
script_filename = f"job_{job_name}_{timestamp}.sh"
script_path = os.path.join(SCRIPT_DIR, script_filename)

with open(script_path, 'w') as f:
    f.write(script)
os.chmod(script_path, 0o755)  # 실행 권한 부여

logger.info(f"Slurm script saved: {script_path}")

# 8. Slurm에 실제 제출
try:
    result = subprocess.run(
        ['sbatch', script_path],
        capture_output=True,
        text=True,
        check=True,
        timeout=10  # 10초 타임아웃
    )

    # sbatch 출력 파싱 (예: "Submitted batch job 12345")
    output = result.stdout.strip()
    logger.info(f"sbatch output: {output}")

    # Job ID 추출
    if 'Submitted batch job' in output:
        job_id = output.split()[-1]
    else:
        raise ValueError(f"Unexpected sbatch output: {output}")

    logger.info(f"✅ Job submitted successfully: {job_id}")

except subprocess.CalledProcessError as e:
    logger.error(f"sbatch failed: {e.stderr}")
    return jsonify({
        'success': False,
        'error': f'Slurm submission failed: {e.stderr}'
    }), 500

except subprocess.TimeoutExpired:
    logger.error("sbatch timeout")
    return jsonify({
        'success': False,
        'error': 'Slurm submission timeout (10s)'
    }), 500

except Exception as e:
    logger.error(f"sbatch error: {e}")
    return jsonify({
        'success': False,
        'error': f'Slurm submission error: {str(e)}'
    }), 500

# 9. DB에 Job 정보 저장 (Phase 3에서 구현)
# record_job_submission(job_id, template_id, job_name, ...)

return jsonify({
    'success': True,
    'job_id': job_id,
    'script_path': script_path,
    'message': f'Job {job_id} submitted successfully'
}), 201
```

**테스트 방법**:
```bash
# Terminal 1: Slurm 상태 모니터링
watch -n 1 squeue

# Terminal 2: Job 제출 테스트 (Frontend 사용 또는 curl)
# Frontend에서:
# 1. Job Management > Submit Job
# 2. Browse Templates > angle-drop-simulation-v2 선택
# 3. 파일 업로드 (geometry.stl, config.json)
# 4. Submit 버튼 클릭

# curl 테스트:
curl -X POST http://localhost:5010/api/jobs/submit \
  -F "template_id=angle-drop-simulation-v2" \
  -F "apptainer_image_id=KooSimulationPython313" \
  -F "file_geometry=@test.stl" \
  -F "file_config=@test_config.json" \
  -F "slurm_overrides={\"memory\":\"32G\",\"time\":\"02:00:00\"}" \
  -F "job_name=test_job_001"

# 응답 확인
# {
#   "success": true,
#   "job_id": "12345",
#   "script_path": "/shared/slurm_scripts/job_test_job_001_20251114_143022.sh",
#   "message": "Job 12345 submitted successfully"
# }
```

**검증 체크리스트**:
- [ ] Job이 실제로 Slurm Queue에 등록되는가? (`squeue` 확인)
- [ ] Job ID가 정상적으로 반환되는가?
- [ ] 스크립트 파일이 저장되는가? (`/shared/slurm_scripts/` 확인)
- [ ] 스크립트 실행 권한이 설정되는가? (`ls -l` 확인)
- [ ] sbatch 실패 시 에러 메시지가 명확한가?
- [ ] 업로드된 파일이 Job 디렉토리로 복사되는가?
- [ ] 환경 변수가 올바르게 설정되는가? (스크립트 확인)

**예상 시간**: 2-3시간

---

### Phase 3: Job History DB (Gap #3 해결) ⭐⭐⭐

**목표**: Job 제출 이력을 DB에 저장하여 추적 가능하도록

**작업 파일**:
- `dashboard/backend_5010/migrations/v4.4.1_job_history.sql` (새로 생성)
- `dashboard/backend_5010/job_submit_api.py`

**Step 1: DB 스키마 생성**

`migrations/v4.4.1_job_history.sql`:
```sql
-- ============================================
-- Dashboard v4.4.1 Migration
-- Job Submission History
-- 작성일: 2025-11-14
-- ============================================

-- Job 제출 이력 테이블
CREATE TABLE IF NOT EXISTS job_submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Job 정보
    job_id TEXT NOT NULL,                      -- Slurm Job ID
    job_name TEXT NOT NULL,                    -- Job 이름

    -- Template 정보
    template_id TEXT NOT NULL,                 -- Template ID
    template_name TEXT,                        -- Template 이름
    template_version TEXT,                     -- Template 버전

    -- 사용자 정보
    user_id TEXT NOT NULL,                     -- 제출한 사용자
    username TEXT,                             -- 사용자 이름

    -- Slurm 설정
    partition TEXT NOT NULL,                   -- 파티션
    nodes INTEGER,                             -- 노드 수
    cpus INTEGER,                              -- CPU 수
    memory TEXT,                               -- 메모리
    time_limit TEXT,                           -- 시간 제한

    -- Apptainer 정보
    apptainer_image TEXT,                      -- 사용된 이미지

    -- 파일 정보 (JSON)
    uploaded_files TEXT,                       -- {"geometry": {...}, "config": {...}}

    -- 스크립트 정보
    script_path TEXT,                          -- 생성된 스크립트 경로
    script_hash TEXT,                          -- 스크립트 해시 (변조 감지)

    -- 상태 추적
    status TEXT DEFAULT 'submitted',           -- submitted, running, completed, failed, cancelled
    slurm_state TEXT,                          -- Slurm 상태 (PD, R, CG, CD, F, CA 등)
    exit_code INTEGER,                         -- 종료 코드

    -- 타임스탬프
    submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,

    -- 결과 정보
    result_dir TEXT,                           -- 결과 디렉토리
    output_files TEXT,                         -- 출력 파일 목록 (JSON)
    error_message TEXT,                        -- 에러 메시지

    -- 통계
    cpu_time INTEGER,                          -- CPU 시간 (초)
    wall_time INTEGER,                         -- 실제 소요 시간 (초)
    memory_used TEXT,                          -- 사용된 메모리

    -- 인덱스
    FOREIGN KEY (template_id) REFERENCES job_templates_v2(template_id)
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_job_submissions_job_id ON job_submissions(job_id);
CREATE INDEX IF NOT EXISTS idx_job_submissions_user_id ON job_submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_job_submissions_template_id ON job_submissions(template_id);
CREATE INDEX IF NOT EXISTS idx_job_submissions_status ON job_submissions(status);
CREATE INDEX IF NOT EXISTS idx_job_submissions_submitted_at ON job_submissions(submitted_at DESC);

-- 마이그레이션 버전 기록
INSERT OR IGNORE INTO schema_migrations (version, description)
VALUES ('v4.4.1', 'Job Submission History Table');
```

**Step 2: Migration 실행**

```bash
cd dashboard/backend_5010
sqlite3 /home/koopark/web_services/backend/dashboard.db < migrations/v4.4.1_job_history.sql

# 확인
sqlite3 /home/koopark/web_services/backend/dashboard.db "SELECT name FROM sqlite_master WHERE type='table' AND name='job_submissions';"
```

**Step 3: Helper 함수 추가**

`job_submit_api.py`에 추가:
```python
import hashlib
import sqlite3

def get_db_connection():
    """DB 연결 가져오기"""
    db_path = os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db')
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def record_job_submission(
    job_id: str,
    job_name: str,
    template_id: str,
    template: dict,
    user_id: str,
    slurm_config: dict,
    apptainer_image: str,
    uploaded_files: dict,
    script_path: str
) -> int:
    """
    Job 제출 이력 DB에 저장

    Returns:
        int: 생성된 레코드 ID
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    # 스크립트 해시 계산
    with open(script_path, 'rb') as f:
        script_hash = hashlib.sha256(f.read()).hexdigest()[:16]

    try:
        cursor.execute("""
            INSERT INTO job_submissions (
                job_id, job_name, template_id, template_name, template_version,
                user_id, partition, nodes, cpus, memory, time_limit,
                apptainer_image, uploaded_files, script_path, script_hash,
                status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'submitted')
        """, (
            job_id,
            job_name,
            template_id,
            template.get('template', {}).get('name'),
            template.get('template', {}).get('version', '1.0.0'),
            user_id,
            slurm_config.get('partition'),
            slurm_config.get('nodes'),
            slurm_config.get('ntasks'),
            slurm_config.get('mem', slurm_config.get('memory')),
            slurm_config.get('time'),
            apptainer_image,
            json.dumps(uploaded_files),
            script_path,
            script_hash
        ))

        conn.commit()
        record_id = cursor.lastrowid

        logger.info(f"✅ Job submission recorded: ID={record_id}, Job={job_id}")
        return record_id

    except Exception as e:
        logger.error(f"Failed to record job submission: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()
```

**Step 4: POST 엔드포인트에 통합**

`job_submit_api.py`의 `submit_job()` 함수 수정:
```python
@job_submit_bp.route('/api/jobs/submit', methods=['POST'])
@jwt_required  # 인증 필요
def submit_job():
    try:
        # ... (기존 코드) ...

        # sbatch 실행 후
        job_id = output.split()[-1]

        # ✅ DB에 Job 기록
        user_id = g.get('user', {}).get('id', 'anonymous')  # JWT에서 가져옴

        record_job_submission(
            job_id=job_id,
            job_name=job_name,
            template_id=template_id,
            template=normalized_template,
            user_id=user_id,
            slurm_config=slurm_config,
            apptainer_image=image['path'],
            uploaded_files=uploaded_files,
            script_path=script_path
        )

        return jsonify({
            'success': True,
            'job_id': job_id,
            'script_path': script_path,
            'message': f'Job {job_id} submitted successfully'
        }), 201

    except Exception as e:
        # 에러 처리
        pass
```

**테스트 방법**:
```bash
# Job 제출
# (Phase 2와 동일)

# DB 확인
sqlite3 /home/koopark/web_services/backend/dashboard.db <<EOF
SELECT
    job_id, job_name, template_id, status,
    submitted_at
FROM job_submissions
ORDER BY submitted_at DESC
LIMIT 5;
EOF
```

**검증 체크리스트**:
- [ ] Job 제출 시 DB에 레코드 생성되는가?
- [ ] 모든 필드가 올바르게 저장되는가?
- [ ] 스크립트 해시가 계산되는가?
- [ ] user_id가 JWT에서 추출되는가?
- [ ] 인덱스가 정상 작동하는가? (조회 성능)

**예상 시간**: 2-3시간

---

### Phase 4: Integration Testing ⭐⭐⭐⭐

**목표**: Frontend-Backend 전체 플로우 통합 테스트

**테스트 시나리오**:

#### Scenario 1: 정상 Job 제출 (Partition Mode)

**Template**: angle-drop-simulation-v2.yaml (apptainer.image_selection.mode = partition)

**Steps**:
1. Frontend에서 Job Management > Submit Job 클릭
2. "Browse Templates" 버튼 클릭
3. "전각도 낙하 시뮬레이션 (개선)" 선택
4. Frontend에서 `apptainer_normalized` 확인:
   - `mode: "partition"`
   - `partition: "compute"`
   - `user_selectable: true`
5. Apptainer 이미지 선택 UI 표시 확인 (compute 파티션 이미지만)
6. "KooSimulationPython313.sif" 선택
7. 파일 업로드:
   - 형상 파일 (geometry): test.stl (1MB)
   - 설정 파일 (config): test_config.json (1KB)
8. Slurm 파라미터 입력:
   - Memory: 32G
   - Time: 02:00:00
9. "Submit Job" 클릭
10. 성공 메시지 확인: "Job 12345 submitted successfully"

**예상 결과**:
- ✅ Template 선택 시 apptainer_normalized 로드됨
- ✅ Apptainer 이미지 선택 UI 정상 표시
- ✅ 파일 업로드 성공
- ✅ Job이 Slurm에 제출됨 (`squeue`에 표시)
- ✅ DB에 job_submissions 레코드 생성됨
- ✅ 스크립트 파일 생성됨 (`/shared/slurm_scripts/`)

**검증 명령**:
```bash
# Slurm Queue 확인
squeue

# DB 확인
sqlite3 /home/koopark/web_services/backend/dashboard.db \
  "SELECT job_id, job_name, status FROM job_submissions ORDER BY id DESC LIMIT 1;"

# 스크립트 확인
ls -lh /shared/slurm_scripts/ | tail -1

# 스크립트 내용 확인 (환경 변수)
grep "FILE_GEOMETRY" /shared/slurm_scripts/job_*.sh | tail -1
grep "FILE_CONFIG" /shared/slurm_scripts/job_*.sh | tail -1
```

#### Scenario 2: Legacy Template (Fixed Mode)

**Template**: 기존 v1.0 템플릿 (apptainer.image_name만 있음)

**Steps**:
1-3. (동일)
4. Frontend에서 `apptainer_normalized` 확인:
   - `mode: "fixed"`
   - `image_name: "KooSimulationPython313.sif"`
   - `user_selectable: false`
5. Apptainer 이미지 선택 UI 표시 **안됨** (고정 이미지)
6. (이미지 선택 skip)
7-10. (동일)

**예상 결과**:
- ✅ Legacy template도 정상 작동
- ✅ apptainer_normalized.mode = "fixed"
- ✅ 이미지 선택 UI 숨겨짐

#### Scenario 3: 파일 검증 실패

**Steps**:
1-6. (동일)
7. 잘못된 파일 업로드:
   - 형상 파일: test.txt (STL 아님)
   - 설정 파일: test.xml (JSON 아님)
8. "Submit Job" 클릭
9. 에러 메시지 확인

**예상 결과**:
- ❌ Backend에서 파일 검증 실패
- ❌ "File validation failed: Invalid file extension" 에러
- ❌ Job 제출 안됨

#### Scenario 4: 필수 파일 누락

**Steps**:
1-6. (동일)
7. 파일 중 하나만 업로드:
   - 형상 파일만 업로드 (설정 파일 누락)
8. "Submit Job" 버튼 **비활성화** 확인

**예상 결과**:
- ✅ Frontend에서 Submit 버튼 비활성화 (Line 1097-1102)
- ✅ Tooltip: "Required files: 2, Uploaded: 1"

#### Scenario 5: sbatch 실패

**Steps**:
1-8. (동일)
9. Backend에서 sbatch 실행 시 실패 시뮬레이션 (Slurm 다운 등)

**예상 결과**:
- ❌ "Slurm submission failed: ..." 에러
- ❌ HTTP 500 응답
- ❌ DB에 레코드 생성 안됨

**테스트 체크리스트**:
- [ ] Scenario 1 성공
- [ ] Scenario 2 성공
- [ ] Scenario 3 성공 (적절한 에러)
- [ ] Scenario 4 성공 (버튼 비활성화)
- [ ] Scenario 5 성공 (적절한 에러)
- [ ] 모든 시나리오에서 로그 정상 출력
- [ ] 메모리 누수 없음 (여러 번 반복 테스트)

**예상 시간**: 4-6시간

---

### Phase 5: Production Hardening ⭐⭐⭐

**목표**: 에러 처리, 로깅, 보안 강화

**작업 목록**:

#### 5-1. 에러 처리 강화 (2시간)

**파일**: `job_submit_api.py`

**개선 사항**:
1. **파일 크기 제한**:
   ```python
   MAX_FILE_SIZE = 5 * 1024 * 1024 * 1024  # 5GB

   for key in request.files:
       file = request.files[key]
       file.seek(0, os.SEEK_END)
       size = file.tell()
       file.seek(0)

       if size > MAX_FILE_SIZE:
           return jsonify({
               'success': False,
               'error': f'File too large: {file.filename} ({size / 1024 / 1024:.1f}MB > 5GB)'
           }), 413
   ```

2. **타임아웃 설정**:
   ```python
   # sbatch 타임아웃: 30초
   result = subprocess.run(['sbatch', script_path], timeout=30, ...)
   ```

3. **디스크 공간 확인**:
   ```python
   import shutil

   def check_disk_space(path='/shared', min_free_gb=10):
       """디스크 여유 공간 확인"""
       stat = shutil.disk_usage(path)
       free_gb = stat.free / (1024 ** 3)
       if free_gb < min_free_gb:
           raise RuntimeError(f"Insufficient disk space: {free_gb:.1f}GB < {min_free_gb}GB")

   # Job 제출 전 확인
   check_disk_space()
   ```

4. **Concurrent Request 제한**:
   ```python
   from threading import Semaphore

   # 동시 Job 제출 제한 (10개)
   job_submit_semaphore = Semaphore(10)

   @job_submit_bp.route('/api/jobs/submit', methods=['POST'])
   def submit_job():
       if not job_submit_semaphore.acquire(blocking=False):
           return jsonify({
               'success': False,
               'error': 'Too many concurrent job submissions. Please try again later.'
           }), 429

       try:
           # ... Job 제출 로직 ...
       finally:
           job_submit_semaphore.release()
   ```

#### 5-2. 로깅 강화 (1시간)

**파일**: `job_submit_api.py`

```python
import logging

# 구조화된 로깅
logger = logging.getLogger('job_submit')
logger.setLevel(logging.INFO)

# 파일 핸들러
handler = logging.FileHandler('/shared/logs/job_submit.log')
handler.setFormatter(logging.Formatter(
    '[%(asctime)s] %(levelname)s [%(name)s.%(funcName)s:%(lineno)d] %(message)s'
))
logger.addHandler(handler)

@job_submit_bp.route('/api/jobs/submit', methods=['POST'])
def submit_job():
    request_id = str(uuid.uuid4())[:8]
    logger.info(f"[{request_id}] Job submission started")

    try:
        # Template 로드
        logger.info(f"[{request_id}] Loading template: {template_id}")
        template = load_template(template_id)

        # 파일 업로드
        logger.info(f"[{request_id}] Processing {len(uploaded_files)} files")

        # Slurm 제출
        logger.info(f"[{request_id}] Submitting to Slurm: {script_path}")
        result = subprocess.run(...)

        logger.info(f"[{request_id}] ✅ Job submitted: {job_id}")
        return jsonify(...), 201

    except Exception as e:
        logger.error(f"[{request_id}] ❌ Job submission failed: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500
```

#### 5-3. 보안 강화 (2시간)

**개선 사항**:

1. **파일 경로 검증** (Path Traversal 방지):
   ```python
   import os.path

   def secure_path(path, base_dir='/tmp/slurm_uploads'):
       """경로 검증 (디렉토리 탈출 방지)"""
       real_path = os.path.realpath(path)
       real_base = os.path.realpath(base_dir)

       if not real_path.startswith(real_base):
           raise ValueError(f"Path traversal detected: {path}")

       return real_path

   # 사용
   temp_path = save_uploaded_file(file)
   temp_path = secure_path(temp_path)
   ```

2. **Filename Sanitization 강화**:
   ```python
   import re

   def ultra_secure_filename(filename):
       """파일명 안전하게 정리"""
       # 확장자 분리
       name, ext = os.path.splitext(filename)

       # 특수문자 제거 (알파벳, 숫자, _, -만 허용)
       name = re.sub(r'[^a-zA-Z0-9_-]', '_', name)

       # 길이 제한 (100자)
       name = name[:100]

       # 빈 이름 방지
       if not name:
           name = 'unnamed'

       return name + ext
   ```

3. **JWT 권한 확인**:
   ```python
   @job_submit_bp.route('/api/jobs/submit', methods=['POST'])
   @jwt_required
   def submit_job():
       user = g.get('user')

       # 사용자 권한 확인
       if not user:
           return jsonify({'success': False, 'error': 'Unauthorized'}), 401

       # 역할 기반 제한 (선택사항)
       allowed_roles = ['admin', 'researcher', 'student']
       if user.get('role') not in allowed_roles:
           return jsonify({
               'success': False,
               'error': 'Insufficient permissions'
           }), 403

       # ... Job 제출 로직 ...
   ```

4. **Script Injection 방지**:
   ```python
   def sanitize_slurm_script(script: str) -> str:
       """Slurm 스크립트 위험 패턴 제거"""
       # 위험한 패턴 목록
       dangerous_patterns = [
           r'rm\s+-rf\s+/',        # 시스템 삭제
           r'chmod\s+777',         # 권한 변경
           r'curl.*\|.*sh',        # 원격 스크립트 실행
           r'wget.*\|.*sh',
           r'nc\s+-l',             # Reverse shell
       ]

       for pattern in dangerous_patterns:
           if re.search(pattern, script, re.IGNORECASE):
               raise ValueError(f"Dangerous pattern detected: {pattern}")

       return script

   # 사용
   script = generate_slurm_script(...)
   script = sanitize_slurm_script(script)
   ```

**검증 체크리스트**:
- [ ] 5GB 파일 업로드 시 413 에러
- [ ] 디스크 부족 시 에러
- [ ] 동시 11개 제출 시 429 에러
- [ ] 로그 파일 생성 (`/shared/logs/job_submit.log`)
- [ ] Path traversal 공격 차단 (../../../etc/passwd)
- [ ] 위험한 스크립트 차단 (rm -rf /)

**예상 시간**: 5시간

---

### Phase 6: Advanced Features (선택사항) ⭐⭐

**목표**: 사용자 경험 개선을 위한 추가 기능

#### 6-1. Script Preview (2시간)

**목표**: Job 제출 전 생성될 스크립트 미리보기

**새 엔드포인트**: `GET /api/jobs/preview`

**파일**: `job_submit_api.py`

```python
@job_submit_bp.route('/api/jobs/preview', methods=['POST'])
@jwt_required
def preview_script():
    """
    Slurm 스크립트 미리보기 (제출 없이 생성만)

    Request: JSON (multipart 대신 JSON 사용)
        {
            "template_id": "angle-drop-simulation-v2",
            "apptainer_image_id": "KooSimulationPython313",
            "job_name": "test_job",
            "slurm_overrides": {"memory": "32G"}
        }

    Response:
        {
            "success": true,
            "script": "#!/bin/bash\n#SBATCH ...",
            "warnings": ["File 'geometry' not uploaded (preview mode)"]
        }
    """
    try:
        data = request.get_json()
        template_id = data.get('template_id')

        # Template 로드 및 정규화
        template = load_template(template_id)
        validator = TemplateValidator()
        valid, normalized_template, errors = validator.validate_and_normalize(template)

        if not valid:
            return jsonify({'success': False, 'errors': errors}), 400

        # 이미지 정보
        apptainer_image_id = data.get('apptainer_image_id')
        apptainer_config = normalized_template['apptainer_normalized']

        if apptainer_config['user_selectable']:
            image = get_apptainer_image(apptainer_image_id)
        else:
            image = get_apptainer_image_by_name(apptainer_config['image_name'])

        # Mock 파일 정보 (실제 파일 없이 Preview)
        mock_files = {}
        for required_file in normalized_template.get('files', {}).get('input_schema', {}).get('required', []):
            file_key = required_file['file_key']
            mock_files[file_key] = {
                'path': f'/mock/path/{file_key}.dat',
                'filename': f'{file_key}.dat',
                'size': 1024
            }

        # 스크립트 생성
        script = generate_slurm_script(
            template=normalized_template,
            job_config={
                'apptainer_image_path': image['path'],
                'uploaded_files': mock_files,
                'slurm_overrides': data.get('slurm_overrides', {}),
                'job_name': data.get('job_name', 'preview_job')
            }
        )

        warnings = []
        for file_key in mock_files:
            warnings.append(f"File '{file_key}' not uploaded (preview mode)")

        return jsonify({
            'success': True,
            'script': script,
            'warnings': warnings
        }), 200

    except Exception as e:
        logger.error(f"Script preview failed: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
```

**Frontend 통합**:

`JobManagement.tsx`에 Preview 버튼 추가:
```typescript
const [showPreview, setShowPreview] = useState(false);
const [previewScript, setPreviewScript] = useState('');

const handlePreview = async () => {
  const response = await fetch(`${API_CONFIG.BASE_URL}/api/jobs/preview`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    },
    body: JSON.stringify({
      template_id: selectedTemplateForJob.template_id,
      apptainer_image_id: selectedApptainerImage?.id,
      job_name: formData.jobName,
      slurm_overrides: { memory: formData.memory, time: formData.time }
    })
  });

  const data = await response.json();
  if (data.success) {
    setPreviewScript(data.script);
    setShowPreview(true);
  }
};

// UI
<button
  type="button"
  onClick={handlePreview}
  className="px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700"
>
  Preview Script
</button>

{showPreview && (
  <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
    <div className="bg-white rounded-lg p-6 max-w-4xl w-full max-h-[80vh] overflow-y-auto">
      <h3 className="text-xl font-bold mb-4">Slurm Script Preview</h3>
      <pre className="bg-gray-100 p-4 rounded overflow-x-auto text-sm">
        {previewScript}
      </pre>
      <button onClick={() => setShowPreview(false)}>Close</button>
    </div>
  </div>
)}
```

#### 6-2. Frontend 파일 사전 검증 (2시간)

**목표**: 파일 업로드 전 Frontend에서 검증하여 불필요한 업로드 방지

`components/JobManagement/TemplateFileUpload.tsx` 수정:

```typescript
const validateFile = (file: File, schema: FileSchema): { valid: boolean; error?: string } => {
  // 파일 크기 검증
  const maxSizeStr = schema.max_size || '1GB';
  const maxSizeBytes = parseSize(maxSizeStr);  // "500MB" → 524288000

  if (file.size > maxSizeBytes) {
    return {
      valid: false,
      error: `File too large: ${(file.size / 1024 / 1024).toFixed(1)}MB > ${maxSizeStr}`
    };
  }

  // 확장자 검증
  const allowedExtensions = schema.validation?.extensions || [];
  const fileExt = '.' + file.name.split('.').pop()?.toLowerCase();

  if (allowedExtensions.length > 0 && !allowedExtensions.includes(fileExt)) {
    return {
      valid: false,
      error: `Invalid file extension: ${fileExt}. Allowed: ${allowedExtensions.join(', ')}`
    };
  }

  // MIME 타입 검증 (선택사항)
  const allowedMimeTypes = schema.validation?.mime_types || [];
  if (allowedMimeTypes.length > 0 && !allowedMimeTypes.includes(file.type)) {
    return {
      valid: false,
      error: `Invalid file type: ${file.type}. Allowed: ${allowedMimeTypes.join(', ')}`
    };
  }

  return { valid: true };
};

// 파일 선택 시
const handleFileSelect = (event: React.ChangeEvent<HTMLInputElement>, fileSchema: FileSchema) => {
  const file = event.target.files?.[0];
  if (!file) return;

  // 사전 검증
  const validation = validateFile(file, fileSchema);
  if (!validation.valid) {
    toast.error(validation.error);
    event.target.value = '';  // 파일 입력 초기화
    return;
  }

  // 검증 통과 시 업로드
  setTemplateFiles([...templateFiles, { file_key: fileSchema.file_key, file }]);
  toast.success(`File selected: ${file.name}`);
};
```

#### 6-3. Job 비용 견적 (4시간)

**목표**: Job 제출 전 예상 비용 표시

**파일**: `job_submit_api.py`

```python
def estimate_job_cost(slurm_config: dict) -> dict:
    """
    Job 비용 견적

    Returns:
        {
            "cpu_hours": 128,  # 코어-시간
            "cost_krw": 12800,  # 원 (100원/코어-시간 가정)
            "estimated_completion": "2025-11-14 16:30:00"
        }
    """
    nodes = slurm_config.get('nodes', 1)
    cpus_per_task = slurm_config.get('cpus_per_task', 1)
    ntasks = slurm_config.get('ntasks', 1)
    time_str = slurm_config.get('time', '01:00:00')

    # 총 코어 수
    total_cores = nodes * ntasks * cpus_per_task

    # 시간 파싱 (HH:MM:SS)
    h, m, s = map(int, time_str.split(':'))
    time_hours = h + m / 60 + s / 3600

    # 코어-시간
    cpu_hours = total_cores * time_hours

    # 비용 (100원/코어-시간 가정)
    COST_PER_CORE_HOUR = 100
    cost_krw = int(cpu_hours * COST_PER_CORE_HOUR)

    # 예상 완료 시간
    estimated_completion = (datetime.now() + timedelta(hours=time_hours)).strftime('%Y-%m-%d %H:%M:%S')

    return {
        'cpu_hours': cpu_hours,
        'cost_krw': cost_krw,
        'estimated_completion': estimated_completion
    }

@job_submit_bp.route('/api/jobs/estimate', methods=['POST'])
@jwt_required
def estimate_cost():
    """비용 견적 API"""
    try:
        data = request.get_json()
        template_id = data.get('template_id')

        template = load_template(template_id)
        slurm_config = template['slurm'].copy()
        slurm_config.update(data.get('slurm_overrides', {}))

        estimate = estimate_job_cost(slurm_config)

        return jsonify({
            'success': True,
            'estimate': estimate
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
```

**Frontend 통합**:
```typescript
const [costEstimate, setCostEstimate] = useState(null);

useEffect(() => {
  if (selectedTemplateForJob && formData.memory && formData.time) {
    // 비용 견적 요청
    fetch(`${API_CONFIG.BASE_URL}/api/jobs/estimate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        template_id: selectedTemplateForJob.template_id,
        slurm_overrides: { memory: formData.memory, time: formData.time }
      })
    })
      .then(res => res.json())
      .then(data => setCostEstimate(data.estimate));
  }
}, [selectedTemplateForJob, formData.memory, formData.time]);

// UI
{costEstimate && (
  <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
    <div className="text-sm font-semibold text-blue-900">예상 비용</div>
    <div className="text-xs text-blue-700 space-y-1 mt-1">
      <div>• 코어-시간: {costEstimate.cpu_hours}h</div>
      <div>• 예상 비용: ₩{costEstimate.cost_krw.toLocaleString()}</div>
      <div>• 예상 완료: {costEstimate.estimated_completion}</div>
    </div>
  </div>
)}
```

**예상 시간**: 8시간 (모두 선택사항)

---

### Phase 7: Documentation & Cleanup ⭐

**목표**: 문서화 및 코드 정리

**작업 목록**:

1. **API 문서 작성** (2시간):
   - OpenAPI/Swagger 스펙 작성
   - Endpoint별 Request/Response 예시
   - 에러 코드 정의

2. **코드 주석 보강** (1시간):
   - Docstring 추가/수정
   - 복잡한 로직 설명

3. **README 업데이트** (1시간):
   - 설치 가이드
   - 사용 예시
   - 트러블슈팅

4. **임시 파일 정리** (30분):
   ```bash
   # 오래된 임시 파일 삭제 (7일 이상)
   find /tmp/slurm_uploads -type f -mtime +7 -delete

   # Cron 등록 (매일 자정)
   0 0 * * * find /tmp/slurm_uploads -type f -mtime +7 -delete
   ```

5. **테스트 케이스 작성** (2시간):
   - Unit Test (pytest)
   - Integration Test
   - Frontend E2E Test (Playwright/Cypress)

**예상 시간**: 6.5시간

---

## 📅 전체 Timeline 요약

| Phase | 설명 | 예상 시간 | 우선순위 | 누적 시간 |
|-------|------|-----------|----------|-----------|
| **Phase 0** | 준비 작업 | 1h | ⭐⭐⭐⭐⭐ | 1h |
| **Phase 1** | Backend Normalization | 2h | ⭐⭐⭐⭐⭐ | 3h |
| **Phase 2** | Backend Job Submission | 3h | ⭐⭐⭐⭐⭐ | 6h |
| **Phase 3** | Job History DB | 3h | ⭐⭐⭐ | 9h |
| **Phase 4** | Integration Testing | 6h | ⭐⭐⭐⭐ | 15h |
| **Phase 5** | Production Hardening | 5h | ⭐⭐⭐ | 20h |
| **Phase 6** | Advanced Features | 8h | ⭐⭐ (선택) | 28h |
| **Phase 7** | Documentation | 6.5h | ⭐ (선택) | 34.5h |

**Core 기능 완성** (Phase 0-4): **15시간**
**Production Ready** (Phase 0-5): **20시간**
**Full Feature** (Phase 0-7): **34.5시간**

---

## 🎯 권장 작업 순서

### Week 1: Core Integration (15h)

**Day 1-2 (6h)**:
- Phase 0: 준비 작업 (1h)
- Phase 1: Backend Normalization (2h)
- Phase 2: Backend Job Submission (3h)

**Day 3 (3h)**:
- Phase 3: Job History DB (3h)

**Day 4-5 (6h)**:
- Phase 4: Integration Testing (6h)

**Milestone**: Template 기반 Job 제출 완전 작동

### Week 2: Production Hardening (5h)

**Day 1-2 (5h)**:
- Phase 5: Production Hardening (5h)

**Milestone**: 프로덕션 배포 가능

### Week 3+: Advanced Features (선택, 14.5h)

**Day 1-2 (8h)**:
- Phase 6: Advanced Features (8h)

**Day 3 (6.5h)**:
- Phase 7: Documentation (6.5h)

**Milestone**: 완전한 엔터프라이즈 기능

---

## ✅ 체크리스트 (Phase별)

### Phase 1 완료 조건
- [ ] GET `/api/v2/templates/{id}` 응답에 `apptainer_normalized` 포함
- [ ] `mode` 값이 정확함 (partition/specific/any/fixed)
- [ ] Legacy template 정상 작동
- [ ] Frontend에서 Template 선택 시 apptainer_normalized 로드됨

### Phase 2 완료 조건
- [ ] POST `/api/jobs/submit` 실행 시 실제 sbatch 호출
- [ ] Job ID가 Slurm에서 반환됨
- [ ] `squeue`에 Job 표시됨
- [ ] 스크립트 파일 생성됨 (`/shared/slurm_scripts/`)
- [ ] 환경 변수 올바르게 설정됨

### Phase 3 완료 조건
- [ ] `job_submissions` 테이블 생성됨
- [ ] Job 제출 시 DB에 레코드 저장됨
- [ ] 모든 필드 정상 저장 확인
- [ ] 인덱스 정상 작동

### Phase 4 완료 조건
- [ ] 모든 시나리오 테스트 통과
- [ ] Frontend-Backend 완전 통합
- [ ] 에러 케이스 적절히 처리됨
- [ ] 로그 정상 출력

### Phase 5 완료 조건
- [ ] 파일 크기 제한 작동
- [ ] 디스크 공간 확인 작동
- [ ] Concurrent request 제한 작동
- [ ] 로그 파일 생성
- [ ] 보안 검증 통과

---

## 🚨 Risk & Mitigation

| Risk | 확률 | 영향 | Mitigation |
|------|------|------|------------|
| Slurm 다운 시 테스트 불가 | 🟡 Medium | 🔴 High | Mock sbatch 구현, Docker Slurm 환경 |
| DB Migration 실패 | 🟢 Low | 🟠 Medium | 백업 철저, 롤백 스크립트 준비 |
| Frontend-Backend 데이터 불일치 | 🟡 Medium | 🟠 Medium | Type 정의 공유, Integration Test |
| 대용량 파일 업로드 타임아웃 | 🟠 High | 🟡 Low | 청크 업로드 (Phase 6) |
| 디스크 공간 부족 | 🟢 Low | 🔴 High | 공간 모니터링, 자동 정리 |

---

## 📊 성공 지표

**기술적 지표**:
- ✅ Template 선택 → Job 제출 성공률 > 95%
- ✅ API 응답 시간 < 2초 (파일 업로드 제외)
- ✅ Job 제출 후 Slurm Queue 등록률 100%
- ✅ DB 기록 정확도 100%
- ✅ 에러 핸들링 커버리지 > 90%

**사용자 경험 지표**:
- ✅ Template 선택부터 Job 제출까지 < 2분
- ✅ 에러 메시지 명확성 (사용자 이해 가능)
- ✅ 파일 업로드 진행률 표시
- ✅ Job 상태 실시간 확인 가능

---

**최종 목표**:
> **"Browse Templates 버튼 클릭 → Template 선택 → 파일 업로드 → Submit → Job 실행"**
> **전체 플로우가 100% 작동하는 Production Ready 시스템**

**예상 완성 시간**: **Core 15시간, Production Ready 20시간**
