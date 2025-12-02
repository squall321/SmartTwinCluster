# Apptainer Command Template System - 설계 전략

**작성일**: 2025-11-08
**목적**: Apptainer 이미지에 명령어 템플릿을 저장하고, Job Template에서 이를 활용하여 자동으로 Slurm 스크립트를 생성하는 시스템 설계

---

## 1. 요구사항 분석

### 1.1 핵심 요구사항

1. **Apptainer 메타데이터에 명령어 템플릿 저장**
   - 각 Apptainer 이미지 JSON 파일에 `command_templates` 필드 추가
   - 명령어 이름, 실행 커맨드, 입출력 파일 패턴 정의
   - 동적 변수 매핑 정보 포함

2. **Job Template에서 Apptainer 이미지 선택 UI 개선**
   - 현재: 이미지 이름을 텍스트로 입력
   - 개선: 실제 존재하는 이미지 목록에서 선택 (드롭다운/멀티셀렉트)
   - 여러 개의 이미지를 선택 가능하도록 확장

3. **스크립트 편집기에서 명령어 템플릿 삽입**
   - 선택한 Apptainer 이미지의 명령어 템플릿 목록 표시
   - 템플릿 선택 시 기본 명령어 구조가 스크립트에 자동 삽입
   - 동적 변수 자동 매핑 (Slurm 설정 → 명령어 파라미터)

4. **동적 변수 바인딩**
   - Job Template의 Slurm 설정 (cores, memory, time 등)을 명령어에 자동 매핑
   - 입력 파일 경로 자동 연결
   - 출력 파일 패턴 자동 설정

---

## 2. 데이터 구조 설계

### 2.1 Apptainer 메타데이터 JSON 확장

**파일 위치**: `/shared/apptainer/metadata/<image_name>.json`

**추가 필드**: `command_templates` (Array)

```json
{
  "id": "abc123",
  "name": "lsdyna_R16d.sif",
  "path": "/opt/apptainers/compute/lsdyna_R16d.sif",
  "partition": "compute",
  "type": "compute",
  "version": "R16d",
  "description": "LS-DYNA R16d solver with MPP support",

  "command_templates": [
    {
      "template_id": "lsdyna_mpp_solver",
      "display_name": "LS-DYNA MPP Solver",
      "description": "Run LS-DYNA simulation with MPI parallelization",
      "category": "solver",

      "command": {
        "executable": "ls-dyna_mpp",
        "format": "mpirun -np ${SLURM_NTASKS} ls-dyna_mpp I=${INPUT_FILE} MEMORY=${MEMORY_KB} NCPU=${SLURM_NTASKS}",
        "requires_mpi": true
      },

      "variables": {
        "dynamic": {
          "SLURM_NTASKS": {
            "source": "slurm.ntasks",
            "description": "Number of MPI processes",
            "required": true
          },
          "MEMORY_KB": {
            "source": "slurm.mem",
            "transform": "memory_to_kb",
            "description": "Memory in KB (converted from Slurm mem)",
            "required": true
          }
        },
        "input_files": {
          "INPUT_FILE": {
            "description": "Main K-file input",
            "pattern": "*.k",
            "required": true,
            "file_key": "k_file"
          }
        },
        "output_files": {
          "d3plot": {
            "pattern": "d3plot*",
            "description": "LS-DYNA result files",
            "collect": true
          },
          "messag": {
            "pattern": "messag*",
            "description": "LS-DYNA message file",
            "collect": true
          }
        }
      },

      "pre_commands": [
        "echo \"Starting LS-DYNA simulation\"",
        "echo \"Input: ${INPUT_FILE}\"",
        "echo \"Cores: ${SLURM_NTASKS}\"",
        "echo \"Memory: ${MEMORY_KB} KB\""
      ],

      "post_commands": [
        "echo \"LS-DYNA simulation completed\"",
        "ls -lh d3plot* messag*"
      ]
    },

    {
      "template_id": "dyna_post_processor_single",
      "display_name": "DynaPostProcessor Single",
      "description": "Post-process LS-DYNA results (single job mode)",
      "category": "post-processing",

      "command": {
        "executable": "KooDynaPostProcessor",
        "format": "KooDynaPostProcessor Single ${D3PLOT_DIR} ${K_FILE_NAME}",
        "requires_mpi": false
      },

      "variables": {
        "dynamic": {},
        "input_files": {
          "D3PLOT_DIR": {
            "description": "Directory containing d3plot files",
            "pattern": "d3plot*",
            "type": "directory",
            "required": true,
            "file_key": "d3plot_directory"
          },
          "K_FILE_NAME": {
            "description": "Original K-file name",
            "pattern": "*.k",
            "required": true,
            "file_key": "k_file_original"
          }
        },
        "input_dependencies": {
          "dynain": {
            "pattern": "dynain*",
            "description": "Dynamic input file from d3plot directory",
            "auto_detect": true,
            "source_dir": "${D3PLOT_DIR}"
          },
          "config_json": {
            "pattern": "${K_FILE_NAME}.json",
            "description": "Configuration JSON based on K-file name",
            "auto_generate": true
          }
        },
        "output_files": {
          "post_results": {
            "pattern": "post_results_*",
            "description": "Post-processing results",
            "collect": true
          }
        }
      },

      "pre_commands": [
        "echo \"Post-processing LS-DYNA results\"",
        "echo \"D3PLOT directory: ${D3PLOT_DIR}\"",
        "echo \"K-file: ${K_FILE_NAME}\""
      ],

      "post_commands": [
        "echo \"Post-processing completed\"",
        "ls -lh post_results_*"
      ]
    }
  ],

  "labels": {},
  "apps": [],
  "env_vars": {}
}
```

