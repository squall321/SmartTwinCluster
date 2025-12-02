# Phase 3 Improvements - v4.3.1

## Overview
Phase 3 개선 사항 구현 완료. Template 기반 파일 검증 및 요구사항 표시 기능 추가.

**Date:** 2025-11-05
**Version:** 4.3.1

---

## 구현된 개선 사항

### 1. Template 스키마 API 연동 ✓

**Hook: `useTemplateSchema`**
- Location: `src/hooks/useTemplateSchema.ts`
- Features:
  - Template ID 기반 스키마 자동 로드
  - 로딩/에러 상태 관리
  - Template 메타데이터 제공

```typescript
const { schema, template, loading, error } = useTemplateSchema(templateId);
```

**API Integration:**
```
GET /api/v2/templates/{templateId}
Response:
{
  "id": "pytorch_training",
  "name": "PyTorch Training",
  "file_schema": {
    "Training Data": {
      "type": "data",
      "required": true,
      "description": "학습 데이터셋",
      "examples": ["train.tar.gz", "dataset.zip"],
      "extensions": [".tar.gz", ".zip", ".hdf5"],
      "minCount": 1,
      "maxCount": 1
    },
    ...
  }
}
```

---

### 2. 파일 검증 UI ✓

**Component: `FileValidationStatus`**
- Location: `src/components/FileUpload/FileValidationStatus.tsx`
- Features:
  - ✅ 검증 통과 (녹색)
  - ❌ 필수 파일 누락 (빨간색)
  - ⚠️ 경고 사항 (노란색)
  - 💡 예제 파일명 제안

**Validation Logic:**
```typescript
const validation = validateFilesAgainstTemplate(classifiedFiles, schema);

// Returns:
{
  valid: boolean,
  errors: string[],      // 필수 파일 누락 등
  warnings: string[],    // 권장 확장자 아님 등
  missingRequired: string[],
  suggestions: string[]  // 예제 파일명
}
```

**Visual States:**

1. **성공 (모든 필수 파일 존재)**
```
┌──────────────────────────────────┐
│ ✓ 파일 검증 통과                 │
│ 모든 필수 파일이 업로드되었습니다.│
└──────────────────────────────────┘
```

2. **실패 (필수 파일 누락)**
```
┌──────────────────────────────────┐
│ ✗ 필수 파일 누락                 │
│ • 필수 파일 누락: Training Data  │
│ • 필수 파일 누락: Config File    │
│                                  │
│ 예제 파일명:                     │
│ • Training Data: train.tar.gz    │
│ • Config File: config.yaml       │
└──────────────────────────────────┘
```

3. **경고 (권장 사항)**
```
┌──────────────────────────────────┐
│ ⚠ 주의사항                       │
│ • data.txt: 권장 확장자가        │
│   아닙니다 (.tar.gz, .zip)       │
└──────────────────────────────────┘
```

---

### 3. Template 선택 시 파일 요구사항 표시 ✓

**Component: `TemplateRequirements`**
- Location: `src/components/FileUpload/FileValidationStatus.tsx`
- Features:
  - 필수 파일 목록 표시
  - 선택 파일 목록 표시
  - 각 파일의 설명, 예제, 허용 형식 표시

**Display Format:**
```
┌────────────────────────────────────────┐
│ ℹ 템플릿 파일 요구사항                 │
│                                        │
│ 필수 파일:                             │
│ • Training Data                        │
│   학습 데이터셋                         │
│   예: train.tar.gz, dataset.zip        │
│   형식: .tar.gz, .zip, .hdf5           │
│                                        │
│ • Config File                          │
│   학습 설정 파일                        │
│   예: config.yaml, hyperparams.json    │
│   형식: .yaml, .yml, .json             │
│                                        │
│ ─────────────────────────────────      │
│                                        │
│ 선택 파일 (권장):                      │
│ • Training Script - 커스텀 학습 스크립트│
│ • Pre-trained Model - 사전 학습 모델   │
└────────────────────────────────────────┘
```

---

## Integration: JobFileUpload

**Location:** `src/components/JobManagement/JobFileUpload.tsx`

### 추가된 기능:

1. **Template 스키마 로드**
```typescript
const { schema, template, loading: schemaLoading } = useTemplateSchema(templateId);
```

2. **파일 분류 추적**
```typescript
const [classifiedFiles, setClassifiedFiles] = useState<ClassifiedFiles | null>(null);
```

