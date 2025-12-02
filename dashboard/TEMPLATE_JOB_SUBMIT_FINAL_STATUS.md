# Template Job Submit - Final Implementation Status

**작성일**: 2025-11-14
**버전**: v2.0 Complete
**상태**: ✅ Production Ready

---

## 📊 구현 완료 요약

| Phase | 기능 | 상태 | 비고 |
|-------|------|------|------|
| **Phase 0-3** | Core Functionality | ✅ 완료 | GET normalize, POST sbatch, DB recording |
| **Phase 4** | Integration Testing | ✅ 완료 | 전체 플로우 검증 완료 |
| **Phase 4.5** | Warnings Fix | ✅ 완료 | Partition, memory 수정 |
| **Phase 5** | Production Hardening | ✅ 완료 | 에러 처리, 로깅, 보안 |
| **Phase 6** | Advanced Features | ✅ 완료 | Script preview, cost estimation |
| **Phase 7** | Documentation | ✅ 완료 | API 문서, 사용 가이드 |

**전체 완성도**: 100% (Production Ready)

---

## 🎯 핵심 기능

### 1. Template 기반 Job 제출 (Phase 0-3)

#### GET API - Template Normalization
```bash
GET /api/v2/templates/{template_id}
```

**응답 예시**:
```json
{
  "template": { ... },
  "apptainer_normalized": {
    "mode": "partition",
    "partition": "normal",
    "user_selectable": true,
    "allowed_images": [...]
  }
}
```

#### POST API - Job Submission
```bash
POST /api/jobs/submit
Content-Type: multipart/form-data

Parameters:
  - template_id: "my-simulation-v1"
  - apptainer_image_id: "KooSimulationPython313"
  - file_<file_key>: File (예: file_input_file)
  - slurm_overrides: JSON {"mem":"2G","time":"02:00:00"}
  - job_name: "my-job"
```

**응답 예시**:
```json
{
  "success": true,
  "job_id": "415",
  "script_path": "/tmp/slurm_scripts/job_my-job_20251114_205350.sh",
  "message": "Job 415 submitted successfully",
  "request_id": "5859c612-ab50-4620-bc1e-d1979341ecf0",
  "elapsed_time": "0.02s"
}
```

#### Job History DB (Phase 3)

**테이블**: `job_submissions`
**컬럼**: 29개 (job info, template info, slurm config, files, status, timestamps)
**인덱스**: 5개 (job_id, user_id, template_id, status, submitted_at)

**검증**:
```bash
sqlite3 /home/koopark/web_services/backend/dashboard.db \
  "SELECT job_id, job_name, status, submitted_at FROM job_submissions ORDER BY id DESC LIMIT 5"
```

---

### 2. Production Hardening (Phase 5)

#### 에러 코드 체계
```python
class ErrorCode:
    # Template errors (1xxx)
    TEMPLATE_NOT_FOUND = 1001
    TEMPLATE_VALIDATION_FAILED = 1003

    # File errors (2xxx)
    FILE_UPLOAD_FAILED = 2004
    FILE_VALIDATION_FAILED = 2005

    # Image errors (3xxx)
    IMAGE_NOT_FOUND = 3001

    # Slurm errors (4xxx)
    SLURM_SUBMISSION_FAILED = 4001
    SLURM_TIMEOUT = 4002

    # DB errors (5xxx)
    DB_RECORD_FAILED = 5002

    # General errors (9xxx)
    INTERNAL_ERROR = 9999
```

#### 구조화된 로깅

**로그 형식** (JSON):
```json
{
  "request_id": "uuid",
  "event": "job_submit_start",
  "timestamp": "2025-11-14T20:51:41.398976",
  "details": {
    "template_id": "my-simulation-v1",
    "has_files": true
  }
}
```

**주요 이벤트**:
- `job_submit_start` → `template_loaded` → `template_validated` → `image_selected`
- `file_uploaded` → `files_validated` → `script_generated` → `script_saved`
- `sbatch_submit_start` → `job_submitted` → `db_recorded` → `job_submit_success`

**로그 위치**:
- `/var/log/web_services/dashboard_backend.error.log`

**request_id로 추적**:
```bash
grep "5859c612-ab50-4620-bc1e-d1979341ecf0" /var/log/web_services/dashboard_backend.error.log
```

#### 보안 강화

**파일 업로드 보안**:
- ✅ 파일 크기 제한 (기본 1000MB)
- ✅ Path traversal 방지
- ✅ 파일명 sanitization (`secure_filename`)
- ✅ 권한 설정 (644, 읽기 전용)

**코드**:
```python
def save_uploaded_file(file, max_size_mb=1000) -> str:
    # 1. 파일명 보안 검증
    # 2. Path traversal 방지
    # 3. 파일 크기 제한
    # 4. 안전한 경로 생성
    # 5. Path traversal 최종 검증
    # 6. 파일 저장
    # 7. 파일 권한 설정 (644)
```