### 2.2 Command Template 필드 상세 설명

#### 2.2.1 최상위 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| `template_id` | string | 명령어 템플릿 고유 ID (snake_case) |
| `display_name` | string | UI에 표시될 이름 |
| `description` | string | 명령어 템플릿 설명 |
| `category` | enum | 카테고리: "solver", "pre-processing", "post-processing", "utility" |

#### 2.2.2 `command` 객체

| 필드 | 타입 | 설명 |
|------|------|------|
| `executable` | string | 실행 파일 이름 |
| `format` | string | 전체 명령어 포맷 (변수 포함) |
| `requires_mpi` | boolean | MPI 필요 여부 |

#### 2.2.3 `variables` 객체

**`dynamic` (Slurm 설정에서 자동 매핑)**
- `source`: Job Template의 필드 경로 (예: "slurm.ntasks", "slurm.mem")
- `transform`: 값 변환 함수 (예: "memory_to_kb", "time_to_seconds")
- `required`: 필수 여부

**`input_files` (사용자 업로드 파일)**
- `pattern`: 파일 패턴 (예: "*.k", "*.dat")
- `type`: "file" 또는 "directory"
- `file_key`: Job Template의 files 섹션과 매핑되는 키
- `required`: 필수 여부

**`input_dependencies` (자동 탐지/생성 파일)**
- `auto_detect`: 특정 디렉토리에서 자동 탐지
- `auto_generate`: 다른 파일 기반으로 자동 생성
- `source_dir`: 파일을 찾을 디렉토리

**`output_files` (출력 파일)**
- `pattern`: 출력 파일 패턴
- `collect`: 자동 수집 여부

---

## 3. UI/UX 설계

### 3.1 Template Editor - Apptainer 섹션 개선

**현재 상태**:
```tsx
// 텍스트 입력으로 이미지 이름 입력
<input type="text" value={fixedImageName} onChange={...} />
```

**개선 사항**:

#### 3.1.1 이미지 선택 모드