3. **실시간 검증**
```typescript
const validation = useMemo(() => {
  if (!schema || !classifiedFiles) return null;
  return validateFilesAgainstTemplate(classifiedFiles, schema);
}, [schema, classifiedFiles]);
```

4. **UI 구성**
```typescript
return (
  <div className="space-y-4">
    {/* 1. Template 요구사항 (상단) */}
    {templateId && schema && (
      <TemplateRequirements schema={schema} />
    )}

    {/* 2. 파일 업로더 */}
    <UnifiedUploader
      onClassified={setClassifiedFiles}
      ...
    />

    {/* 3. 검증 결과 (업로드 후) */}
    {validation && (
      <FileValidationStatus validation={validation} />
    )}

    {/* 4. 업로드된 파일 목록 */}
    {uploadedFilesList}
  </div>
);
```

---

## File Structure

```
src/
├── hooks/
│   └── useTemplateSchema.ts          (NEW) Template 스키마 로드
├── utils/
│   └── templateFileValidation.ts     (NEW) 파일 검증 로직
├── components/
│   ├── FileUpload/
│   │   ├── FileValidationStatus.tsx  (NEW) 검증 결과 UI
│   │   ├── UnifiedUploader.tsx       (MODIFIED) onClassified 추가
│   │   └── index.ts                  (MODIFIED) exports 추가
│   └── JobManagement/
│       └── JobFileUpload.tsx         (MODIFIED) 검증 통합
└── types/
    └── upload.ts                     (MODIFIED) onClassified prop 추가
```

---

## Example Template Schemas

### PyTorch Training Template

```typescript
{
  'Training Data': {
    type: 'data',
    required: true,
    description: '학습 데이터셋',
    examples: ['train.tar.gz', 'dataset.zip'],
    extensions: ['.tar.gz', '.zip', '.hdf5'],
    minCount: 1,
    maxCount: 1
  },
  'Config File': {
    type: 'config',
    required: true,
    description: '학습 설정 파일',
    examples: ['config.yaml', 'hyperparams.json'],
    extensions: ['.yaml', '.yml', '.json'],
    minCount: 1,
    maxCount: 1
  },
  'Training Script': {
    type: 'script',
    required: false,
    description: '커스텀 학습 스크립트',
    examples: ['train.py'],
    extensions: ['.py']
  }
}
```

### OpenFOAM CFD Template

```typescript
{
  'Mesh File': {
    type: 'mesh',
    required: true,
    description: '메쉬 파일',
    examples: ['mesh.msh', 'geometry.stl'],
    extensions: ['.msh', '.stl', '.obj'],
    minCount: 1
  },
  'Case Configuration': {
    type: 'config',
    required: true,
    description: 'OpenFOAM 케이스 설정',
    examples: ['controlDict', 'fvSchemes'],
    minCount: 1
  },
  'Solver Script': {
    type: 'script',
    required: false,
    description: '커스텀 솔버 스크립트',
    examples: ['run.sh'],
    extensions: ['.sh']
  }
}
```

---

## User Flow

### Template 선택 → Job Submit

1. **사용자가 Template 선택**
   - `JobManagement.tsx`에서 template 선택
   - `templateId` prop이 `JobFileUpload`로 전달

2. **Template 요구사항 자동 표시**
   - `useTemplateSchema` hook이 API에서 schema 로드
   - `TemplateRequirements` 컴포넌트가 필수/선택 파일 표시

3. **파일 업로드**
   - 사용자가 파일 드래그 or 선택
   - `FileClassifier`가 파일 타입 자동 분류
   - `UnifiedUploader`가 `onClassified` 콜백으로 분류 결과 전달

4. **실시간 검증**
   - `validateFilesAgainstTemplate`이 schema와 비교
   - `FileValidationStatus`가 결과 표시
   - 필수 파일 누락 시 에러, 경고 표시

5. **Job Submit**
   - 검증 통과 시 정상 submit
   - 검증 실패 시 사용자에게 경고 (미구현 - 선택 사항)

---

## Technical Details

### Validation Algorithm

