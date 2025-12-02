# Template Policy Enforcement - Design Document

**작성일**: 2025-11-15
**목표**: Template 정책 강제 + 파일 업로드 검증 강화 + 스크립트 수정 불가

---

## 🎯 핵심 정책

### 1. Template 설정 강제 (Immutable Template Configuration)

**원칙**: Template을 선택하면 해당 Template의 Slurm 설정은 **변경 불가**

| 항목 | Template에서 결정 | 사용자 Override 가능 | UI 표시 |
|------|------------------|---------------------|---------|
| **Partition** | ✅ | ❌ | 읽기 전용 (회색) |
| **Nodes** | ✅ | ❌ | 읽기 전용 (회색) |
| **CPUs (ntasks)** | ✅ | ❌ | 읽기 전용 (회색) |
| **CPUs per Task** | ✅ | ❌ | 읽기 전용 (회색) |
| **Memory** | ⚠️ 기본값 | ✅ | 편집 가능 (파란색) |
| **Time Limit** | ⚠️ 기본값 | ✅ | 편집 가능 (파란색) |
| **Script** | ✅ | ❌ | 읽기 전용 (미리보기만) |

**이유**:
- 보안: 파티션 정책 우회 방지
- 일관성: Template 작성자의 의도 보존
- 리소스 관리: 클러스터 정책 준수

---

### 2. 파일 업로드 검증 강화

**검증 단계**:

#### Phase 1: 업로드 전 검증 (Frontend)
```typescript
// 필수 파일 체크
const requiredFiles = schema.required || [];
const uploadedKeys = uploadedFiles.map(f => f.file_key);
const missingFiles = requiredFiles.filter(
  req => !uploadedKeys.includes(req.file_key)
);

if (missingFiles.length > 0) {
  // ❌ Submit 버튼 비활성화
  // ⚠️ 경고 메시지 표시: "필수 파일 누락: geometry, config"
}
```

#### Phase 2: 업로드 후 검증 (Backend)
```python
# job_submit_api.py - validate_file_schema() 강화

def validate_file_schema_strict(template: dict, uploaded_files: dict) -> list:
    """
    엄격한 파일 스키마 검증

    Returns:
        list: 에러 목록 (빈 리스트면 검증 통과)
    """
    errors = []
    file_schema = template.get('files', {}).get('input_schema', {})

    # 1. 필수 파일 확인
    for required_file in file_schema.get('required', []):
        file_key = required_file['file_key']
        if file_key not in uploaded_files:
            errors.append(f"Required file missing: {file_key} ({required_file['name']})")

    # 2. 파일 확장자 검증
    for file_key, file_info in uploaded_files.items():
        # 스키마에서 해당 파일 정의 찾기
        file_def = find_file_definition(file_schema, file_key)
        if not file_def:
            errors.append(f"Unexpected file: {file_key}")
            continue

        # 확장자 검증
        if 'validation' in file_def and 'extensions' in file_def['validation']:
            allowed_exts = file_def['validation']['extensions']
            filename = file_info['filename']
            ext = os.path.splitext(filename)[1].lower()

            if ext not in [e.lower() for e in allowed_exts]:
                errors.append(
                    f"Invalid file extension for {file_key}: {ext} "
                    f"(allowed: {', '.join(allowed_exts)})"
                )

    # 3. 파일 크기 검증
    for file_key, file_info in uploaded_files.items():
        file_def = find_file_definition(file_schema, file_key)
        if file_def and 'max_size' in file_def:
            max_size_str = file_def['max_size']  # "500MB"
            max_size_bytes = parse_size_string(max_size_str)

            if file_info['size'] > max_size_bytes:
                errors.append(
                    f"File too large: {file_key} "
                    f"({file_info['size'] / 1024 / 1024:.2f}MB, max: {max_size_str})"
                )

    return errors
```