```tsx
// 1. Mode 선택
<select value={apptainerMode}>
  <option value="partition">파티션별 선택 (기존)</option>
  <option value="specific">특정 이미지 선택 (신규)</option>
  <option value="multiple">복수 이미지 선택 (신규)</option>
</select>

// 2. Mode별 UI

// Mode: "specific" - 단일 이미지 선택
<ImageSelector
  partition={partition}
  selectedImageId={selectedImageId}
  onSelect={handleImageSelect}
  showCommands={true}  // 명령어 템플릿 미리보기
/>

// Mode: "multiple" - 복수 이미지 선택
<MultiImageSelector
  partition={partition}
  selectedImageIds={selectedImageIds}
  onSelect={handleMultiImageSelect}
  showCommands={true}
/>
```

#### 3.1.2 이미지 선택 컴포넌트

```tsx
interface ImageSelectorProps {
  partition: 'compute' | 'viz' | 'all';
  selectedImageId?: string;
  selectedImageIds?: string[];  // 복수 선택용
  mode: 'single' | 'multiple';
  onSelect: (image: ApptainerImage | ApptainerImage[]) => void;
  showCommands?: boolean;  // 명령어 템플릿 표시 여부
}

// UI 구조:
// [검색창]
// [파티션 필터]
//
// 이미지 카드 1
//   - 이름, 버전, 설명
//   - [선택 체크박스/라디오]
//   - 명령어 템플릿 (펼치기/접기)
//     - LS-DYNA MPP Solver
//     - DynaPostProcessor Single
//     - ...
//
// 이미지 카드 2
//   ...
```

### 3.2 Template Editor - Script 섹션 개선

**추가 기능**: Command Template Inserter

```tsx
<div className="script-editor-toolbar">
  {/* 기존 도구 */}
  <button>변수 삽입</button>
  <button>환경변수</button>

  {/* 신규: 명령어 템플릿 삽입 */}
  <button onClick={() => setShowCommandInserter(true)}>
    명령어 템플릿 삽입
  </button>
</div>

{/* Command Template Inserter Modal */}
{showCommandInserter && (
  <CommandTemplateInserter
    selectedImages={selectedApptainerImages}
    onInsert={handleInsertCommandTemplate}
    cursorPosition={scriptCursorPosition}
  />
)}
```

#### 3.2.1 CommandTemplateInserter 컴포넌트

```tsx
interface CommandTemplateInserterProps {
  selectedImages: ApptainerImage[];  // 선택된 이미지 목록
  onInsert: (generatedScript: string) => void;
  cursorPosition: number;
}

// UI 구조:
//
// [이미지 선택 탭]
//   - lsdyna_R16d.sif
//   - KooSimulationPython313.sif
//
// [선택된 이미지: lsdyna_R16d.sif]
//
// 사용 가능한 명령어 템플릿:
//   [라디오] LS-DYNA MPP Solver
//            "Run LS-DYNA simulation with MPI parallelization"
//            필요: SLURM_NTASKS, MEMORY, INPUT_FILE (*.k)
//
//   [라디오] DynaPostProcessor Single
//            "Post-process LS-DYNA results (single job mode)"
//            필요: D3PLOT_DIR, K_FILE_NAME
//
// [변수 매핑 설정]
//   동적 변수:
//     ✓ SLURM_NTASKS: 4 (from slurm.ntasks)
//     ✓ MEMORY_KB: 16777216 (from slurm.mem = "16G")
//
//   입력 파일:
//     INPUT_FILE: [드롭다운: file_key 목록]
//       └─ k_file (*.k) - "Main K-file input"
//
//   출력 파일:
//     ✓ d3plot* (자동 수집)
//     ✓ messag* (자동 수집)
//
// [미리보기]
//   생성될 스크립트:
//   ```bash
//   # LS-DYNA MPP Solver
//   echo "Starting LS-DYNA simulation"
//   echo "Input: $FILE_K_FILE"
//   echo "Cores: 4"
//   echo "Memory: 16777216 KB"
//
//   mpirun -np 4 ls-dyna_mpp I=$FILE_K_FILE MEMORY=16777216 NCPU=4
//
//   echo "LS-DYNA simulation completed"
//   ls -lh d3plot* messag*
//   ```
//
// [삽입] [취소]
```

---

## 4. 워크플로우 설계

### 4.1 전체 흐름

```
1. Apptainer 이미지 스캔
   └─> 메타데이터 JSON에 command_templates 포함