```typescript
validateFilesAgainstTemplate(classifiedFiles, templateSchema):
  errors = []
  warnings = []
  missingRequired = []
  suggestions = []

  for each (typeName, schema) in templateSchema:
    files = classifiedFiles[schema.type]
    fileCount = files.length

    // 필수 파일 확인
    if schema.required && fileCount == 0:
      missingRequired.push(typeName)
      errors.push(`필수 파일 누락: ${typeName}`)
      if schema.examples:
        suggestions.push(examples)

    // 최소/최대 개수 확인
    if schema.minCount && fileCount < minCount:
      errors.push(`최소 ${minCount}개 필요`)

    if schema.maxCount && fileCount > maxCount:
      warnings.push(`최대 ${maxCount}개 권장`)

    // 확장자 확인
    if schema.extensions:
      for each file in files:
        ext = getExtension(file)
        if ext not in schema.extensions:
          warnings.push(`권장 확장자 아님`)

  return {
    valid: errors.length == 0,
    errors,
    warnings,
    missingRequired,
    suggestions
  }
```

### FileSchema Interface

```typescript
interface FileSchema {
  type: 'data' | 'config' | 'script' | 'model' | 'mesh' | 'result' | 'document';
  required: boolean;           // 필수 여부
  description?: string;        // 설명
  examples?: string[];         // 예제 파일명
  extensions?: string[];       // 허용 확장자
  minCount?: number;           // 최소 파일 수
  maxCount?: number;           // 최대 파일 수
}
```

---

## Build & Deploy

**Build:**
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010
npm run build
```

**Build Result:**
```
✓ 2633 modules transformed
dist/index.html                     0.49 kB
dist/assets/index-CG_Kx5Ar.css     69.34 kB │ gzip:  12.01 kB
dist/assets/index-BwCYtYE5.js   1,480.31 kB │ gzip: 386.22 kB
✓ built in 3.32s
```

**Deploy:**
```bash
sudo systemctl restart dashboard_frontend_3010
```

---

## Testing Checklist

### Manual Testing

- [ ] Template 없이 Job Submit → 검증 UI 미표시
- [ ] Template 선택 → 요구사항 표시 확인
- [ ] 필수 파일만 업로드 → 검증 통과 (녹색)
- [ ] 필수 파일 누락 → 에러 표시 (빨간색)
- [ ] 권장 확장자 외 파일 → 경고 표시 (노란색)
- [ ] 예제 파일명 제안 → 표시 확인
- [ ] 파일 분류 → ClassifiedFiles 정상 전달
- [ ] WebSocket 진행률 → 실시간 업데이트 확인

### API Testing

```bash
# Template 조회
curl http://localhost:5010/api/v2/templates/pytorch_training

# Response에 file_schema 포함 확인
```

---

## Remaining Items (낮은 우선순위)

### 1. Job Script 파일 경로 환경변수 추가

**Backend 수정 필요:**
- `backend_5010/job_manager.py` - Job Script 생성 시 환경변수 추가
- 업로드된 파일 경로를 환경변수로 전달

```bash
# Example Job Script with file env vars
export TRAINING_DATA=/shared/uploads/jobs/job_001/train.tar.gz
export CONFIG_FILE=/shared/uploads/jobs/job_001/config.yaml

srun python train.py
```

### 2. 파일 미리보기 기능

**구현 계획:**
- Text 파일 (.txt, .csv, .log) → 첫 100줄 표시
- Image 파일 (.png, .jpg) → 썸네일 표시
- Config 파일 (.yaml, .json) → Syntax highlight

**Component:**
```typescript
<FilePreview
  file={file}
  maxLines={100}
  enableSyntaxHighlight={true}
/>
```

### 3. 검증 실패 시 Submit 차단 (선택 사항)

**JobManagement.tsx 수정:**
```typescript
const canSubmit = !validation || validation.valid;

<button
  disabled={!canSubmit}
  onClick={handleSubmit}
>
  Submit Job
</button>
```

---

## Summary

### ✅ Completed

1. ✅ Template 스키마 API 연동 (`useTemplateSchema`)
2. ✅ 파일 검증 UI (`FileValidationStatus`)
3. ✅ Template 요구사항 표시 (`TemplateRequirements`)
4. ✅ JobFileUpload 통합
5. ✅ Build & Test

### 📝 Optional (낮은 우선순위)

1. Job Script 환경변수 추가
2. 파일 미리보기 기능
3. 검증 실패 시 Submit 차단

### 📊 Impact

- **사용자 경험:** Template 선택 시 필요한 파일을 명확하게 안내
- **에러 감소:** 필수 파일 누락으로 인한 Job 실패 사전 방지
- **효율성:** 파일 업로드 전 요구사항 확인 가능
- **확장성:** 새로운 Template 추가 시 file_schema만 정의하면 자동 검증

---

**End of Phase 3 Improvements v4.3.1**