#### Phase 3: 스크립트 생성 후 검증 (Backend)
```python
# 스크립트에 파일 환경 변수가 제대로 포함되었는지 검증
def verify_script_file_mappings(script: str, uploaded_files: dict) -> list:
    """
    생성된 스크립트에 파일 환경 변수가 포함되었는지 확인

    Returns:
        list: 경고 목록
    """
    warnings = []

    for file_key in uploaded_files.keys():
        # 환경 변수 이름 (예: GEOMETRY_FILE, CONFIG_FILE)
        env_var = f"{file_key.upper()}_FILE"

        if env_var not in script:
            warnings.append(
                f"Warning: File '{file_key}' uploaded but environment variable "
                f"'{env_var}' not found in script"
            )

    return warnings
```

---

### 3. 스크립트 수정 불가 (Read-Only Script)

**Frontend 변경**:
```typescript
// JobManagement.tsx

// ❌ 제거: 스크립트 편집 UI
// <textarea value={formData.script} onChange={...} />

// ✅ 추가: 읽기 전용 미리보기
<div className="bg-gray-50 rounded-lg p-4 border border-gray-200">
  <div className="flex items-center justify-between mb-2">
    <label className="text-sm font-medium text-gray-700">
      Generated Script (Read-Only)
    </label>
    <button
      onClick={handlePreviewScript}
      className="text-sm text-blue-600 hover:text-blue-700"
    >
      🔍 Preview Full Script
    </button>
  </div>

  {/* 스크립트 미리보기 (읽기 전용) */}
  <pre className="text-xs bg-gray-900 text-green-400 p-3 rounded overflow-x-auto max-h-60">
    <code>{scriptPreview || 'Select template to preview script...'}</code>
  </pre>

  <p className="text-xs text-gray-500 mt-2">
    ℹ️ This script is automatically generated from the template.
    Manual editing is not allowed.
  </p>
</div>
```

---

## 📝 구현 상세

### Backend Changes

#### 1. `job_submit_api.py` - 파일 검증 강화

**위치**: Lines 466-484 (기존 검증 로직 교체)

```python
# 5. 파일 스키마 검증 (엄격 모드)
log_info(request_id, 'file_validation_start', {
    'uploaded_files': list(uploaded_files.keys())
})

errors = validate_file_schema_strict(normalized_template, uploaded_files)
if errors:
    log_error(request_id, ErrorCode.FILE_VALIDATION_FAILED, 'File validation failed', {
        'errors': errors
    })
    return jsonify({
        'success': False,
        'error': 'File validation failed',
        'errors': errors,
        'error_code': ErrorCode.FILE_VALIDATION_FAILED,
        'request_id': request_id
    }), 400

log_info(request_id, 'files_validated')

# 5.5. 스크립트 파일 매핑 검증 (추가)
warnings = verify_script_file_mappings(script, uploaded_files)
if warnings:
    log_info(request_id, 'script_file_mapping_warnings', {
        'warnings': warnings
    })
```

#### 2. `job_submit_api.py` - Helper 함수 추가

```python
def find_file_definition(file_schema: dict, file_key: str) -> dict:
    """
    파일 스키마에서 file_key에 해당하는 정의 찾기

    Args:
        file_schema: Template의 files.input_schema
        file_key: 찾을 파일 키

    Returns:
        dict: 파일 정의 또는 None
    """
    for file_def in file_schema.get('required', []) + file_schema.get('optional', []):
        if file_def.get('file_key') == file_key:
            return file_def
    return None


def parse_size_string(size_str: str) -> int:
    """
    크기 문자열을 바이트로 변환

    Args:
        size_str: "500MB", "1GB" 등

    Returns:
        int: 바이트 수
    """
    size_str = size_str.strip().upper()

    if size_str.endswith('GB'):
        return int(float(size_str[:-2]) * 1024 * 1024 * 1024)
    elif size_str.endswith('MB'):
        return int(float(size_str[:-2]) * 1024 * 1024)
    elif size_str.endswith('KB'):
        return int(float(size_str[:-2]) * 1024)
    else:
        # 기본값: MB로 가정
        return int(float(size_str) * 1024 * 1024)
```

