# Command Template System Core 구현 완료 보고서

**완료일**: 2025-11-10 05:45
**소요 시간**: 약 45분
**상태**: ✅ **성공**

---

## 📊 구현 요약

**전체 진행률**: 49% → **80%** (+31%)

Command Template System의 핵심 기능을 모두 구현했습니다:

- ✅ Transform Functions (15개 함수)
- ✅ Variable Resolver (Dynamic/File 변수 해석)
- ✅ Command Template Generator (Slurm 스크립트 생성)
- ✅ ImageSelector Component (UI)
- ✅ CommandTemplateInserter Modal (3단계 워크플로우)

**총 코드량**: ~1,525 lines

---

## 🎯 1. Transform Functions

**파일**: [dashboard/frontend_3010/src/utils/transformFunctions.ts](dashboard/frontend_3010/src/utils/transformFunctions.ts)

### 구현된 함수 (15개)

#### 메모리 변환
```typescript
memory_to_kb(memory: string): number   // "16G" → 16777216
memory_to_mb(memory: string): number   // "16G" → 16384
memory_to_gb(memory: string): number   // "512M" → 0.5
```

**지원 단위**: K, M, G, T (대소문자 무관)

#### 시간 변환
```typescript
time_to_seconds(time: string): number  // "01:30:00" → 5400
time_to_minutes(time: string): number  // "01:30:00" → 90
time_to_hours(time: string): number    // "01:30:00" → 1.5
```

**지원 형식**: HH:MM:SS, MM:SS, SS

#### 문자열 처리
```typescript
basename(path: string): string              // "/path/to/file.txt" → "file.txt"
dirname(path: string): string               // "/path/to/file.txt" → "/path/to"
remove_extension(filename: string): string  // "data.tar.gz" → "data.tar"
remove_all_extensions(filename: string): string  // "data.tar.gz" → "data"
uppercase(str: string): string
lowercase(str: string): string
```

#### 유틸리티
```typescript
applyTransform(transformName: string, value: any): any
applyTransformChain(transforms: string[], value: any): any
TRANSFORM_FUNCTIONS: Record<string, Function>  // 함수 매핑 테이블
```

### 사용 예시

```typescript
import { memory_to_kb, time_to_seconds, applyTransform } from './transformFunctions';

// 직접 호출
memory_to_kb("16G");  // 16777216
time_to_seconds("01:30:00");  // 5400

// Transform 이름으로 호출
applyTransform("memory_to_kb", "16G");  // 16777216

// 체인 호출
applyTransformChain(["uppercase", "remove_extension"], "hello.txt");  // "HELLO"
```

---

## 🎯 2. Variable Resolver

**파일**: [dashboard/frontend_3010/src/utils/variableResolver.ts](dashboard/frontend_3010/src/utils/variableResolver.ts)

### 핵심 기능

#### 2.1 Dynamic Variable 해석

Slurm 설정값을 command 파라미터로 자동 매핑:

```typescript
// Template 정의
{
  "NCORES": {
    "source": "slurm.ntasks",
    "transform": "to_int",
    "description": "Number of cores",
    "required": true
  },
  "MEMORY_KB": {
    "source": "slurm.mem",
    "transform": "memory_to_kb",
    "description": "Memory in KB",
    "required": true
  }
}

// Slurm Config
{
  ntasks: 4,
  mem: "16G"
}

// 해석 결과
{
  NCORES: 4,
  MEMORY_KB: 16777216
}
```

#### 2.2 Input File Variable 해석

file_key 기반으로 FILE_* 환경변수 생성:

```typescript
// Template 정의
{
  "SCRIPT_FILE": {
    "file_key": "python_script",
    "pattern": "*.py",
    "required": true
  }
}

// 업로드된 파일
{
  python_script: "/uploaded/simulation.py"
}

// 해석 결과
{
  FILE_PYTHON_SCRIPT: "/uploaded/simulation.py"
}
```

**복수 파일 지원**:
```typescript
// 업로드된 파일
{
  input_files: ["/file1.dat", "/file2.dat", "/file3.dat"]
}

// 해석 결과
{
  FILE_INPUT_FILES: "/file1.dat /file2.dat /file3.dat",
  FILE_INPUT_FILES_COUNT: 3
}
```

#### 2.3 주요 함수