2. Job Template 작성
   ├─> Apptainer 섹션: 이미지 선택
   │   └─> 단일/복수 선택 가능
   │   └─> 명령어 템플릿 미리보기
   │
   ├─> Files 섹션: 입력 파일 스키마 정의
   │   └─> file_key를 명령어 템플릿의 input_files와 매핑
   │
   └─> Script 섹션: 스크립트 작성
       ├─> [명령어 템플릿 삽입] 버튼 클릭
       ├─> 이미지 선택 → 명령어 템플릿 선택
       ├─> 변수 자동 매핑 (Slurm 설정 → 명령어 파라미터)
       ├─> 파일 매핑 (file_key → INPUT_FILE 변수)
       └─> 스크립트 자동 생성 및 삽입

3. Job 제출
   ├─> 파일 업로드 (file_key 기반)
   ├─> Slurm 설정 값 주입
   ├─> 환경 변수 설정
   │   ├─ FILE_K_FILE="/path/to/uploaded.k"
   │   ├─ SLURM_NTASKS=4
   │   └─ MEMORY_KB=16777216
   └─> 스크립트 실행
```

### 4.2 명령어 생성 로직

#### 4.2.1 변수 매핑 우선순위

```
1. 동적 변수 (variables.dynamic)
   - Slurm 설정에서 자동 추출
   - 변환 함수 적용 (예: memory_to_kb)

2. 입력 파일 (variables.input_files)
   - Job Template의 files.input_schema와 file_key로 매핑
   - 사용자가 업로드한 파일 경로로 치환

3. 입력 종속성 (variables.input_dependencies)
   - auto_detect: 지정된 디렉토리에서 패턴 매칭
   - auto_generate: 규칙 기반 자동 생성

4. 출력 파일 (variables.output_files)
   - 수집할 파일 패턴 명시
   - post_exec에서 자동 수집 코드 생성
```

#### 4.2.2 스크립트 생성 템플릿

```bash
#!/bin/bash

# =============================================================================
# 명령어: ${template.display_name}
# 설명: ${template.description}
# 이미지: ${image.name}
# =============================================================================

# --- 환경 변수 설정 ---
${generateEnvVars(template.variables.dynamic, slurmConfig)}

${generateFileVars(template.variables.input_files, uploadedFiles)}

# --- Pre-commands ---
${template.pre_commands.join('\n')}

# --- Main Command ---
${generateCommand(template.command.format, resolvedVariables)}

# --- Post-commands ---
${template.post_commands.join('\n')}

# --- 결과 파일 수집 ---
${generateOutputCollection(template.variables.output_files, resultDir)}
```

---

## 5. 변환 함수 (Transform Functions)

### 5.1 내장 변환 함수

```typescript
const transformFunctions = {
  // Memory 변환: "16G" -> 16777216 (KB)
  memory_to_kb: (memStr: string): number => {
    const match = memStr.match(/^(\d+)([KMGT])$/i);
    if (!match) return 0;

    const value = parseInt(match[1]);
    const unit = match[2].toUpperCase();

    const multipliers = { K: 1, M: 1024, G: 1024*1024, T: 1024*1024*1024 };
    return value * multipliers[unit];
  },

  // Memory 변환: "16G" -> 16384 (MB)
  memory_to_mb: (memStr: string): number => {
    // ... 유사한 로직
  },

  // Time 변환: "01:30:00" -> 5400 (seconds)
  time_to_seconds: (timeStr: string): number => {
    const parts = timeStr.split(':').map(Number);
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  },

  // 파일 경로 → 파일명 추출
  basename: (path: string): string => {
    return path.split('/').pop() || '';
  },

  // 파일 경로 → 디렉토리 추출
  dirname: (path: string): string => {
    return path.split('/').slice(0, -1).join('/');
  }
};
```

### 5.2 변환 함수 적용 예시

```json
{
  "variables": {
    "dynamic": {
      "MEMORY_KB": {
        "source": "slurm.mem",
        "transform": "memory_to_kb"
      }
    }
  }
}
```

적용:
```typescript
const slurmMem = "16G";  // from job template
const memoryKb = transformFunctions.memory_to_kb(slurmMem);
// memoryKb = 16777216
```

---

## 6. 구현 단계

### Phase 1: 데이터 구조 확장 (Backend)

**파일 수정**:
1. `/apptainer/generate_metadata.py`
   - `command_templates` 필드 생성 로직 추가
   - 수동 정의용 템플릿 파일 지원 (`.commands.json`)

2. `/dashboard/backend_5010/apptainer_service_v2.py`
   - `get_image_commands(image_id)` API 추가
   - 명령어 템플릿 조회 로직

3. 샘플 명령어 템플릿 JSON 생성
   - `lsdyna_R16d.commands.json`
   - `KooSimulationPython313.commands.json`

**테스트**:
```bash
# 명령어 템플릿 포함한 메타데이터 생성
python3 generate_metadata.py lsdyna_R16d.sif compute