#### 3. `template_validator.py` - 검증 함수 강화

```python
def validate_file_schema_strict(self, template: dict, uploaded_files: dict) -> list:
    """
    엄격한 파일 스키마 검증

    (위에서 정의한 로직 구현)
    """
    # ... 구현 ...
    pass


def verify_script_file_mappings(self, script: str, uploaded_files: dict) -> list:
    """
    스크립트 파일 매핑 검증

    (위에서 정의한 로직 구현)
    """
    # ... 구현 ...
    pass
```

---

### Frontend Changes

#### 1. `JobManagement.tsx` - UI 정책 강제

**변경 위치**: Lines 925-999 (Partition 및 Resource Configuration)

**Before** (편집 가능):
```typescript
{/* Partition Selection - 편집 가능 */}
<select
  required
  value={formData.partition}
  onChange={(e) => setFormData({ ...formData, partition: e.target.value })}
  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
>
  {partitions.map((p) => (
    <option key={p.name} value={p.name}>{p.label}</option>
  ))}
</select>

{/* Resource Configuration - 편집 가능 */}
<div onClick={() => handleConfigChange(index)} className="cursor-pointer">
  {config.total_cores} Total Cores
</div>
```

**After** (읽기 전용):
```typescript
{/* Template 선택 시: 읽기 전용 표시 */}
{selectedTemplateForJob ? (
  <div className="space-y-3">
    {/* Partition - 읽기 전용 */}
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1">
        Partition (from Template)
        <span className="ml-2 text-xs text-gray-500">🔒 Read-only</span>
      </label>
      <div className="px-3 py-2 bg-gray-100 border border-gray-300 rounded-lg text-gray-700">
        {selectedTemplateForJob.slurm?.partition || 'N/A'}
      </div>
    </div>

    {/* Nodes - 읽기 전용 */}
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1">
        Resource Configuration (from Template)
        <span className="ml-2 text-xs text-gray-500">🔒 Read-only</span>
      </label>
      <div className="px-3 py-2 bg-gray-100 border border-gray-300 rounded-lg text-gray-700">
        <div className="font-semibold">
          {(selectedTemplateForJob.slurm?.nodes || 1) * (selectedTemplateForJob.slurm?.ntasks || 1)} Total Cores
        </div>
        <div className="text-sm text-gray-600">
          {selectedTemplateForJob.slurm?.nodes || 1} node(s) × {selectedTemplateForJob.slurm?.ntasks || 1} CPUs/node
        </div>
      </div>
    </div>

    {/* Memory - 편집 가능 */}
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1">
        Memory
        <span className="ml-2 text-xs text-blue-600">✏️ Override allowed</span>
      </label>
      <input
        type="text"
        value={formData.memory}
        onChange={(e) => setFormData({ ...formData, memory: e.target.value })}
        className="w-full px-3 py-2 border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500"
        placeholder={selectedTemplateForJob.slurm?.mem || "16G"}
      />
      <p className="text-xs text-gray-500 mt-1">
        Template default: {selectedTemplateForJob.slurm?.mem || "16G"}
      </p>
    </div>

    {/* Time - 편집 가능 */}
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1">
        Time Limit
        <span className="ml-2 text-xs text-blue-600">✏️ Override allowed</span>
      </label>
      <input
        type="text"
        value={formData.time}
        onChange={(e) => setFormData({ ...formData, time: e.target.value })}
        className="w-full px-3 py-2 border border-blue-300 rounded-lg focus:ring-2 focus:ring-blue-500"
        placeholder="HH:MM:SS"
      />
      <p className="text-xs text-gray-500 mt-1">
        Template default: {selectedTemplateForJob.slurm?.time || "01:00:00"}
      </p>
    </div>
  </div>
) : (
  <div className="text-gray-500 text-sm italic">
    Please select a template to view Slurm configuration
  </div>
)}
```

#### 2. `JobManagement.tsx` - 파일 업로드 검증 UI