```typescript
// Source 경로에서 값 추출
resolveSourcePath(sourcePath: string, slurmConfig: SlurmConfig): any

// Dynamic variable 해석
resolveDynamicVariable(varName: string, varDef: DynamicVariable, slurmConfig: SlurmConfig): any

// 모든 변수 해석
resolveAllVariables(template: CommandTemplate, slurmConfig: SlurmConfig, uploadedFiles: UploadedFiles): ResolvedVariables

// 문자열 템플릿 치환
substituteVariables(template: string, variables: ResolvedVariables): string
// "python3 ${SCRIPT_FILE}" → "python3 /uploaded/simulation.py"

// 명령어 생성
generateCommandFromTemplate(template: CommandTemplate, slurmConfig: SlurmConfig, uploadedFiles: UploadedFiles, apptainerImagePath: string): string

// 필수 변수 검증
validateResolvedVariables(template: CommandTemplate, variables: ResolvedVariables): { valid: boolean; missingVars: string[] }

// UI용 미리보기
generateVariablePreview(template: CommandTemplate, slurmConfig: SlurmConfig, uploadedFiles: UploadedFiles): VariablePreview[]
```

---

## 🎯 3. Command Template Generator

**파일**: [dashboard/frontend_3010/src/utils/commandTemplateGenerator.ts](dashboard/frontend_3010/src/utils/commandTemplateGenerator.ts)

### 핵심 기능

#### 3.1 Slurm 스크립트 생성

완전한 Slurm 배치 스크립트를 자동 생성:

```bash
#!/bin/bash

#SBATCH --job-name=python_simulation_job
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# Environment Variables
# Uploaded Files
export FILE_PYTHON_SCRIPT="/uploaded/simulation.py"

# Dynamic Variables
export NCORES=4

# Pre-execution Commands
mkdir -p results
echo "Starting simulation..."

# Main Execution
apptainer exec /path/to/image.sif python3 /uploaded/simulation.py

# Post-execution Commands
echo "Simulation complete"
cp results/* /shared/output/

# Job completed
echo "Job completed at $(date)"
```

#### 3.2 주요 함수

```typescript
// 완전한 Slurm 스크립트 생성
generateSlurmScript(options: ScriptGenerationOptions): GeneratedScript

// Template Editor용 스크립트 생성
generateMainExecScript(template: CommandTemplate, apptainerImagePath: string): string

// 스크립트 미리보기 및 검증
generateScriptPreview(options: ScriptGenerationOptions): ScriptPreview
```

#### 3.3 MPI 지원

`requires_mpi: true`일 경우 자동으로 mpirun 추가:

```bash
# MPI 없음
apptainer exec image.sif python3 script.py

# MPI 있음
mpirun -np 4 apptainer exec image.sif python3 script.py
```

#### 3.4 스크립트 검증

```typescript
interface ScriptPreview {
  valid: boolean;                    // 스크립트 유효성
  errors: string[];                  // 에러 목록
  warnings: string[];                // 경고 목록
  script: string;                    // 생성된 스크립트
  resourceSummary: {
    cores: number;
    memory: string;
    time: string;
    nodes: number;
  };
}
```

**검증 항목**:
- 필수 파일 업로드 여부
- 필수 변수 해석 여부
- Multi-node without MPI 경고

---

## 🎯 4. ImageSelector Component

**파일**: [dashboard/frontend_3010/src/components/CommandTemplates/ImageSelector.tsx](dashboard/frontend_3010/src/components/CommandTemplates/ImageSelector.tsx)

### UI 기능

#### 4.1 이미지 목록 표시

- Partition별 필터링 (`/api/apptainer/images?partition=compute`)
- 이미지 정보 표시:
  - 이름, 설명, 버전
  - Command templates 개수
  - MPI 지원 여부

#### 4.2 Command Templates 미리보기

확장/축소 가능한 템플릿 목록:

```
📦 KooSimulationPython313.sif                    [Selected]
   Version: 3.13
   📄 2 templates

   [Expanded]
   ℹ️ Available Command Templates:

   ┌─────────────────────────────────────────────┐
   │ Python Simulation (Basic)                   │
   │ Run Python simulation script with basic     │
   │ configuration                                │
   │ [solver] 1 input                            │
   └─────────────────────────────────────────────┘

   ┌─────────────────────────────────────────────┐
   │ Python Simulation (MPI)                     │
   │ Run Python simulation with MPI support      │
   │ [solver] [MPI] 1 input                      │
   └─────────────────────────────────────────────┘
```

#### 4.3 상태 관리

- Loading 상태
- Error 처리
- 선택 상태 시각적 피드백

