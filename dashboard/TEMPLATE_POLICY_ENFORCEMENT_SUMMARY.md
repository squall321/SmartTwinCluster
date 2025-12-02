# Template Policy Enforcement - Implementation Summary

**작성일**: 2025-11-15
**상태**: ✅ **Implementation Complete**

---

## 🎯 구현 완료 항목

### 1. Backend 파일 검증 강화 ✅

**파일**: [backend_5010/job_submit_api.py](backend_5010/job_submit_api.py)

#### 추가된 Helper 함수

| 함수 | 위치 | 기능 |
|------|------|------|
| `find_file_definition()` | Lines 205-219 | 파일 스키마에서 file_key 정의 찾기 |
| `parse_size_string()` | Lines 222-242 | 크기 문자열("500MB") → 바이트 변환 |
| `validate_file_schema_strict()` | Lines 245-310 | 엄격한 파일 검증 (필수/확장자/크기) |
| `verify_script_file_mappings()` | Lines 313-336 | 스크립트 환경 변수 매핑 검증 |

#### 검증 로직 강화

**Before**:
```python
errors = validator.validate_file_schema(normalized_template, uploaded_files)
```

**After** (Line 802):
```python
errors = validate_file_schema_strict(normalized_template, uploaded_files)
```

**추가 검증 항목**:
1. ✅ 필수 파일 누락 체크
2. ✅ 파일 확장자 검증 (`.stl`, `.json` 등)
3. ✅ 파일 크기 제한 검증 (`max_size: "500MB"`)
4. ✅ 예상치 못한 파일 업로드 감지
5. ✅ 스크립트 환경 변수 매핑 검증 (Line 840-845)

---

### 2. Frontend Template 정책 강제 ✅

**파일**: [frontend_3010/src/components/JobManagement.tsx](frontend_3010/src/components/JobManagement.tsx)

#### 2.1. Partition - 읽기 전용 (Lines 976-1011)

**Template 선택 시**:
```tsx
<div className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-100 text-gray-700">
  {selectedTemplateForJob.slurm?.partition || 'N/A'}
</div>
<span className="text-xs text-gray-500 ml-2">🔒 Read-only (from Template)</span>
```

**Template 없을 때**: 편집 가능한 `<select>` 표시

---

#### 2.2. Resource Configuration - 읽기 전용 (Lines 1013-1079)

**Template 선택 시**:
```tsx
<div className="p-3 border border-gray-300 rounded-lg bg-gray-100">
  <div className="font-semibold text-gray-900">
    {(nodes × ntasks)} Total Cores
  </div>
  <div className="text-sm text-gray-600">
    {nodes} node(s) × {ntasks} CPUs/node
  </div>
</div>
<span className="text-xs text-gray-500 ml-2">🔒 Read-only (from Template)</span>
```

**Template 없을 때**: 편집 가능한 Resource Configuration 선택 UI

---

#### 2.3. Memory, Time - Override 허용 (Lines 1110-1152)

**특징**:
- ✏️ **항상 편집 가능** (파란색 테두리)
- Template 기본값을 placeholder와 하단 텍스트로 표시
- 사용자 입력 우선 적용

```tsx
<label>
  Memory
  {selectedTemplateForJob && (
    <span className="text-xs text-blue-600 ml-2">✏️ Override allowed</span>
  )}
</label>
<input
  className="border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500"
  placeholder={selectedTemplateForJob?.slurm?.mem || "16GB"}
/>
{selectedTemplateForJob && (
  <p className="text-xs text-gray-500 mt-1">
    Template default: {selectedTemplateForJob.slurm?.mem || "N/A"}
  </p>
)}
```

---

#### 2.4. Script - 읽기 전용 미리보기 (Lines 1168-1214)

**Template 선택 시**:
```tsx
<pre className="bg-gray-50 text-gray-700 font-mono text-xs max-h-60">
  <code>{`#!/bin/bash
# This script will be automatically generated from the template
# Template: ${selectedTemplateForJob.template?.name}

# Slurm Configuration:
#SBATCH --partition=${selectedTemplateForJob.slurm?.partition}
#SBATCH --nodes=${selectedTemplateForJob.slurm?.nodes}
#SBATCH --ntasks=${selectedTemplateForJob.slurm?.ntasks}
#SBATCH --mem=${formData.memory || selectedTemplateForJob.slurm?.mem}
#SBATCH --time=${formData.time || selectedTemplateForJob.slurm?.time}

# Apptainer: ${selectedApptainerImage?.name || 'Will be selected'}
# Files: ${templateFiles.map(f => f.file_key).join(', ')}

# Template scripts will be inserted here...
`}</code>
</pre>
<p className="text-xs text-gray-500 mt-1">
  ℹ️ This is a preview. The actual script will be generated when you submit the job.
</p>
```

