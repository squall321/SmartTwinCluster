# Command Template System 구현 상세 설계

**작성일**: 2025-11-10
**목적**: job_template_strategy.md의 Phase 2-4 구현을 위한 상세 설계 및 구현 가이드

---

## 📋 목차

1. [현재 상태 요약](#현재-상태-요약)
2. [아키텍처 개요](#아키텍처-개요)
3. [Phase 2: Frontend UI 컴포넌트](#phase-2-frontend-ui-컴포넌트)
4. [Phase 3: Core Logic](#phase-3-core-logic)
5. [Phase 4: 통합 및 테스트](#phase-4-통합-및-테스트)
6. [구현 순서](#구현-순서)
7. [파일 구조](#파일-구조)

---

## 현재 상태 요약

### ✅ Phase 1 완료 (데이터 구조)

1. **Apptainer 메타데이터**
   - `command_templates` 필드 구현
   - `.commands.json` 파일 지원
   - Partition 연결 구조

2. **Backend API**
   - `GET /api/apptainer/images?partition=compute` - Partition별 이미지 조회
   - `GET /api/apptainer/images/<image_id>/metadata` - 메타데이터 조회
   - `GET /api/v2/templates` - Template 조회

3. **Template 저장소**
   - `/shared/templates/` YAML 기반 시스템
   - Template v2 API 구현

### ❌ Phase 2-4 미구현

- Frontend UI 컴포넌트 전체
- 스크립트 자동 생성 로직
- 파일 스키마 매핑
- 동적 변수 바인딩

---

## 아키텍처 개요

### 핵심 개념

**3단계 다이나믹 연결**:
```
노드 그룹(Partition) → Apptainer 이미지 → Command Templates
        ↓                    ↓                      ↓
    compute              Python.sif          python_simulation_basic
                                            ├─ 입력: *.py (file_key: python_script)
                                            ├─ 출력: results_*
                                            └─ 실행: apptainer exec ... python3 ${FILE}
```

### 데이터 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                        Template Editor                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Basic Info  │  │ Slurm Config │  │  Apptainer   │          │
│  └──────────────┘  └──────────────┘  └──────┬───────┘          │
│                                              │                   │
│                                              ▼                   │
│                                    ┌─────────────────┐          │
│                                    │ ImageSelector   │          │
│                                    │                 │          │
│  Step 1: Partition 선택             │ - Partition: □ │          │
│         ↓                          │ - Images: [ ]  │          │
│  GET /api/apptainer/images?        │ - Command Tpls │          │
│      partition=compute              └─────────────────┘          │
│         ↓                                   │                   │
│  이미지 목록 표시                            │                   │
│                                              │                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────▼───────┐          │
│  │ File Schema  │  │   Scripts    │◄─┤Cmd Template  │          │
│  └──────────────┘  └──────┬───────┘  │   Inserter   │          │
│                           │          └──────────────┘          │
│  Step 2: "명령어 템플릿 삽입" 클릭                               │
│         ↓                │                                      │
│  CommandTemplateInserter 모달 열림                               │
│         ↓                │                                      │
│  Step 3: 템플릿 선택      │                                      │
│         ↓                │                                      │
│  변수 매핑 (자동)        │                                      │
│   - Slurm → 동적 변수    │                                      │
│   - file_key → 파일 변수 │                                      │
│         ↓                │                                      │
│  Step 4: 스크립트 생성    │                                      │
│         ↓                │                                      │
│  generateScript()        │                                      │
│         ↓                │                                      │
│  Step 5: Script 탭에 삽입◄┘                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컴포넌트 관계도

```
TemplateEditor
├── Tab: Apptainer
│   └── ImageSelector
│       ├── PartitionFilter
│       ├── ImageGrid
│       │   └── ImageCard
│       │       ├── ImageInfo
│       │       └── CommandTemplateList (펼치기/접기)
│       └── ImageSearch
│
└── Tab: Scripts
    ├── ScriptEditor (Monaco Editor)
    └── CommandTemplateInserter (Button)
        └── CommandTemplateInserterModal
            ├── TemplateList
            ├── VariableMappingPanel
            │   ├── DynamicVariables (Slurm)
            │   ├── FileVariables (file_key)
            │   └── OutputFiles
            └── ScriptPreview
```

---

## Phase 2: Frontend UI 컴포넌트

[자세한 구현 내용은 원본 문서 참조 - 너무 길어서 요약]

### 2.1 ImageSelector 컴포넌트

**파일**: `dashboard/frontend_3010/src/components/TemplateManagement/ImageSelector.tsx`

**주요 기능**:
- Partition별 Apptainer 이미지 조회
- 이미지 검색 및 필터링
- 이미지 카드 UI (명령어 템플릿 미리보기 포함)
- 단일 이미지 선택

### 2.2 CommandTemplateInserter 모달

**파일**: `dashboard/frontend_3010/src/components/TemplateManagement/CommandTemplateInserter.tsx`

**주요 기능**:
- 명령어 템플릿 목록 표시
- 변수 자동 매핑 (Slurm, 파일)
- 스크립트 미리보기
- Script 탭에 삽입

---

## Phase 3: Core Logic

### 3.1 Command Template Generator

**파일**: `dashboard/frontend_3010/src/utils/commandTemplateGenerator.ts`

**핵심 함수**:
```typescript
export function generateScript(context: CommandTemplateContext): string {
  // 1. 동적 변수 해석 (Slurm → 명령어 파라미터)
  // 2. 파일 변수 해석 (file_key → $FILE_XXX)
  // 3. 명령어 포맷 치환
  // 4. Pre/Post commands 치환
  // 5. 출력 파일 수집 스크립트 생성
  // 6. 전체 스크립트 조립
}
```

### 3.2 Transform Functions

**파일**: `dashboard/frontend_3010/src/utils/transformFunctions.ts`

**제공 함수**:
- `memory_to_kb`: "16G" → 16777216
- `memory_to_mb`: "16G" → 16384
- `time_to_seconds`: "01:30:00" → 5400
- `basename`: "/path/to/file.py" → "file.py"
- `dirname`: "/path/to/file.py" → "/path/to"

### 3.3 Variable Resolver

**파일**: `dashboard/frontend_3010/src/utils/variableResolver.ts`

**핵심 함수**:
```typescript
export function initializeVariableMappings(
  template: CommandTemplate,
  slurmConfig: Record<string, any>,
  fileSchema: Record<string, FileSchemaItem>
): VariableMapping {
  // 1. 동적 변수 자동 매핑
  // 2. 입력 파일 자동 매핑
  // 3. 출력 파일 활성화
}
```

---

## Phase 4: 통합 및 테스트

### 4.1 TemplateEditor 통합

**수정 파일**: `dashboard/frontend_3010/src/components/TemplateManagement/TemplateEditor.tsx`

**변경 사항**:
1. Apptainer 탭에 ImageSelector 추가
2. Scripts 탭에 "명령어 템플릿 삽입" 버튼 추가
3. CommandTemplateInserter 모달 통합

### 4.2 테스트 시나리오

#### 시나리오 1: Python 시뮬레이션 Template
- Partition: compute
- 이미지: KooSimulationPython313.sif
- 명령어 템플릿: Python Simulation (Basic)
- 파일: python_script (*.py)

#### 시나리오 2: LS-DYNA MPP Solver
- Partition: compute
- 이미지: lsdyna_R16d.sif
- 명령어 템플릿: LS-DYNA MPP Solver
- 파일: k_file (*.k)
- 동적 변수: SLURM_NTASKS, MEMORY_KB

---

## 구현 순서

### Week 1: Foundation (핵심 로직)

**Day 1-2: Transform Functions & Variable Resolver**
- [ ] `transformFunctions.ts` 구현
- [ ] `variableResolver.ts` 구현
- [ ] 단위 테스트 작성

**Day 3-4: Command Template Generator**
- [ ] `commandTemplateGenerator.ts` 구현
- [ ] 통합 테스트 작성

**Day 5: Review & Refactor**
- [ ] 코드 리뷰
- [ ] 리팩토링
- [ ] 문서화

### Week 2: UI Components

**Day 1-2: ImageSelector**
- [ ] `ImageSelector.tsx` 구현
- [ ] `ImageCard.tsx` 구현
- [ ] CSS 스타일링
- [ ] API 연동

**Day 3-4: CommandTemplateInserter**
- [ ] `CommandTemplateInserter.tsx` 구현
- [ ] `VariableMappingPanel.tsx` 구현
- [ ] CSS 스타일링

**Day 5: Integration**
- [ ] TemplateEditor에 통합
- [ ] 테스트

### Week 3: Testing & Polish

**Day 1-2: 통합 테스트**
- [ ] 시나리오 1 테스트 (Python)
- [ ] 시나리오 2 테스트 (LS-DYNA)
- [ ] 버그 수정

**Day 3-4: UX 개선**
- [ ] 로딩 상태 처리
- [ ] 에러 처리
- [ ] 검증 메시지
- [ ] 툴팁 추가

**Day 5: Documentation**
- [ ] 사용자 가이드 작성
- [ ] API 문서 업데이트
- [ ] 예제 Template 작성

---

## 파일 구조

```
dashboard/frontend_3010/
├── src/
│   ├── components/
│   │   └── TemplateManagement/
│   │       ├── TemplateEditor.tsx (수정)
│   │       ├── ImageSelector.tsx (신규)
│   │       ├── ImageSelector.css (신규)
│   │       ├── CommandTemplateInserter.tsx (신규)
│   │       ├── CommandTemplateInserter.css (신규)
│   │       └── VariableMappingPanel.tsx (신규)
│   │
│   ├── utils/
│   │   ├── commandTemplateGenerator.ts (신규)
│   │   ├── variableResolver.ts (신규)
│   │   └── transformFunctions.ts (신규)
│   │
│   └── types/
│       └── apptainer.ts (수정 - CommandTemplate 타입 추가)
│
└── tests/
    ├── unit/
    │   ├── transformFunctions.test.ts (신규)
    │   ├── variableResolver.test.ts (신규)
    │   └── commandTemplateGenerator.test.ts (신규)
    │
    └── integration/
        └── templateWorkflow.test.ts (신규)
```

---

## 다음 단계

1. ✅ **COMMAND_TEMPLATE_IMPLEMENTATION_PLAN.md 생성** - 이 문서
2. **COMMAND_TEMPLATE_PROGRESS.md 생성** - 진행 상태 추적 파일
3. **transformFunctions.ts 구현** - 가장 기초적인 유틸리티부터 시작
4. **단위 테스트 작성** - TDD 방식으로 진행
5. **점진적 통합** - 작은 단위로 테스트하며 통합

---

**작성자**: Claude
**최종 수정**: 2025-11-10