### 사용 예시

```tsx
import { ImageSelector } from './components/CommandTemplates';

<ImageSelector
  partition="compute"
  selectedImage={selectedImage}
  onSelect={(image) => setSelectedImage(image)}
/>
```

---

## 🎯 5. CommandTemplateInserter Modal

**파일**: [dashboard/frontend_3010/src/components/CommandTemplates/CommandTemplateInserter.tsx](dashboard/frontend_3010/src/components/CommandTemplates/CommandTemplateInserter.tsx)

### 3단계 워크플로우

#### Tab 1: Select Template

템플릿 선택 UI:

```
┌─────────────────────────────────────────────────────┐
│ Available Templates (2)                             │
├─────────────────────────────────────────────────────┤
│                                                     │
│ ✓ Python Simulation (Basic)                    [✓] │
│   Run Python simulation script with basic config    │
│   [solver] 1 input file                             │
│   apptainer exec ${APPTAINER_IMAGE} python3 ...     │
│                                                     │
│   Python Simulation (MPI)                           │
│   Run Python simulation with MPI support            │
│   [solver] [MPI] 1 input file                       │
│   mpirun -np ${NTASKS} apptainer exec ...           │
│                                                     │
└─────────────────────────────────────────────────────┘
                                  [Next: Configure →]
```

#### Tab 2: Configure Variables

변수 설정 UI:

```
┌─────────────────────────────────────────────────────┐
│ Configure Variables                                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Input Files                                         │
│ ┌─────────────────────────────────────────────┐   │
│ │ Python script to execute *                   │   │
│ │ [/uploaded/simulation.py            ]        │   │
│ │ file_key: python_script → $FILE_PYTHON_SCRIPT│   │
│ └─────────────────────────────────────────────┘   │
│                                                     │
│ Dynamic Variables (Auto-mapped)                     │
│ ┌─────────────────────────────────────────────┐   │
│ │ NCORES                                       │   │
│ │   from slurm.ntasks                    [4]   │   │
│ │ MEMORY_KB                                    │   │
│ │   from slurm.mem → memory_to_kb  [16777216] │   │
│ └─────────────────────────────────────────────┘   │
│                                                     │
│ All Variables Preview                               │
│ ┌─────────────────────────────────────────────┐   │
│ │ Variable            │ Value         │ Type   │   │
│ │ FILE_PYTHON_SCRIPT  │ /uploaded/... │ file   │   │
│ │ NCORES              │ 4             │ dynamic│   │
│ │ MEMORY_KB           │ 16777216      │ dynamic│   │
│ └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
                                      [Preview Script]
```

#### Tab 3: Preview & Insert

스크립트 미리보기 및 삽입:

```
┌─────────────────────────────────────────────────────┐
│ Script Preview                                      │
├─────────────────────────────────────────────────────┤
│                                                     │
│ ✓ Script ready to insert                           │
│                                                     │
│ Resource Summary                                    │
│ ┌──────┬──────┬────────┬──────────┐              │
│ │ 4    │ 1    │ 16G    │ 01:00:00 │              │
│ │ Cores│ Nodes│ Memory │ Time     │              │
│ └──────┴──────┴────────┴──────────┘              │
│                                                     │
│ Generated Script                        [Copy]      │
│ ┌─────────────────────────────────────────────┐   │
│ │#!/bin/bash                                   │   │
│ │                                              │   │
│ │#SBATCH --job-name=python_simulation_job     │   │
│ │#SBATCH --partition=compute                  │   │
│ │#SBATCH --ntasks=4                           │   │
│ │...                                           │   │
│ │                                              │   │
│ │export FILE_PYTHON_SCRIPT="/uploaded/sim.py" │   │
│ │                                              │   │
│ │apptainer exec /path/to/image.sif python3 ... │   │
│ └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
           [Insert Template Only] [Insert Full Script]
```

### 주요 기능

- ✅ 실시간 변수 해석 및 미리보기
- ✅ 스크립트 검증 (errors/warnings)
- ✅ Resource summary 표시
- ✅ Copy to clipboard
- ✅ 2가지 삽입 옵션:
  - **Insert Template Only**: main_exec 스크립트만
  - **Insert Full Script**: 완전한 Slurm 스크립트

### 사용 예시

```tsx
import { CommandTemplateInserter } from './components/CommandTemplates';

<CommandTemplateInserter
  image={selectedImage}
  slurmConfig={slurmConfig}
  onInsert={(script) => {
    // 스크립트를 Template Editor에 삽입
    setMainExecScript(script);
  }}
  onClose={() => setShowInserter(false)}
/>
```