---

### 3. Advanced Features (Phase 6)

#### Script Preview API

Job을 제출하지 않고 생성될 스크립트만 미리 확인

```bash
POST /api/jobs/preview
Content-Type: multipart/form-data

Parameters:
  - template_id: "my-simulation-v1"
  - apptainer_image_id: "KooSimulationPython313"
  - slurm_overrides: JSON {"mem":"2G","time":"02:00:00"}
  - job_name: "test-preview"
```

**응답 예시**:
```json
{
  "success": true,
  "script": "#!/bin/bash\n#SBATCH ...",
  "script_length": 3265,
  "estimated_cost": {
    "total_cost_usd": 1.04,
    "breakdown": {
      "node_cost": 1.0,
      "memory_cost": 0.04
    },
    "resources": {
      "nodes": 1,
      "ntasks": 4,
      "memory_gb": 2.0,
      "time_hours": 2.0
    },
    "note": "Estimated cost - actual cost may vary"
  },
  "request_id": "uuid"
}
```

#### Cost Estimation

**비용 모델** (예시, 실제 환경에 맞게 조정):
- 노드당 시간당: $0.50
- 메모리 GB당 시간당: $0.01

**예시**:
- 1 노드, 2GB, 2시간 → $1.04
- 2 노드, 16GB, 4시간 → $4.64

---

## 📁 수정된 파일 목록

### Backend

1. **`backend_5010/job_submit_api.py`** (주요 수정)
   - Line 30-102: ErrorCode, 로깅 유틸리티
   - Line 312-362: 보안 강화 `save_uploaded_file()`
   - Line 459-861: 향상된 `submit_job()` (에러 처리, 로깅)
   - Line 863-973: `preview_script()` 엔드포인트
   - Line 976-1039: `estimate_job_cost()` 함수

2. **`backend_5010/templates_api_v2.py`**
   - Line 172-183: Template 정규화 로직 추가

3. **`backend_5010/template_validator.py`**
   - Line 101: 파티션 목록에 'normal' 추가

4. **`backend_5010/migrations/v4.4.1_job_history.sql`** (신규 생성)
   - `job_submissions` 테이블 스키마

### Templates

5. **`/shared/templates/community/compute/my-simulation-v1.yaml`**
   - Line 14: partition "compute" → "normal"
   - Line 18: mem "16G" → "4G"
   - Line 23: partition "compute" → "normal"

---

## 🧪 테스트 결과

### Phase 4: Integration Testing ✅

| 테스트 | 결과 | Job ID | 비고 |
|--------|------|--------|------|
| GET API normalize | ✅ Pass | N/A | `apptainer_normalized` 필드 확인 |
| POST API submission | ✅ Pass | 413 | 실제 sbatch 제출 성공 |
| Slurm queue | ✅ Pass | 413 | `squeue` 확인 완료 |
| DB recording | ✅ Pass | 413 | `job_submissions` 테이블 기록 확인 |

### Phase 5-6: New Features ✅

| 테스트 | 결과 | 비고 |
|--------|------|------|
| Structured logging | ✅ Pass | JSON 형식, request_id 추적 |
| Error codes | ✅ Pass | 1xxx, 2xxx, 3xxx, 4xxx, 5xxx |
| File security | ✅ Pass | Path traversal, 크기 제한 |
| Script preview | ✅ Pass | 3265 bytes script |
| Cost estimation | ✅ Pass | $1.04 for 1 node, 2GB, 2h |
| Final integration | ✅ Pass | Job 415 성공 |

### 로그 샘플 (Job 414)

```
2025-11-14 20:51:41,399 - {"request_id": "2a258f2c", "event": "job_submit_start", ...}
2025-11-14 20:51:41,399 - {"request_id": "2a258f2c", "event": "template_loaded", ...}
2025-11-14 20:51:41,404 - {"request_id": "2a258f2c", "event": "template_validated", ...}
2025-11-14 20:51:41,406 - {"request_id": "2a258f2c", "event": "image_selected", ...}
2025-11-14 20:51:41,406 - {"request_id": "2a258f2c", "event": "file_uploaded", ...}
2025-11-14 20:51:41,406 - {"request_id": "2a258f2c", "event": "files_validated", ...}
2025-11-14 20:51:41,406 - {"request_id": "2a258f2c", "event": "script_generated", ...}
2025-11-14 20:51:41,409 - {"request_id": "2a258f2c", "event": "job_submitted", "details": {"job_id": "414"}}
2025-11-14 20:51:41,415 - {"request_id": "2a258f2c", "event": "job_submit_success", "details": {"elapsed_time": 0.017693}}
```

---

## 🚀 사용 가이드

### 1. 기본 Job 제출