**추가 위치**: TemplateFileUpload 아래

```typescript
{/* 파일 업로드 검증 상태 표시 */}
{selectedTemplateForJob?.files?.input_schema && (
  <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
    <h4 className="text-sm font-semibold text-blue-900 mb-2">
      📋 File Upload Status
    </h4>

    {/* 필수 파일 체크 */}
    {(selectedTemplateForJob.files.input_schema.required || []).map(fileReq => {
      const isUploaded = templateFiles.some(f => f.file_key === fileReq.file_key);

      return (
        <div key={fileReq.file_key} className="flex items-center gap-2 text-sm mb-1">
          {isUploaded ? (
            <span className="text-green-600">✅</span>
          ) : (
            <span className="text-red-600">❌</span>
          )}
          <span className={isUploaded ? 'text-gray-700' : 'text-red-700 font-semibold'}>
            {fileReq.name} ({fileReq.file_key})
          </span>
          {!isUploaded && (
            <span className="text-red-600 text-xs ml-auto">Required</span>
          )}
        </div>
      );
    })}

    {/* 선택적 파일 체크 */}
    {(selectedTemplateForJob.files.input_schema.optional || []).map(fileReq => {
      const isUploaded = templateFiles.some(f => f.file_key === fileReq.file_key);

      return (
        <div key={fileReq.file_key} className="flex items-center gap-2 text-sm mb-1">
          {isUploaded ? (
            <span className="text-green-600">✅</span>
          ) : (
            <span className="text-gray-400">⭕</span>
          )}
          <span className={isUploaded ? 'text-gray-700' : 'text-gray-500'}>
            {fileReq.name} ({fileReq.file_key})
          </span>
          {!isUploaded && (
            <span className="text-gray-500 text-xs ml-auto">Optional</span>
          )}
        </div>
      );
    })}
  </div>
)}
```

#### 3. `JobManagement.tsx` - Submit 버튼 검증

**변경 위치**: Submit 버튼

```typescript
{/* Submit Button */}
<button
  type="submit"
  disabled={isSubmitDisabled}
  className={`w-full py-2 rounded-lg font-semibold transition-colors ${
    isSubmitDisabled
      ? 'bg-gray-300 text-gray-500 cursor-not-allowed'
      : 'bg-blue-600 text-white hover:bg-blue-700'
  }`}
>
  {isSubmitDisabled ? '⚠️ Missing Required Files' : 'Submit Job'}
</button>

{/* Submit 검증 로직 */}
const isSubmitDisabled = useMemo(() => {
  if (!selectedTemplateForJob) return true;

  const requiredFiles = selectedTemplateForJob.files?.input_schema?.required || [];
  const uploadedKeys = templateFiles.map(f => f.file_key);

  const allRequiredUploaded = requiredFiles.every(
    req => uploadedKeys.includes(req.file_key)
  );

  return !allRequiredUploaded;
}, [selectedTemplateForJob, templateFiles]);
```

---

## 🧪 테스트 시나리오

### Scenario 1: 필수 파일 누락

**Steps**:
1. Template 선택: "angle-drop-simulation-v2"
2. 필수 파일 스키마: `geometry` (STL), `config` (JSON)
3. `geometry` 파일만 업로드, `config` 누락
4. Submit 버튼 클릭 시도

**Expected**:
- ❌ Submit 버튼 비활성화 (회색)
- ⚠️ 경고 메시지: "Missing Required Files"
- 📋 파일 상태: `config` 옆에 ❌ 표시

---

### Scenario 2: 잘못된 파일 확장자

**Steps**:
1. Template 선택: "angle-drop-simulation-v2"
2. `geometry` 파일로 `.txt` 파일 업로드 (`.stl` 필요)
3. Submit 버튼 클릭

**Expected**:
- Backend 응답: `400 Bad Request`
- Error: "Invalid file extension for geometry: .txt (allowed: .stl, .STL)"

---

### Scenario 3: Template 설정 강제

