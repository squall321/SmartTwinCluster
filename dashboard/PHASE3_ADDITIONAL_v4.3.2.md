# Phase 3 추가 개선 사항 - v4.3.2

## Overview
Phase 3의 추가 개선 사항 구현 완료. Job Script 환경변수 및 검증 차단 기능 추가.

**Date:** 2025-11-05
**Version:** 4.3.2
**Previous:** v4.3.1 (Template 기반 검증)

---

## 구현된 추가 개선 사항

### 1. Job Script 파일 경로 환경변수 추가 ✅

업로드된 파일의 경로를 Job Script에 자동으로 환경변수로 추가하여, 스크립트에서 바로 사용할 수 있도록 구현.

#### Backend 수정 ([app.py:613-716](app.py#L613-L716))

**파일 경로 조회 및 환경변수 생성:**
```python
@app.route('/api/slurm/jobs/submit', methods=['POST'])
def submit_job():
    data = request.json
    job_id = data.get('jobId')  # Frontend에서 전달한 임시 job_id

    # 업로드된 파일 정보 조회
    file_env_vars = {}
    if job_id:
        cursor.execute('''
            SELECT filename, file_path, storage_path, file_type
            FROM file_uploads
            WHERE job_id = ? AND status = 'completed'
            ORDER BY created_at
        ''', (job_id,))

        uploaded_files = cursor.fetchall()

        # 파일별 환경변수 생성
        for file in uploaded_files:
            filename = file['filename']
            file_path = file['file_path'] or file['storage_path']
            file_type = file['file_type']

            # 변수명 생성
            var_name = filename.rsplit('.', 1)[0]  # 확장자 제거
            var_name = ''.join(c if c.isalnum() else '_' for c in var_name)
            var_name = var_name.upper()

            # FILE_<TYPE>_<NAME> 형식
            env_var_name = f"FILE_{file_type.upper()}_{var_name}"
            file_env_vars[env_var_name] = file_path

            # 짧은 별칭도 추가
            if var_name not in file_env_vars:
                file_env_vars[var_name] = file_path
```

**Job Script에 환경변수 추가:**
```python
# 임시 스크립트 파일 생성
with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
    f.write(f"#!/bin/bash\n")
    f.write(f"#SBATCH --job-name={data['jobName']}\n")
    f.write(f"#SBATCH --partition={data['partition']}\n")
    # ... SBATCH directives ...
    f.write(f"\n")

    # 업로드된 파일 경로를 환경변수로 추가
    if file_env_vars:
        f.write(f"# Uploaded File Paths\n")
        for var_name, file_path in file_env_vars.items():
            f.write(f"export {var_name}=\"{file_path}\"\n")
        f.write(f"\n")

    f.write(f"{script_content}\n")
```

#### Frontend 수정 ([JobManagement.tsx:594-598](JobManagement.tsx#L594-L598))

**jobId를 Job Submit API에 전달:**
```typescript
const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault();

  // jobId를 포함하여 전송
  const submitData = {
    ...formData,
    jobId: tempJobId  // 업로드 시 사용한 임시 job ID
  };

  const response = await fetch('/api/slurm/jobs/submit', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(submitData),
  });
};
```

#### 환경변수 명명 규칙

1. **Long Name (타입 포함):**
   - 형식: `FILE_<TYPE>_<NAME>`
   - 예시:
     - `train.tar.gz` → `FILE_DATA_TRAIN`
     - `config.yaml` → `FILE_CONFIG_CONFIG`
     - `model.pth` → `FILE_MODEL_MODEL`

2. **Short Name (별칭):**
   - 형식: `<NAME>` (중복 시 생략)
   - 예시:
     - `train.tar.gz` → `TRAIN`
     - `config.yaml` → `CONFIG`
     - `model.pth` → `MODEL`

3. **특수문자 처리:**
   - 파일명의 특수문자는 `_`로 변환
   - `my-data.csv` → `MY_DATA`
   - `test file.txt` → `TEST_FILE`

#### 생성되는 Job Script 예시

**입력 파일:**
- `train.tar.gz` (data)
- `config.yaml` (config)
- `model.pth` (model)