**Template 없을 때**: 편집 가능한 `<textarea>`

---

### 3. 파일 업로드 검증 UI ✅

**위치**: [JobManagement.tsx:916-963](frontend_3010/src/components/JobManagement.tsx#L916-L963)

**기능**:
- 📋 실시간 파일 업로드 상태 표시
- ✅ 업로드 완료된 파일 (녹색 체크)
- ❌ 누락된 필수 파일 (빨간색 X + "Required" 태그)
- ⭕ 누락된 선택적 파일 (회색 원 + "Optional" 태그)

```tsx
<div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
  <h4 className="text-sm font-semibold text-blue-900 mb-2">
    📋 File Upload Status
  </h4>

  {/* 필수 파일 체크 */}
  {requiredFiles.map(fileReq => {
    const isUploaded = templateFiles.some(f => f.file_key === fileReq.file_key);
    return (
      <div className="flex items-center gap-2 text-sm mb-1">
        {isUploaded ? <span className="text-green-600">✅</span> : <span className="text-red-600">❌</span>}
        <span className={isUploaded ? 'text-gray-700' : 'text-red-700 font-semibold'}>
          {fileReq.name} ({fileReq.file_key})
        </span>
        {!isUploaded && <span className="text-red-600 text-xs ml-auto font-bold">Required</span>}
      </div>
    );
  })}

  {/* 선택적 파일 체크 */}
  {optionalFiles.map(fileReq => {
    // ... 동일한 로직
  })}
</div>
```

---

### 4. Submit 버튼 검증 강화 ✅

**위치**: [JobManagement.tsx:1225-1286](frontend_3010/src/components/JobManagement.tsx#L1225-L1286)

**검증 로직**:
```tsx
disabled={(() => {
  // Loading state
  if (loadingPartitions) return true;

  // Legacy template validation
  if (templateId && fileValidation && !fileValidation.valid) return true;

  // New template system validation
  if (selectedTemplateForJob?.files?.input_schema?.required) {
    const requiredFiles = selectedTemplateForJob.files.input_schema.required;
    const uploadedKeys = templateFiles.map(f => f.file_key);
    const allRequiredUploaded = requiredFiles.every(req => uploadedKeys.includes(req.file_key));
    if (!allRequiredUploaded) return true;
  }

  return false;
})()}
```

**UI 변화**:
- ✅ **모든 필수 파일 업로드 완료**: 파란색 "Submit Job" 버튼
- ❌ **필수 파일 누락**: 회색 "⚠️ Missing Required Files" 버튼 (비활성화)
- 💬 **Tooltip**: 누락된 파일 목록 표시

```tsx
title={(() => {
  if (selectedTemplateForJob?.files?.input_schema?.required) {
    const missingFiles = requiredFiles.filter(req => !uploadedKeys.includes(req.file_key));
    if (missingFiles.length > 0) {
      return `Missing required files: ${missingFiles.map(f => f.name).join(', ')}`;
    }
  }
  return '';
})()}
```

---

### 5. slurm_overrides 정책 강제 ✅

**위치**: [JobManagement.tsx:775-780](frontend_3010/src/components/JobManagement.tsx#L775-L780)

**Before** (호환성 문제):
```javascript
const slurmOverrides = {
  memory: formData.memory,  // ❌ Backend 필드명 불일치
  time: formData.time,
};
// partition, nodes, ntasks 누락 (사용자 변경 무시됨)
```

**After** (정책 강제):
```javascript
// Slurm overrides (memory, time만 허용 - Template 정책 강제)
const slurmOverrides = {
  mem: formData.memory,    // ✅ Backend 필드명: 'mem'
  time: formData.time,
};
// partition, nodes, ntasks는 전송하지 않음 → Template 기본값 사용
```

**Backend 처리** ([job_submit_api.py:818-822](backend_5010/job_submit_api.py#L818-L822)):
```python
slurm_overrides = json.loads(request.form.get('slurm_overrides', '{}'))
# slurm_overrides = {"mem": "8G", "time": "02:00:00"}

# Template 기본값
slurm_config = normalized_template['slurm'].copy()
# {"partition": "normal", "nodes": 1, "ntasks": 4, "mem": "4G", "time": "01:00:00"}

# Override 적용 (mem, time만)
slurm_config.update(slurm_overrides)
# {"partition": "normal", "nodes": 1, "ntasks": 4, "mem": "8G", "time": "02:00:00"}
#  ^^^^^^^^^^^^^^^^  ^^^^^^^  ^^^^^^^^^^  Template 기본값 유지
#                                           ^^^^^^^^^  ^^^^^^^^^^^^  사용자 override
```

---

## 📊 최종 정책 요약

| 항목 | Template에서 결정 | 사용자 Override 가능 | UI 표시 |
|------|------------------|---------------------|---------|
| **Partition** | ✅ | ❌ | 🔒 읽기 전용 (회색) |
| **Nodes** | ✅ | ❌ | 🔒 읽기 전용 (회색) |
| **CPUs (ntasks)** | ✅ | ❌ | 🔒 읽기 전용 (회색) |
| **CPUs per Task** | ✅ | ❌ | 🔒 읽기 전용 (회색) |
| **Memory** | ⚠️ 기본값 제공 | ✅ | ✏️ 편집 가능 (파란색) |
| **Time Limit** | ⚠️ 기본값 제공 | ✅ | ✏️ 편집 가능 (파란색) |
| **Script** | ✅ | ❌ | 🔒 읽기 전용 미리보기 |
| **Files** | ✅ 스키마 정의 | ❌ | 📋 검증 상태 표시 |

---

## 🧪 테스트 가이드

### Scenario 1: 필수 파일 누락 테스트

**Steps**:
1. Template 선택: "angle-drop-simulation-v2"
2. 필수 파일: `geometry` (STL), `config` (JSON)
3. `geometry` 파일만 업로드
4. Submit 버튼 확인

**Expected**:
- ❌ Submit 버튼: 회색 "⚠️ Missing Required Files" (비활성화)
- 📋 파일 상태:
  - ✅ 형상 파일 (geometry) - 녹색 체크
  - ❌ 설정 파일 (config) - 빨간색 X + "Required"
- 💬 Tooltip: "Missing required files: 설정 파일"

---

### Scenario 2: 잘못된 파일 확장자 테스트

**Steps**:
1. Template 선택: "angle-drop-simulation-v2"
2. `geometry` 파일로 `.txt` 파일 업로드 (`.stl` 필요)
3. `config` 파일 정상 업로드 (`.json`)
4. Submit 버튼 클릭

**Expected Frontend**:
- ✅ Submit 버튼: 활성화 (파일 개수는 맞음)

**Expected Backend**:
- ❌ 응답: `400 Bad Request`
- 📋 Error:
```json
{
  "success": false,
  "error": "File validation failed",
  "errors": [
    "Invalid file extension for '형상 파일': .txt (allowed: .stl, .STL)"
  ],
  "error_code": 2005,
  "request_id": "uuid"
}
```

---

### Scenario 3: Template 정책 강제 테스트

**Steps**:
1. Template 선택: "my-simulation-v1"
   - Template 설정: partition="normal", nodes=1, ntasks=4
2. UI 확인

**Expected**:
- 🔒 **Partition**: "normal" (회색 배경, 읽기 전용)
- 🔒 **Resource Configuration**: "4 Total Cores (1 node × 4 CPUs)" (회색 배경)
- ✏️ **Memory**: 편집 가능 (파란색 테두리, placeholder="4G")
- ✏️ **Time**: 편집 가능 (파란색 테두리, placeholder="01:00:00")
- 🔒 **Script**: 읽기 전용 미리보기 표시

**Submit 후 검증**:
```sql
-- DB에서 실제 제출된 값 확인
SELECT partition, nodes, cpus, memory, time_limit
FROM job_submissions
WHERE job_id = '<submitted_job_id>';

-- Expected:
-- partition = "normal"  (Template 기본값)
-- nodes = 1              (Template 기본값)
-- cpus = 4               (Template 기본값)
-- memory = "8G"          (사용자 override, 기본값 "4G")
-- time_limit = "02:00:00" (사용자 override, 기본값 "01:00:00")
```

---

### Scenario 4: 스크립트 파일 매핑 검증

**Steps**:
1. Template 선택: "my-simulation-v1"
2. `input_file` 업로드 (file_key: "input_file")
3. Submit

**Expected Backend 로그**:
```json
{
  "request_id": "uuid",
  "event": "script_file_mapping_warnings",
  "details": {
    "warnings": []  // ✅ 경고 없음 (INPUT_FILE 환경 변수가 스크립트에 존재)
  }
}
```

**만약 Template 스크립트에 `INPUT_FILE` 환경 변수가 없다면**:
```json
{
  "warnings": [
    "Warning: File 'input_file' uploaded but environment variable 'INPUT_FILE_FILE' not found in script. This file may not be used."
  ]
}
```

---

## 🔧 문제 해결 (Troubleshooting)

### Q1: Submit 버튼이 활성화되지 않아요

**원인**: 필수 파일이 모두 업로드되지 않음

**해결**:
1. 📋 "File Upload Status" 섹션 확인
2. ❌ 빨간색 X가 있는 파일 업로드
3. ✅ 모든 파일이 녹색 체크가 되면 버튼 활성화됨

---

### Q2: 파일을 업로드했는데 "Invalid file extension" 에러가 나요

**원인**: Template에서 허용하는 확장자가 아님

**해결**:
1. Template의 `files.input_schema` 확인
2. `validation.extensions` 필드 확인
3. 허용되는 확장자로 파일 업로드

**예시**:
```yaml
files:
  input_schema:
    required:
      - name: "형상 파일"
        file_key: "geometry"
        validation:
          extensions: [".stl", ".STL"]  # ✅ 이 확장자만 허용
```

---

### Q3: UI에서 Partition을 변경하고 싶어요

**답변**: Template을 선택한 경우 Partition은 Template에서 결정됩니다.

**해결 방법**:
- **Option 1**: Template 선택을 취소하고 직접 스크립트 작성
- **Option 2**: 다른 Partition을 사용하는 Template 선택
- **Option 3**: Template YAML 파일을 수정하여 원하는 Partition으로 변경

---

### Q4: Memory를 Template 기본값보다 작게 설정하고 싶어요

**답변**: 가능합니다! Memory와 Time은 Override 허용됩니다.

**방법**:
1. Memory 입력 필드 편집 (파란색 테두리)
2. 원하는 값 입력 (예: "2G")
3. Submit → Backend에서 사용자 값 우선 적용

---

## 📁 수정된 파일 목록

### Backend
1. ✅ **[job_submit_api.py](backend_5010/job_submit_api.py)**
   - Lines 205-336: Helper 함수 4개 추가
   - Line 802: 파일 검증 로직 교체
   - Lines 840-845: 스크립트 파일 매핑 검증 추가

### Frontend
2. ✅ **[JobManagement.tsx](frontend_3010/src/components/JobManagement.tsx)**
   - Lines 775-780: slurm_overrides 수정 (mem, time만)
   - Lines 916-963: 파일 업로드 검증 UI 추가
   - Lines 976-1011: Partition 읽기 전용 UI
   - Lines 1013-1079: Resource Configuration 읽기 전용 UI
   - Lines 1110-1152: Memory, Time Override UI
   - Lines 1168-1214: Script 읽기 전용 미리보기
   - Lines 1225-1286: Submit 버튼 검증 강화

### Documentation
3. ✅ **[TEMPLATE_POLICY_ENFORCEMENT_DESIGN.md](TEMPLATE_POLICY_ENFORCEMENT_DESIGN.md)**
   - 상세 설계 문서

4. ✅ **[TEMPLATE_POLICY_ENFORCEMENT_SUMMARY.md](TEMPLATE_POLICY_ENFORCEMENT_SUMMARY.md)**
   - 구현 요약 문서 (현재 문서)

5. ✅ **[FRONTEND_BACKEND_COMPATIBILITY_ANALYSIS.md](FRONTEND_BACKEND_COMPATIBILITY_ANALYSIS.md)**
   - 호환성 문제 분석 문서

---

## ✅ 최종 체크리스트

### Backend
- [x] `validate_file_schema_strict()` 함수 추가
- [x] `find_file_definition()` Helper 함수 추가
- [x] `parse_size_string()` Helper 함수 추가
- [x] `verify_script_file_mappings()` 함수 추가
- [x] 파일 검증 로직 교체
- [x] 스크립트 파일 매핑 검증 추가

### Frontend
- [x] Partition UI 읽기 전용으로 변경
- [x] Resource Configuration UI 읽기 전용으로 변경
- [x] Memory, Time Override UI 개선
- [x] 파일 업로드 상태 표시 UI 추가
- [x] Submit 버튼 검증 로직 추가
- [x] Script 읽기 전용 미리보기로 변경
- [x] slurm_overrides 전송 데이터 수정

### Documentation
- [x] 설계 문서 작성
- [x] 구현 요약 문서 작성
- [x] 호환성 분석 문서 작성
- [x] 테스트 시나리오 작성
- [x] 문제 해결 가이드 작성

---

## 🎓 추가 개선 가능 사항 (Optional)

### High Priority
- [ ] 대용량 파일 업로드 (청크 업로드, 진행률 표시)
- [ ] 실시간 스크립트 미리보기 API (`/api/jobs/preview` 호출)
- [ ] Template override 권한 관리 (관리자만 override 허용)

### Medium Priority
- [ ] 파일 업로드 진행률 표시
- [ ] Template 버전 관리 강화
- [ ] Job 비용 예측 UI 표시

### Low Priority
- [ ] 파일 drag-and-drop 지원
- [ ] Template 즐겨찾기 기능
- [ ] Job 제출 히스토리 대시보드

---

**작성자**: Claude
**최종 업데이트**: 2025-11-15
**상태**: ✅ **Implementation Complete - Ready for Testing**

---

## 🚀 다음 단계

1. **Backend 재시작**: `systemctl restart dashboard_backend.service`
2. **Frontend 빌드**: `cd frontend_3010 && npm run build`
3. **통합 테스트**: 위 4가지 시나리오 테스트
4. **Production 배포**: 테스트 통과 후 배포
