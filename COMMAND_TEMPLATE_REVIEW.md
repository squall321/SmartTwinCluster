# Command Template System 설계 검토 보고서

**검토일**: 2025-11-10
**검토자**: Development Team
**대상**: COMMAND_TEMPLATE_IMPLEMENTATION_PLAN.md

---

## 📋 Executive Summary

전반적으로 **잘 설계**되었으나, 구현 레벨의 세부사항과 일부 현실성 문제 발견.

**종합 평가**:
- 설계 완성도: 7/10
- 구현 가능성: 8/10
- 권장 조치: **즉시 수정 후 진행**

---

## 1. 🔴 Critical Issues (즉시 해결 필요)

### 1.1 타입 정의 누락

**문제**: `CommandTemplate` 인터페이스가 `apptainer.ts`에 정의되지 않음

**영향도**: ⭐⭐⭐⭐⭐ (컴파일 불가)

**현재 상태**:
```typescript
// dashboard/frontend_3010/src/types/apptainer.ts
export interface ApptainerImage {
  id: string;
  name: string;
  // ... 기타 필드
  // command_templates 필드 없음!
}
```

**필요 조치**:
```typescript
// 1. 변수 타입 정의 추가
export interface DynamicVariable {
  source: string;
  transform?: string;
  description: string;
  required: boolean;
}

export interface InputFileVariable {
  description: string;
  pattern: string;
  type?: 'file' | 'directory';
  required: boolean;
  file_key: string;
}

export interface OutputFileVariable {
  pattern: string;
  description: string;
  collect: boolean;
}

// 2. CommandTemplate 인터페이스 추가
export interface CommandTemplate {
  template_id: string;
  display_name: string;
  description: string;
  category: 'solver' | 'pre-processing' | 'post-processing' | 'utility';
  command: {
    executable: string;
    format: string;
    requires_mpi: boolean;
  };
  variables: {
    dynamic: Record<string, DynamicVariable>;
    input_files: Record<string, InputFileVariable>;
    output_files: Record<string, OutputFileVariable>;
  };
  pre_commands: string[];
  post_commands: string[];
}

// 3. ApptainerImage에 필드 추가
export interface ApptainerImage {
  // ... 기존 필드
  command_templates?: CommandTemplate[];  // 추가!
}
```

---

### 1.2 Backend API 엔드포인트 누락

**문제**: 명령어 템플릿 조회 API가 실제로 구현되지 않음

**영향도**: ⭐⭐⭐⭐⭐ (데이터 조회 불가)

**설계 문서 명시**:
```
GET /api/v2/apptainer/images/{image_id}/commands
```

**실제 코드** (`apptainer_api.py`):
```python
# ✓ 있음
@apptainer_bp.route('/api/apptainer/images/<image_id>/metadata')

# ✗ 없음!
# @apptainer_bp.route('/api/apptainer/images/<image_id>/commands')
```

**필요 조치**:
```python
@apptainer_bp.route('/api/apptainer/images/<image_id>/commands', methods=['GET'])
def get_image_commands(image_id: str):
    """
    이미지의 명령어 템플릿 목록 조회

    Response:
        {
            "image_id": "abc123",
            "image_name": "Python.sif",
            "command_templates": [
                {
                    "template_id": "python_sim",
                    "display_name": "Python Simulation",
                    ...
                }
            ]
        }
    """
    try:
        service = get_apptainer_service()
        all_images = service.get_all_images()
        image = next((img for img in all_images if img['id'] == image_id), None)

        if not image:
            return jsonify({'error': 'Image not found'}), 404

        return jsonify({
            'image_id': image['id'],
            'image_name': image['name'],
            'command_templates': image.get('command_templates', [])
        }), 200

    except Exception as e:
        logger.error(f"Failed to get commands: {e}")
        return jsonify({'error': str(e)}), 500
```

---

### 1.3 변수 매핑 불일치 리스크

**문제**: file_key 매칭 로직이 명확하지 않음