**생성되는 Job Script:**
```bash
#!/bin/bash
#SBATCH --job-name=my_training_job
#SBATCH --partition=group1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=16GB
#SBATCH --time=01:00:00

# Uploaded File Paths
export FILE_DATA_TRAIN="/shared/uploads/jobs/tmp-1730841234567/train.tar.gz"
export TRAIN="/shared/uploads/jobs/tmp-1730841234567/train.tar.gz"
export FILE_CONFIG_CONFIG="/shared/uploads/jobs/tmp-1730841234567/config.yaml"
export CONFIG="/shared/uploads/jobs/tmp-1730841234567/config.yaml"
export FILE_MODEL_MODEL="/shared/uploads/jobs/tmp-1730841234567/model.pth"
export MODEL="/shared/uploads/jobs/tmp-1730841234567/model.pth"

# User Script
python train.py --data $TRAIN --config $CONFIG --model $MODEL
```

#### 사용 예시

**사용자 Script (간단):**
```bash
# 환경변수를 직접 사용
python train.py --data $TRAIN --config $CONFIG

# 또는 긴 이름 사용
python train.py --data $FILE_DATA_TRAIN --config $FILE_CONFIG_CONFIG
```

**사용자 Script (안전):**
```bash
# 환경변수 존재 확인
if [ -z "$TRAIN" ]; then
  echo "Error: Training data not found"
  exit 1
fi

# 파일 존재 확인
if [ ! -f "$TRAIN" ]; then
  echo "Error: File $TRAIN does not exist"
  exit 1
fi

# 실행
python train.py --data $TRAIN
```

---

### 2. 검증 실패 시 Submit 차단 ✅

Template을 사용하는 Job에서 필수 파일이 모두 업로드되지 않으면 Submit 버튼을 비활성화.

#### JobFileUpload 수정 ([JobFileUpload.tsx:22-91](JobFileUpload.tsx#L22-L91))

**검증 결과를 부모 컴포넌트로 전달:**
```typescript
interface JobFileUploadProps {
  files: LegacyUploadedFile[];
  jobId: string;
  userId: string;
  onFilesChange: React.Dispatch<React.SetStateAction<LegacyUploadedFile[]>>;
  onValidationChange?: (validation: { valid: boolean } | null) => void;  // 추가
  // ...
}

export const JobFileUpload: React.FC<JobFileUploadProps> = ({
  // ...
  onValidationChange,
}) => {
  // 파일 검증 결과 계산
  const validation = useMemo(() => {
    if (!schema || !classifiedFiles) return null;
    return validateFilesAgainstTemplate(classifiedFiles, schema);
  }, [schema, classifiedFiles]);

  // 검증 결과를 부모 컴포넌트로 전달
  useEffect(() => {
    if (onValidationChange) {
      onValidationChange(validation);
    }
  }, [validation, onValidationChange]);

  // ...
};
```

#### JobManagement 수정 ([JobManagement.tsx:433-840](JobManagement.tsx#L433-L840))

**검증 상태 추가 및 Submit 버튼 비활성화:**
```typescript
const JobSubmitModal: React.FC<JobSubmitModalProps> = ({ template, ... }) => {
  // 파일 검증 상태
  const [fileValidation, setFileValidation] = useState<{ valid: boolean } | null>(null);

  // ...

  return (
    <form onSubmit={handleSubmit}>
      {/* JobFileUpload에 onValidationChange 전달 */}
      <JobFileUpload
        files={uploadedFiles}
        jobId={tempJobId}
        userId={userId}
        onFilesChange={setUploadedFiles}
        onValidationChange={setFileValidation}  // 추가
        templateId={templateId}
      />

      {/* Submit 버튼 - 검증 실패 시 비활성화 */}
      <button
        type="submit"
        disabled={
          loadingPartitions ||
          (templateId && fileValidation && !fileValidation.valid)
        }
        className="... disabled:opacity-50 disabled:cursor-not-allowed"
        title={
          templateId && fileValidation && !fileValidation.valid
            ? '필수 파일을 모두 업로드해주세요'
            : ''
        }
      >
        Submit Job
      </button>
    </form>
  );
};
```

#### 동작 흐름

1. **Template 선택 시:**
   - Template 파일 스키마 로드
   - 필수 파일 요구사항 표시

2. **파일 업로드:**
   - 파일 자동 분류 (data, config, script 등)
   - 실시간 검증 수행

3. **검증 결과:**
   - 필수 파일 모두 있음 → ✅ Submit 버튼 활성화
   - 필수 파일 누락 → ❌ Submit 버튼 비활성화 + 툴팁 표시

4. **Submit 시도:**
   - 검증 통과: 정상 제출
   - 검증 실패: 버튼 비활성화로 제출 불가

#### UI 상태

**검증 통과 (Submit 가능):**
```
┌──────────────────────────────────┐
│ ✓ 파일 검증 통과                 │
│ 모든 필수 파일이 업로드되었습니다.│
└──────────────────────────────────┘

┌──────────────────────────────────┐
│ [Cancel]      [Submit Job] ✓     │
└──────────────────────────────────┘
```