**Steps**:
1. Template 선택: "my-simulation-v1" (partition=normal, nodes=1, ntasks=4)
2. UI에서 Partition, Nodes 필드 확인

**Expected**:
- ✅ Partition 표시: "normal" (읽기 전용, 회색 배경)
- ✅ Resource Configuration: "4 Total Cores (1 node × 4 CPUs)" (읽기 전용)
- ✅ Memory, Time: 편집 가능 (파란색 테두리)
- ℹ️ 안내 메시지: "🔒 Read-only (from Template)"

---

### Scenario 4: 스크립트 미리보기

**Steps**:
1. Template 선택
2. Memory "8G", Time "02:00:00" 입력
3. "🔍 Preview Full Script" 버튼 클릭

**Expected**:
- GET `/api/jobs/preview` 호출
- 모달에 생성될 스크립트 전체 표시 (읽기 전용)
- 예상 비용 표시: "$1.04 for 2 hours"
- ✅ 수정 불가 (복사만 가능)

---

## 📊 slurm_overrides 변경 사항

### Before (호환성 문제)
```javascript
const slurmOverrides = {
  memory: formData.memory,
  time: formData.time,
};
```

### After (정책 강제)
```javascript
// Template 선택 시: memory, time만 override
const slurmOverrides = {
  mem: formData.memory,     // memory → mem (Backend 필드명 통일)
  time: formData.time,
};

// ❌ 전송하지 않음 (Template 기본값 사용):
// - partition
// - nodes
// - ntasks
// - cpus_per_task
```

**Backend 처리**:
```python
# Template 기본값
slurm_config = normalized_template['slurm'].copy()
# {
#   "partition": "normal",
#   "nodes": 1,
#   "ntasks": 4,
#   "cpus_per_task": 1,
#   "mem": "4G",
#   "time": "01:00:00"
# }

# 사용자 override (memory, time만)
slurm_config.update(slurm_overrides)
# {
#   "partition": "normal",      # Template 기본값 유지
#   "nodes": 1,                 # Template 기본값 유지
#   "ntasks": 4,                # Template 기본값 유지
#   "cpus_per_task": 1,         # Template 기본값 유지
#   "mem": "8G",                # ✅ 사용자 override
#   "time": "02:00:00"          # ✅ 사용자 override
# }
```

---

## ✅ 구현 체크리스트

### Backend (job_submit_api.py)
- [ ] `validate_file_schema_strict()` 함수 추가
- [ ] `find_file_definition()` Helper 함수 추가
- [ ] `parse_size_string()` Helper 함수 추가
- [ ] `verify_script_file_mappings()` 함수 추가
- [ ] 파일 검증 로직 교체 (Lines 466-484)
- [ ] 스크립트 파일 매핑 검증 추가
- [ ] 에러 코드 추가: `FILE_EXTENSION_INVALID = 2006`

### Frontend (JobManagement.tsx)
- [ ] Partition UI 읽기 전용으로 변경 (Lines 925-953)
- [ ] Resource Configuration UI 읽기 전용으로 변경 (Lines 956-999)
- [ ] Memory, Time Override UI 개선 (파란색 테두리 + 안내)
- [ ] 파일 업로드 상태 표시 UI 추가
- [ ] Submit 버튼 검증 로직 추가 (`isSubmitDisabled`)
- [ ] 스크립트 편집 UI 제거, 읽기 전용 미리보기로 교체
- [ ] slurm_overrides 전송 데이터 수정 (memory, time만)

### Testing
- [ ] Scenario 1: 필수 파일 누락 테스트
- [ ] Scenario 2: 잘못된 파일 확장자 테스트
- [ ] Scenario 3: Template 설정 강제 테스트
- [ ] Scenario 4: 스크립트 미리보기 테스트
- [ ] Job 제출 후 DB 확인 (partition, nodes 값 확인)

---

**작성자**: Claude
**최종 업데이트**: 2025-11-15
**목표**: Template 정책 강제 + 보안 강화 + 사용자 경험 개선