**영향도**: ⭐⭐⭐⭐ (런타임 에러 가능)

**시나리오**:
```json
// Apptainer 메타데이터
{
  "variables": {
    "input_files": {
      "SCRIPT_FILE": {
        "file_key": "python_script",  // 소문자
        "pattern": "*.py"
      }
    }
  }
}

// Template Editor - File Schema
{
  "python_script": {  // file_key (소문자)
    "pattern": "*.py",
    "required": true
  }
}

// 런타임 환경 변수
FILE_PYTHON_SCRIPT="/path/to/file.py"  // 대문자 변환
```

**잠재적 문제**:
1. file_key 대소문자 불일치
2. 사용자가 다른 file_key 입력 시 매칭 실패
3. 환경 변수 이름 생성 규칙 불명확

**필요 조치**:
```typescript
// variableResolver.ts
function resolveFileVariables(
  inputFileDefs: Record<string, InputFileVariable>,
  fileSchema: Record<string, FileSchemaItem>
): Record<string, string> {
  const resolved: Record<string, string> = {};

  for (const [varName, fileDef] of Object.entries(inputFileDefs)) {
    const fileKey = fileDef.file_key;

    // file_key 존재 확인 (case-insensitive)
    const matchedKey = Object.keys(fileSchema).find(
      key => key.toLowerCase() === fileKey.toLowerCase()
    );

    if (matchedKey) {
      // 환경 변수 형식: FILE_<UPPERCASE_FILE_KEY>
      const envVarName = `FILE_${matchedKey.toUpperCase()}`;
      resolved[varName] = `$${envVarName}`;
    } else {
      console.warn(`File key "${fileKey}" not found in schema`);
    }
  }

  return resolved;
}
```

---

## 2. 🟡 Important Issues (개선 필요)

### 2.1 메타데이터 병합 로직 확인 필요

**문제**: `.commands.json` 파일이 자동으로 메타데이터에 병합되는지 불명확

**파일 구조**:
```
apptainer/compute-node-images/
├── KooSimulationPython313.sif
├── KooSimulationPython313.json          # 기본 메타데이터
└── KooSimulationPython313.commands.json # 명령어 템플릿
```

**확인 필요**:
- `apptainer_service_v2.py`의 `load_image_metadata()` 함수
- 메타데이터 로딩 시 자동 병합 여부
- API 응답에 command_templates 포함 여부

**검증 방법**:
```bash
# 1. API 호출
curl http://localhost:5010/api/apptainer/images/{image_id}/metadata

# 2. 응답 확인
{
  "id": "...",
  "name": "KooSimulationPython313.sif",
  "command_templates": [...]  # 이 필드가 있어야 함!
}
```

---

### 2.2 TemplateEditor 상태 관리 보완

**문제**: 현재 TemplateEditor가 선택된 이미지 정보를 저장하는 상태 없음

**현재 코드** (`TemplateEditor.tsx`):
```typescript
const [apptainerMode, setApptainerMode] = useState<'fixed' | 'partition' | 'specific' | 'any'>('partition');
const [fixedImageName, setFixedImageName] = useState('');
// selectedImageId, selectedImage 상태 없음!
```

**필요 추가**:
```typescript
const [selectedApptainerImage, setSelectedApptainerImage] = useState<ApptainerImage | null>(null);
const [availableCommandTemplates, setAvailableCommandTemplates] = useState<CommandTemplate[]>([]);

// ImageSelector에서 이미지 선택 시
const handleImageSelect = (image: ApptainerImage) => {
  setSelectedApptainerImage(image);
  setAvailableCommandTemplates(image.command_templates || []);

  // Template 상태 업데이트
  setTemplate({
    ...template,
    apptainerConfig: {
      ...template.apptainerConfig,
      imageId: image.id,
      imageName: image.name,
      imagePath: image.path
    }
  });
};
```

---

### 2.3 Transform Functions 구현 확인

**문제**: 변환 함수 파일이 존재하는지 불명확