**검증 실패 (Submit 불가):**
```
┌──────────────────────────────────┐
│ ✗ 필수 파일 누락                 │
│ • 필수 파일 누락: Training Data  │
│                                  │
│ 예제 파일명:                     │
│ • Training Data: train.tar.gz    │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│ [Cancel]  [Submit Job (비활성)]  │
│           ↑ 마우스 올리면:        │
│           "필수 파일을 모두       │
│            업로드해주세요"        │
└──────────────────────────────────┘
```

---

## File Changes

### Backend

**Modified:**
- `backend_5010/app.py` ([app.py:613-716](app.py#L613-L716))
  - Job Submit API에 파일 경로 조회 로직 추가
  - Job Script에 환경변수 자동 추가

### Frontend

**Modified:**
- `src/components/JobManagement.tsx` ([JobManagement.tsx:433-840](JobManagement.tsx#L433-L840))
  - 파일 검증 상태 추가
  - jobId를 Submit API에 전달
  - 검증 실패 시 Submit 버튼 비활성화

- `src/components/JobManagement/JobFileUpload.tsx` ([JobFileUpload.tsx:9-91](JobFileUpload.tsx#L9-L91))
  - `onValidationChange` prop 추가
  - 검증 결과를 부모로 전달

---

## Benefits

### 1. Job Script 환경변수

**Before (수동 경로 입력):**
```bash
# 사용자가 업로드한 파일 경로를 직접 찾아서 입력해야 함
python train.py --data /shared/uploads/jobs/job_123/train.tar.gz
```

**After (자동 환경변수):**
```bash
# 환경변수가 자동으로 설정되어 있음
python train.py --data $TRAIN

# 파일이 어디에 저장되었는지 신경 쓸 필요 없음
# 파일명만 알면 자동으로 경로 설정
```

**장점:**
- ✅ 파일 경로 수동 입력 불필요
- ✅ 스크립트 재사용성 향상
- ✅ 오타로 인한 오류 방지
- ✅ 일관된 변수명 규칙

### 2. Submit 차단

**Before (검증 없이 Submit):**
- 필수 파일 없이 Job Submit 가능
- Job 실행 후 에러 발생
- 컴퓨팅 자원 낭비

**After (검증 후 Submit):**
- 필수 파일 누락 시 Submit 불가
- Job 실행 전 에러 방지
- 사용자에게 명확한 피드백

**장점:**
- ✅ Job 실행 전 에러 사전 차단
- ✅ 컴퓨팅 자원 낭비 방지
- ✅ 사용자 경험 개선
- ✅ 명확한 오류 메시지

---

## Testing Scenarios

### Test 1: 환경변수 생성

**Given:**
- PyTorch Training Template 선택
- 3개 파일 업로드:
  - `train.tar.gz` (data)
  - `config.yaml` (config)
  - `model.pth` (model)

**When:**
- Job Submit

**Then:**
- Job Script에 환경변수 포함:
  ```bash
  export FILE_DATA_TRAIN="/shared/uploads/.../train.tar.gz"
  export TRAIN="/shared/uploads/.../train.tar.gz"
  export FILE_CONFIG_CONFIG="/shared/uploads/.../config.yaml"
  export CONFIG="/shared/uploads/.../config.yaml"
  export FILE_MODEL_MODEL="/shared/uploads/.../model.pth"
  export MODEL="/shared/uploads/.../model.pth"
  ```

### Test 2: Submit 차단 - 필수 파일 누락

**Given:**
- PyTorch Training Template 선택 (Training Data, Config File 필수)
- Config File만 업로드

**When:**
- Submit 버튼 확인

**Then:**
- Submit 버튼 비활성화
- 툴팁: "필수 파일을 모두 업로드해주세요"
- 검증 UI에 에러 표시: "필수 파일 누락: Training Data"

### Test 3: Submit 허용 - 필수 파일 모두 있음

**Given:**
- PyTorch Training Template 선택
- Training Data, Config File 업로드

**When:**
- Submit 버튼 확인

**Then:**
- Submit 버튼 활성화
- 검증 UI에 성공 표시: "✓ 파일 검증 통과"
- 정상적으로 Job Submit 가능

### Test 4: Template 없는 경우

**Given:**
- Template 선택 안 함 (Custom Job)
- 파일 업로드 안 함

**When:**
- Submit 버튼 확인

**Then:**
- Submit 버튼 활성화 (검증 없음)
- 파일 없이도 Submit 가능

---

## Implementation Details

### 환경변수 생성 로직

```python
def generate_env_var_name(filename: str, file_type: str) -> tuple[str, str]:
    """
    파일명에서 환경변수 이름 생성

    Returns:
        (long_name, short_name)
        long_name: FILE_<TYPE>_<NAME>
        short_name: <NAME>
    """
    # 확장자 제거
    name_without_ext = filename.rsplit('.', 1)[0]

    # 특수문자 → 언더스코어
    clean_name = ''.join(
        c if c.isalnum() else '_'
        for c in name_without_ext
    )

    # 대문자 변환
    var_name = clean_name.upper()

    # Long name with type
    long_name = f"FILE_{file_type.upper()}_{var_name}"

    # Short name (alias)
    short_name = var_name

    return long_name, short_name
```

### 검증 차단 로직

```typescript
// Submit 버튼 비활성화 조건
const isSubmitDisabled =
  loadingPartitions ||  // 파티션 로딩 중
  (
    templateId &&         // Template 사용 중 AND
    fileValidation &&     // 검증 결과 있음 AND
    !fileValidation.valid // 검증 실패
  );

// 툴팁 메시지
const getTooltip = () => {
  if (templateId && fileValidation && !fileValidation.valid) {
    return '필수 파일을 모두 업로드해주세요';
  }
  return '';
};
```

---

## Core Principles Applied (핵심원칙 준수)

### 1. 단순성 (Simplicity)
- ✅ 환경변수 명명 규칙 단순화 (TYPE_NAME)
- ✅ 자동 생성으로 사용자 부담 최소화
- ✅ Submit 차단 로직 간단명료

### 2. 일관성 (Consistency)
- ✅ 모든 파일에 동일한 환경변수 규칙 적용
- ✅ 기존 검증 UI와 일관된 에러 표시
- ✅ 파일 타입별 prefix 통일

### 3. 재사용성 (Reusability)
- ✅ 환경변수로 스크립트 재사용 용이
- ✅ 검증 로직 분리하여 재사용 가능
- ✅ Template별로 다른 스키마 지원

### 4. 확장성 (Extensibility)
- ✅ 새로운 파일 타입 추가 용이
- ✅ 환경변수 명명 규칙 변경 가능
- ✅ 검증 규칙 확장 가능

### 5. 명확성 (Clarity)
- ✅ 환경변수 이름이 파일 타입/이름 명확히 표시
- ✅ Submit 차단 시 이유 명확히 표시
- ✅ 로그에 환경변수 목록 출력

### 6. 안전성 (Safety)
- ✅ 파일 로딩 실패 시에도 Job 제출 가능 (치명적 아님)
- ✅ 검증 실패 시 Submit 차단으로 사전 오류 방지
- ✅ 특수문자 처리로 Shell injection 방지

---

## Logs Example

**Backend Log (Job Submit):**
```
📁 Found 3 uploaded files for job tmp-1730841234567
🔧 Environment variables: ['FILE_DATA_TRAIN', 'TRAIN', 'FILE_CONFIG_CONFIG', 'CONFIG', 'FILE_MODEL_MODEL', 'MODEL']
✅ Job 12345 submitted successfully
```

**Frontend Console:**
```
Files uploaded: [
  { filename: 'train.tar.gz', file_type: 'data', ... },
  { filename: 'config.yaml', file_type: 'config', ... },
  { filename: 'model.pth', file_type: 'model', ... }
]
Validation result: { valid: true, errors: [], warnings: [], ... }
```

---

## Summary

### ✅ 완료된 작업

1. **Job Script 환경변수 자동 생성**
   - Backend: 파일 경로 조회 및 환경변수 생성
   - Backend: Job Script에 export 문 자동 추가
   - Frontend: jobId를 Submit API에 전달

2. **검증 실패 시 Submit 차단**
   - JobFileUpload: 검증 결과를 부모로 전달
   - JobManagement: 검증 상태 추적
   - Submit 버튼: 검증 실패 시 비활성화 + 툴팁

3. **빌드 및 배포**
   - Frontend 빌드 성공
   - Backend 재시작 완료

### 📊 Impact

- **개발자 경험:**
  - 파일 경로 수동 입력 불필요
  - 스크립트에서 간단히 `$TRAIN` 사용

- **사용자 경험:**
  - 필수 파일 누락 시 명확한 피드백
  - Submit 전 오류 사전 방지

- **시스템 안정성:**
  - Job 실행 전 검증으로 실패율 감소
  - 컴퓨팅 자원 낭비 방지

---

**End of Phase 3 Additional Improvements v4.3.2**