# API 테스트
curl http://localhost:5010/api/v2/apptainer/images/{image_id}/commands
```

---

### Phase 2: 프론트엔드 컴포넌트 (UI)

**신규 컴포넌트**:

1. `ImageSelector.tsx`
   - 단일/복수 이미지 선택
   - 명령어 템플릿 미리보기
   - 검색 및 필터링

2. `MultiImageSelector.tsx`
   - 여러 이미지 선택 UI
   - 선택된 이미지 관리

3. `CommandTemplateInserter.tsx`
   - 명령어 템플릿 선택 모달
   - 변수 매핑 UI
   - 스크립트 미리보기

**수정 컴포넌트**:

1. `TemplateEditor.tsx`
   - Apptainer 섹션 UI 개선
   - Script 섹션에 "명령어 템플릿 삽입" 버튼 추가
   - 이미지 선택 상태 관리

2. `ApptainerSelector.tsx`
   - 명령어 템플릿 표시 기능 추가
   - 카드 UI 확장

---

### Phase 3: 스크립트 생성 로직 (Core)

**신규 유틸리티**:

1. `/frontend/src/utils/commandTemplateGenerator.ts`
   ```typescript
   export interface CommandTemplateContext {
     template: CommandTemplate;
     image: ApptainerImage;
     slurmConfig: SlurmConfig;
     inputFiles: Record<string, string>;  // file_key -> file_path
   }

   export function generateScript(context: CommandTemplateContext): string {
     // 1. 동적 변수 해석
     const dynamicVars = resolveDynamicVariables(
       context.template.variables.dynamic,
       context.slurmConfig
     );

     // 2. 파일 변수 해석
     const fileVars = resolveFileVariables(
       context.template.variables.input_files,
       context.inputFiles
     );

     // 3. 명령어 포맷 치환
     const command = substituteVariables(
       context.template.command.format,
       { ...dynamicVars, ...fileVars }
     );

     // 4. 전체 스크립트 조립
     return assembleScript({
       header: generateHeader(context),
       envVars: generateEnvVars({ ...dynamicVars, ...fileVars }),
       preCommands: context.template.pre_commands,
       mainCommand: command,
       postCommands: context.template.post_commands,
       outputCollection: generateOutputCollection(
         context.template.variables.output_files
       )
     });
   }
   ```

2. `/frontend/src/utils/variableResolver.ts`
   - 변수 해석 로직
   - 변환 함수 구현
   - 값 검증

---

### Phase 4: 통합 및 테스트

**통합 테스트 시나리오**:

1. **LS-DYNA 시뮬레이션 + 후처리**
   ```
   Step 1: lsdyna_R16d 이미지 선택
   Step 2: "LS-DYNA MPP Solver" 명령어 템플릿 삽입
   Step 3: K-file 업로드 매핑
   Step 4: 스크립트 생성 확인
   Step 5: Job 제출 및 실행
   ```

2. **복수 이미지 파이프라인**
   ```
   Step 1: lsdyna_R16d + KooSimulationPython313 선택
   Step 2: LS-DYNA Solver → DynaPostProcessor 순차 삽입
   Step 3: 파일 종속성 자동 연결 확인
   Step 4: Job 제출 및 실행
   ```

---

## 7. 샘플 명령어 템플릿 (JSON)

### 7.1 LS-DYNA R16d Commands

**파일**: `/shared/apptainer/metadata/lsdyna_R16d.commands.json`

```json
{
  "image_id": "lsdyna_r16d_abc123",
  "image_name": "lsdyna_R16d.sif",
  "command_templates": [
    {
      "template_id": "lsdyna_mpp_solver",
      "display_name": "LS-DYNA MPP Solver",
      "description": "Run LS-DYNA simulation with MPI parallelization",
      "category": "solver",

      "command": {
        "executable": "ls-dyna_mpp",
        "format": "mpirun -np ${SLURM_NTASKS} ls-dyna_mpp I=${INPUT_FILE} MEMORY=${MEMORY_KB} NCPU=${SLURM_NTASKS}",
        "requires_mpi": true
      },

      "variables": {
        "dynamic": {
          "SLURM_NTASKS": {
            "source": "slurm.ntasks",
            "description": "Number of MPI processes",
            "required": true
          },
          "MEMORY_KB": {
            "source": "slurm.mem",
            "transform": "memory_to_kb",
            "description": "Memory in KB (converted from Slurm mem)",
            "required": true
          }
        },
        "input_files": {
          "INPUT_FILE": {
            "description": "Main K-file input",
            "pattern": "*.k",
            "required": true,
            "file_key": "k_file"
          }
        },
        "output_files": {
          "d3plot": {
            "pattern": "d3plot*",
            "description": "LS-DYNA result files (binary)",
            "collect": true
          },
          "messag": {
            "pattern": "messag*",
            "description": "LS-DYNA message file (log)",
            "collect": true
          }
        }
      },

      "pre_commands": [
        "echo \"======================================\"",
        "echo \"LS-DYNA MPP Solver\"",
        "echo \"======================================\"",
        "echo \"Input K-file: ${INPUT_FILE}\"",
        "echo \"MPI Processes: ${SLURM_NTASKS}\"",
        "echo \"Memory: ${MEMORY_KB} KB\"",
        "echo \"Start time: $(date)\"",
        "echo \"\""
      ],

      "post_commands": [
        "echo \"\"",
        "echo \"======================================\"",
        "echo \"LS-DYNA Simulation Completed\"",
        "echo \"======================================\"",
        "echo \"End time: $(date)\"",
        "echo \"Result files:\"",
        "ls -lh d3plot* messag* 2>/dev/null || echo 'No output files found'"
      ]
    },

    {
      "template_id": "dyna_post_processor_single",
      "display_name": "DynaPostProcessor Single",
      "description": "Post-process LS-DYNA results for a single job",
      "category": "post-processing",

      "command": {
        "executable": "KooDynaPostProcessor",
        "format": "KooDynaPostProcessor Single ${D3PLOT_DIR} ${K_FILE_BASENAME}",
        "requires_mpi": false
      },

      "variables": {
        "dynamic": {},
        "input_files": {
          "D3PLOT_DIR": {
            "description": "Directory containing d3plot files",
            "pattern": "d3plot*",
            "type": "directory",
            "required": true,
            "file_key": "d3plot_directory"
          },
          "K_FILE": {
            "description": "Original K-file",
            "pattern": "*.k",
            "required": true,
            "file_key": "k_file_original"
          }
        },
        "computed": {
          "K_FILE_BASENAME": {
            "source": "K_FILE",
            "transform": "basename",
            "description": "K-file name without path"
          }
        },
        "input_dependencies": {
          "dynain": {
            "pattern": "dynain*",
            "description": "Dynamic restart file (auto-detected)",
            "auto_detect": true,
            "source_dir": "${D3PLOT_DIR}",
            "required": false
          },
          "config_json": {
            "pattern": "${K_FILE_BASENAME}.json",
            "description": "Auto-generated config from K-file",
            "auto_generate": true,
            "generate_rule": "k_file_to_json"
          }
        },
        "output_files": {
          "post_results": {
            "pattern": "post_results_*",
            "description": "Post-processing output",
            "collect": true
          }
        }
      },

      "pre_commands": [
        "echo \"======================================\"",
        "echo \"DynaPostProcessor Single\"",
        "echo \"======================================\"",
        "echo \"D3PLOT Directory: ${D3PLOT_DIR}\"",
        "echo \"K-file: ${K_FILE_BASENAME}\"",
        "echo \"\"",
        "echo \"Checking dependencies...\"",
        "if [ -f \"${D3PLOT_DIR}/dynain\" ]; then",
        "  echo \"  ✓ dynain found\"",
        "else",
        "  echo \"  ⚠ dynain not found (optional)\"",
        "fi",
        "if [ -f \"${K_FILE_BASENAME}.json\" ]; then",
        "  echo \"  ✓ config JSON found\"",
        "else",
        "  echo \"  ⚠ config JSON not found (will auto-generate)\"",
        "fi",
        "echo \"\""
      ],

      "post_commands": [
        "echo \"\"",
        "echo \"======================================\"",
        "echo \"Post-processing Completed\"",
        "echo \"======================================\"",
        "echo \"Output files:\"",
        "ls -lh post_results_* 2>/dev/null || echo 'No output files found'"
      ]
    }
  ]
}
```

---

## 8. 파일 수정 체크리스트

### 8.1 Backend 수정

- [ ] `/apptainer/generate_metadata.py`
  - [ ] `command_templates` 생성 로직 추가
  - [ ] `.commands.json` 파일 로딩 지원
  - [ ] 메타데이터 JSON에 병합

- [ ] `/dashboard/backend_5010/apptainer_service_v2.py`
  - [ ] `get_image_commands(image_id)` API 엔드포인트 추가
  - [ ] 명령어 템플릿 조회 메서드

- [ ] `/cluster/setup/phase8_containers.sh`
  - [ ] `.commands.json` 파일도 함께 배포하도록 수정

### 8.2 Frontend 신규 컴포넌트

- [ ] `/dashboard/frontend_3010/src/components/Apptainer/ImageSelector.tsx`
  - [ ] 단일 이미지 선택 UI
  - [ ] 명령어 템플릿 미리보기

- [ ] `/dashboard/frontend_3010/src/components/Apptainer/MultiImageSelector.tsx`
  - [ ] 복수 이미지 선택 UI
  - [ ] 체크박스 + 목록 관리

- [ ] `/dashboard/frontend_3010/src/components/TemplateManagement/CommandTemplateInserter.tsx`
  - [ ] 명령어 템플릿 선택 모달
  - [ ] 변수 매핑 UI
  - [ ] 스크립트 미리보기

### 8.3 Frontend 수정 컴포넌트

- [ ] `/dashboard/frontend_3010/src/components/TemplateManagement/TemplateEditor.tsx`
  - [ ] Apptainer 섹션 UI 개선 (이미지 선택 모드)
  - [ ] Script 섹션에 "명령어 템플릿 삽입" 버튼
  - [ ] 상태 관리 확장

- [ ] `/dashboard/frontend_3010/src/components/ApptainerSelector.tsx`
  - [ ] 명령어 템플릿 표시 기능 추가
  - [ ] 카드 확장/축소

### 8.4 Frontend 유틸리티

- [ ] `/dashboard/frontend_3010/src/utils/commandTemplateGenerator.ts`
  - [ ] `generateScript()` 함수
  - [ ] 변수 해석 로직
  - [ ] 스크립트 조립 로직

- [ ] `/dashboard/frontend_3010/src/utils/variableResolver.ts`
  - [ ] 동적 변수 해석
  - [ ] 변환 함수 구현
  - [ ] 파일 변수 매핑

- [ ] `/dashboard/frontend_3010/src/utils/transformFunctions.ts`
  - [ ] `memory_to_kb()`
  - [ ] `memory_to_mb()`
  - [ ] `time_to_seconds()`
  - [ ] `basename()`
  - [ ] `dirname()`

### 8.5 타입 정의

- [ ] `/dashboard/frontend_3010/src/types/apptainer.ts`
  - [ ] `CommandTemplate` 인터페이스
  - [ ] `CommandVariable` 인터페이스
  - [ ] `VariableMapping` 인터페이스

---

## 9. 예상 효과

### 9.1 사용자 경험 개선

**Before (현재)**:
```bash
# 사용자가 수동으로 작성
mpirun -np 4 ls-dyna_mpp I=input.k MEMORY=16777216 NCPU=4
```
- 명령어 구조를 외워야 함
- 파라미터 실수 가능
- 파일 경로 수동 입력

**After (개선)**:
1. [이미지 선택: lsdyna_R16d]
2. [명령어 템플릿 선택: LS-DYNA MPP Solver]
3. [파일 매핑: k_file → input.k]
4. [삽입] → 자동 생성된 스크립트 확인

### 9.2 재사용성 향상

- 명령어 템플릿을 한 번 정의하면 모든 Job Template에서 재사용
- Apptainer 이미지와 함께 명령어 사용법 배포
- 일관된 명령어 구조 유지

### 9.3 오류 감소

- 변수 자동 매핑으로 오타 방지
- 필수 파라미터 검증
- 파일 종속성 자동 체크

---

## 10. 추가 고려사항

### 10.1 명령어 템플릿 버전 관리

```json
{
  "template_id": "lsdyna_mpp_solver",
  "version": "1.0.0",
  "compatibility": {
    "min_slurm_version": "21.08",
    "max_cores": 128,
    "min_memory": "1G"
  }
}
```

### 10.2 조건부 명령어

```json
{
  "command": {
    "format": "mpirun -np ${SLURM_NTASKS} ls-dyna_mpp I=${INPUT_FILE} ${MEMORY_FLAG}",
    "conditional_vars": {
      "MEMORY_FLAG": {
        "condition": "MEMORY_KB > 0",
        "true": "MEMORY=${MEMORY_KB}",
        "false": ""
      }
    }
  }
}
```

### 10.3 명령어 체이닝

```json
{
  "template_id": "lsdyna_full_pipeline",
  "display_name": "LS-DYNA Full Pipeline",
  "chain": [
    {
      "step": 1,
      "template_ref": "lsdyna_mpp_solver",
      "wait": true
    },
    {
      "step": 2,
      "template_ref": "dyna_post_processor_single",
      "input_from": "step1.output.d3plot"
    }
  ]
}
```

---

## 11. 구현 우선순위

### 우선순위 1 (필수 - MVP)

1. ✅ Command Template 데이터 구조 정의
2. Backend: 메타데이터 생성 로직 수정
3. Frontend: ImageSelector 컴포넌트 (단일 선택)
4. Frontend: CommandTemplateInserter 기본 버전
5. 스크립트 생성 로직 (동적 변수 + 파일 변수)

### 우선순위 2 (중요)

6. Frontend: MultiImageSelector (복수 선택)
7. 변환 함수 전체 구현
8. 입력 종속성 (auto_detect, auto_generate)
9. 출력 파일 자동 수집

### 우선순위 3 (추가 기능)

10. 조건부 명령어
11. 명령어 체이닝
12. 버전 관리 및 호환성 체크

---

## 12. 결론

이 전략은 Apptainer 이미지에 명령어 템플릿을 저장하고, Job Template 작성 시 이를 활용하여 복잡한 Slurm 스크립트를 자동으로 생성하는 시스템을 구축합니다.

**핵심 장점**:
- 명령어 재사용성 극대화
- 사용자 실수 방지
- 변수 자동 매핑
- 일관된 스크립트 구조

**구현 순서**:
1. Backend 데이터 구조 확장
2. Frontend UI 컴포넌트 개발
3. 스크립트 생성 로직 구현
4. 통합 테스트 및 검증

이 문서를 기반으로 단계별로 구현을 진행하면 효율적이고 사용자 친화적인 시스템을 구축할 수 있습니다.