**필요 함수**:
```typescript
memory_to_kb("16G")  // → 16777216
memory_to_mb("16G")  // → 16384
time_to_seconds("01:30:00")  // → 5400
basename("/path/to/file.py")  // → "file.py"
dirname("/path/to/file.py")  // → "/path/to"
```

**확인 필요**:
```bash
ls dashboard/frontend_3010/src/utils/transformFunctions.ts
```

**없다면 생성 필요** (Phase 1 Day 1 작업)

---

### 2.4 Computed Variables 처리 로직 불명확

**문제**: `computed` 필드의 실행 시점과 순서가 명확하지 않음

**예시**:
```json
{
  "computed": {
    "K_FILE_BASENAME": {
      "source": "K_FILE",  // input_files.K_FILE 참조
      "transform": "basename"
    }
  }
}
```

**문제점**:
1. 실행 순서: dynamic → input_files → computed?
2. 순환 참조 방지는?
3. computed 결과를 다른 computed가 참조 가능?

**제안**: **Phase 1에서 제외, Phase 2로 이연**
- Phase 1은 dynamic + input_files만
- computed는 나중에 추가

---

### 2.5 Input Dependencies 현실성 부족

**문제**: `auto_detect`, `auto_generate` 구현 방법이 불명확

**예시**:
```json
{
  "input_dependencies": {
    "dynain": {
      "auto_detect": true,
      "source_dir": "${D3PLOT_DIR}"
    },
    "config_json": {
      "auto_generate": true,
      "generate_rule": "k_file_to_json"
    }
  }
}
```

**문제점**:
1. auto_detect는 어디서 실행? (Frontend? Backend? Slurm 스크립트?)
2. generate_rule은 어디에 정의?
3. 생성된 파일은 어디 저장?

**제안**: **Phase 1에서 제외, Phase 2로 이연**
- Phase 1은 pre_commands에서 bash 스크립트로 직접 처리
- Phase 2에서 고급 기능으로 구현

---

## 3. 🟢 Nice to Have (개선 제안)

### 3.1 변수 매핑 실시간 검증

```typescript
const validateMapping = (template: CommandTemplate, fileSchema: Record<string, FileSchemaItem>) => {
  const errors: string[] = [];

  // 필수 파일 체크
  Object.entries(template.variables.input_files).forEach(([varName, varDef]) => {
    if (varDef.required && !fileSchema[varDef.file_key]) {
      errors.push(`Missing required file: ${varDef.file_key}`);
    }
  });

  return errors;
};
```

### 3.2 스크립트 생성 디버그 모드

```typescript
interface ScriptGenerationLog {
  step: string;
  variables: Record<string, any>;
  output: string;
}

// 변수 치환 과정 시각화
```

### 3.3 템플릿 즐겨찾기

```typescript
interface UserPreferences {
  favoriteTemplates: string[];
  recentTemplates: string[];
}
```

---

## 4. ✅ 구현 전 필수 체크리스트

### 4.1 Backend 검증

- [ ] **메타데이터 API 테스트**
  ```bash
  curl http://localhost:5010/api/apptainer/images/{id}/metadata | jq '.command_templates'
  ```
  - command_templates 필드 존재 확인
  - 구조가 설계와 일치하는지 확인

- [ ] **메타데이터 병합 로직 확인**
  ```python
  # apptainer_service_v2.py 확인
  def load_image_metadata(image_path):
      # .commands.json 자동 병합 여부 확인
  ```

- [ ] **File 환경 변수 주입 확인**
  ```python
  # job_service.py 또는 job_submission_service.py 확인
  # FILE_* 환경 변수 생성 로직 확인
  ```

### 4.2 Frontend 검증

- [ ] **Transform functions 파일 확인**
  ```bash
  ls dashboard/frontend_3010/src/utils/transformFunctions.ts
  ```

- [ ] **TemplateEditor 상태 구조 확인**
  ```typescript
  // selectedImage 상태 존재 여부
  // apptainerConfig 저장 방식
  ```