```bash
curl -X POST http://localhost:5010/api/jobs/submit \
  -F "template_id=my-simulation-v1" \
  -F "job_name=my-job" \
  -F "apptainer_image_id=KooSimulationPython313" \
  -F "file_input_file=@/path/to/input.py" \
  -F 'slurm_overrides={"mem":"2G","time":"01:00:00"}'
```

### 2. Script 미리보기

```bash
curl -X POST http://localhost:5010/api/jobs/preview \
  -F "template_id=my-simulation-v1" \
  -F "job_name=preview-test" \
  -F "apptainer_image_id=KooSimulationPython313" \
  -F 'slurm_overrides={"mem":"2G","time":"02:00:00"}' \
  | jq '.estimated_cost'
```

### 3. Job 상태 확인

```bash
# Slurm 큐 확인
squeue -j <job_id>

# DB 기록 확인
sqlite3 /home/koopark/web_services/backend/dashboard.db \
  "SELECT * FROM job_submissions WHERE job_id='<job_id>'"
```

### 4. 로그 추적

```bash
# request_id로 전체 플로우 추적
grep "<request_id>" /var/log/web_services/dashboard_backend.error.log | jq

# 최근 에러만 확인
grep "error_code" /var/log/web_services/dashboard_backend.error.log | tail -20
```

---

## 🔍 문제 해결 (Troubleshooting)

### 에러 코드별 해결 방법

| Error Code | 문제 | 해결 방법 |
|-----------|------|----------|
| 1001 | Template not found | template_id 확인, `/api/v2/templates` 목록 조회 |
| 1003 | Template validation failed | YAML 형식 확인, partition 유효성 |
| 2004 | File upload failed | 파일 크기, 디스크 공간 확인 |
| 2005 | File validation failed | file_key, 파일 형식 확인 |
| 3001 | Image not found | `apptainer_image_id` 확인, `/api/apptainer/images` 조회 |
| 4001 | Slurm submission failed | Slurm 파티션, 리소스 한도 확인 |
| 4002 | Slurm timeout | Slurm controller 상태 확인 |
| 5002 | DB record failed | DB 파일 권한, 디스크 공간 확인 |
| 9999 | Internal error | 로그 확인, 스택 트레이스 분석 |

### 일반적인 문제

**Q: Template validation failed (partition: normal)**
A: `template_validator.py` Line 101에 'normal' 추가 필요

**Q: sbatch 제출은 성공했는데 DB 기록 실패**
A: Job은 정상 제출됨. DB 권한 확인 후 수동 기록 가능

**Q: 로그에서 특정 Job 찾기**
A: `grep "job_id.*<job_id>" /var/log/web_services/dashboard_backend.error.log`

---

## 📊 성능 메트릭

**Job 제출 평균 시간**: 17-20ms
**Script 생성 시간**: ~1ms
**DB 기록 시간**: ~5ms
**sbatch 실행 시간**: ~3ms

**동시 요청 처리**: Flask default (단일 스레드, 개선 필요 시 gunicorn 사용)

---

## 🎓 추가 개선 가능 사항 (Optional)

### High Priority
- [ ] 대용량 파일 업로드 (청크 업로드)
- [ ] Image 호환성 체크
- [ ] Job 상태 추적 (실시간 업데이트)

### Medium Priority
- [ ] Frontend UI 통합 테스트
- [ ] Template 버전 관리
- [ ] Job queue 우선순위

### Low Priority
- [ ] Job 실행 통계 대시보드
- [ ] 비용 분석 리포트
- [ ] 자동 리소스 최적화

---

## 📝 변경 이력

| 날짜 | Phase | 변경 내용 |
|------|-------|----------|
| 2025-11-14 | Phase 0-3 | Core 기능 구현 (GET normalize, POST sbatch, DB) |
| 2025-11-14 | Phase 4 | 통합 테스트 완료 |
| 2025-11-14 | Phase 4.5 | Partition, memory 주의사항 개선 |
| 2025-11-14 | Phase 5 | 에러 처리, 로깅, 보안 강화 |
| 2025-11-14 | Phase 6 | Script preview, cost estimation 추가 |
| 2025-11-14 | Phase 7 | Documentation 완료 |

---

## ✅ 최종 체크리스트

- [x] GET API Template 정규화
- [x] POST API sbatch 실제 제출
- [x] Job History DB 기록
- [x] 구조화된 에러 처리 (ErrorCode)
- [x] JSON 로깅 (request_id 추적)
- [x] 파일 업로드 보안
- [x] Script preview API
- [x] Cost estimation
- [x] 통합 테스트 (Job 413, 414, 415)
- [x] Documentation

**Status**: ✅ **Production Ready**

---

**작성자**: Claude
**최종 업데이트**: 2025-11-14 20:53
**버전**: v2.0 Complete