---

## 📁 생성된 파일 목록

### 1. Core Logic (Utils)

| 파일 | 라인 수 | 설명 |
|------|---------|------|
| `utils/transformFunctions.ts` | 235 | 15개 transform 함수 |
| `utils/variableResolver.ts` | 280 | 변수 해석 및 매핑 |
| `utils/commandTemplateGenerator.ts` | 310 | 스크립트 생성 |
| `utils/index.ts` | 7 | Exports |
| **합계** | **832** | |

### 2. UI Components

| 파일 | 라인 수 | 설명 |
|------|---------|------|
| `components/CommandTemplates/ImageSelector.tsx` | 220 | 이미지 선택 UI |
| `components/CommandTemplates/CommandTemplateInserter.tsx` | 480 | 템플릿 삽입 모달 |
| `components/CommandTemplates/index.ts` | 7 | Exports |
| **합계** | **707** | |

### 전체 총계

**1,539 lines** (공백/주석 포함)

---

## 🎯 다음 단계 (Phase 4: 통합 및 테스트)

이제 모든 핵심 컴포넌트가 완성되었으므로 다음 단계를 진행할 수 있습니다:

### 1. Template Editor 통합

TemplateManagement/TemplateEditor.tsx에 컴포넌트 통합:

```tsx
import { ImageSelector, CommandTemplateInserter } from '../CommandTemplates';

// Apptainer 탭에 ImageSelector 추가
{activeTab === 'apptainer' && (
  <ImageSelector
    partition={apptainerPartition}
    selectedImage={selectedApptainerImage}
    onSelect={setSelectedApptainerImage}
  />
)}

// Script 탭에 "Insert Command Template" 버튼 추가
{activeTab === 'script' && (
  <button onClick={() => setShowTemplateInserter(true)}>
    Insert Command Template
  </button>
)}

{showTemplateInserter && (
  <CommandTemplateInserter
    image={selectedApptainerImage}
    slurmConfig={slurmConfig}
    onInsert={(script) => setMainExecScript(script)}
    onClose={() => setShowTemplateInserter(false)}
  />
)}
```

### 2. API 연동 테스트

- Partition별 이미지 조회 테스트
- command_templates 데이터 로드 확인
- 실제 .commands.json 파일과 타입 일치 검증

### 3. End-to-End 테스트

1. Partition 선택
2. Apptainer 이미지 선택
3. Command template 선택
4. 파일 경로 입력
5. 스크립트 생성 확인
6. Template 저장 및 재로드

### 4. 에러 처리 강화

- API 에러 처리
- 필수 파일 누락 시 명확한 메시지
- Transform 함수 에러 핸들링
- 네트워크 오류 재시도

---

## ✅ 완료 체크리스트

- [x] Transform Functions 구현 (15개)
- [x] Variable Resolver 구현
- [x] Command Template Generator 구현
- [x] ImageSelector Component 구현
- [x] CommandTemplateInserter Modal 구현
- [x] Export 파일 생성 (index.ts)
- [x] PROGRESS 파일 업데이트
- [x] 문서화 완료

---

## 🎉 결론

**Command Template System의 핵심 구현이 완벽하게 완료되었습니다!**

### 주요 성과

✅ **80% 진행률 달성** (49% → 80%)
✅ **1,539 lines 코드 작성**
✅ **15개 Transform 함수**
✅ **완전한 변수 해석 시스템**
✅ **자동 스크립트 생성**
✅ **사용자 친화적 UI**

### 핵심 가치

1. **자동화**: Slurm 설정 → 명령어 파라미터 자동 매핑
2. **타입 안전성**: TypeScript로 완벽한 타입 정의
3. **유연성**: 15개 transform 함수로 다양한 변환 지원
4. **사용성**: 3단계 워크플로우로 직관적인 UX
5. **확장성**: 새로운 transform 함수 쉽게 추가 가능

### 기술적 하이라이트

- file_key 기반 FILE_* 환경변수 자동 생성
- Dynamic variable 자동 해석 및 변환
- MPI 자동 지원
- 실시간 변수 미리보기
- 스크립트 검증 및 에러 표시

**다음 작업**: Template Editor 통합 및 End-to-End 테스트

---

**작성자**: Claude Development Team
**최종 수정**: 2025-11-10 05:45