- [ ] **기존 타입 정의 확인**
  ```bash
  cat dashboard/frontend_3010/src/types/apptainer.ts
  ```

---

## 5. 📝 수정된 구현 계획

### Phase 1: Core MVP (단순화)

**목표**: 동작하는 최소 기능 구현

**포함 항목**:
- [x] TypeScript 타입 정의 (CommandTemplate 등)
- [x] Backend API 추가 (/commands 엔드포인트)
- [x] Transform Functions (basic)
- [x] Variable Resolver (dynamic + input_files만)
- [x] Command Template Generator (basic)
- [x] ImageSelector UI
- [x] CommandTemplateInserter UI (simple)

**제외 항목** (Phase 2로 이연):
- [ ] Computed Variables
- [ ] Input Dependencies (auto_detect, auto_generate)
- [ ] 조건부 명령어
- [ ] 명령어 체이닝
- [ ] 변수 검증 (advanced)

### 구현 순서 (수정)

#### Week 1: Foundation

**Day 1 (즉시)**:
1. 타입 정의 완성 (`apptainer.ts`)
2. Backend API 추가 (`apptainer_api.py`)
3. 검증 체크리스트 실행

**Day 2-3**:
4. Transform Functions 구현
5. Variable Resolver (simple) 구현
6. 단위 테스트

**Day 4-5**:
7. Command Template Generator 구현
8. 통합 테스트

#### Week 2: UI

**Day 1-2**:
- ImageSelector 구현
- API 연동

**Day 3-4**:
- CommandTemplateInserter 구현 (simple)
- VariableMappingPanel (dynamic + files만)

**Day 5**:
- TemplateEditor 통합

#### Week 3: Testing & Polish

**Day 1-2**: 통합 테스트
**Day 3-4**: UX 개선
**Day 5**: 문서화

---

## 6. 🎯 최종 권장 사항

### 즉시 조치 항목

1. **타입 정의 추가** (1시간)
   - `apptainer.ts`에 CommandTemplate 인터페이스 추가

2. **Backend API 추가** (2시간)
   - `/commands` 엔드포인트 구현
   - 메타데이터 병합 로직 확인

3. **검증 체크리스트 실행** (1시간)
   - 위 4.1, 4.2 항목 모두 확인

### 구현 접근 방식

**✅ DO**:
- Phase 1을 단순하게 유지
- 기본 기능부터 차근차근
- TDD 방식 (테스트 먼저)
- 점진적 통합

**❌ DON'T**:
- Computed variables 구현 시도 (Phase 2)
- Input dependencies 구현 시도 (Phase 2)
- 완벽주의 (MVP 먼저)

### 예상 일정

- **Phase 1 (Core MVP)**: 2주
- **Phase 2 (Advanced)**: 1-2주
- **Total**: 3-4주

---

## 7. 📊 리스크 평가

| 리스크 | 확률 | 영향도 | 대응 방안 |
|--------|------|--------|----------|
| Backend API 미구현 | 높음 | 높음 | 즉시 확인 및 추가 |
| 타입 불일치 | 중간 | 높음 | 타입 정의 우선 작성 |
| 변수 매핑 실패 | 중간 | 중간 | 철저한 테스트 |
| Computed 구현 복잡도 | 낮음 | 낮음 | Phase 2로 이연 |

---

## 8. 결론

**설계는 전반적으로 우수하나, 일부 현실성 문제와 구현 누락 존재.**

**권장 조치**:
1. ✅ 즉시 조치 항목 3가지 완료
2. ✅ 검증 체크리스트 실행
3. ✅ Phase 1 단순화 적용
4. ✅ 구현 시작

**예상 결과**: 2-3주 내에 **실제로 동작하는 MVP 완성** 가능

---

**검토자**: Claude Development Team
**최종 수정**: 2025-11-10 23:45
**다음 단계**: COMMAND_TEMPLATE_IMPLEMENTATION_PLAN_V2.md 작성
