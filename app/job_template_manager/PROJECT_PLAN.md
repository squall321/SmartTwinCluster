# Job Template Manager - PyQt5 Desktop Application

## 📋 프로젝트 개요

### 목적
HPC 대시보드의 Job Management 기능을 **독립 실행형 PyQt5 데스크톱 앱**으로 재구현하여, 웹 브라우저 없이도 Slurm Job Template을 생성하고 관리할 수 있는 로컬 애플리케이션을 제공합니다.

### 주요 기능
1. **Job Template 생성/편집/삭제** - YAML 기반 템플릿 관리
2. **파일 업로드 및 검증** - Drag & Drop, 파일 스키마 검증
3. **Slurm 스크립트 생성** - 템플릿 + 파일 매핑 → Bash 스크립트
4. **Job 제출 미리보기** - 실제 제출 전 스크립트 검토
5. **Template Library** - 사전 정의된 템플릿 브라우징 및 적용

---

## 🏗️ 아키텍처

### 기존 웹 시스템 분석

#### Frontend (React + TypeScript)
- **Components**: `JobManagement.tsx`, `JobTemplates/index.tsx`, `TemplateEditor.tsx`
- **File Upload**: `FileUploadSection.tsx`, `TemplateFileUpload.tsx`
- **API 통신**: `/api/jobs/templates`, `/api/jobs/submit`
- **State Management**: React Hooks (`useTemplates.ts`)

#### Backend (Flask + Python)
- **API 엔드포인트**:
  - `GET/POST /api/jobs/templates` - 템플릿 CRUD
  - `POST /api/jobs/submit` - Job 제출
  - `POST /api/jobs/preview` - 스크립트 미리보기
- **핵심 모듈**:
  - `templates_api_v2.py` - 템플릿 관리
  - `job_submit_api.py` - Job 제출 로직
  - `template_validator.py` - 템플릿 검증
  - `template_loader.py` - YAML 로딩

#### 데이터 구조
```yaml
# Template YAML 구조 (예시)
template:
  id: pytorch-gpu-training
  name: PyTorch GPU Training
  description: GPU 기반 딥러닝 학습
  category: ml
  version: 1.0.0
  source: official
  tags: [pytorch, gpu, deep-learning]

slurm:
  partition: compute
  nodes: 1
  ntasks: 4
  mem: 32G
  time: 02:00:00

apptainer:
  image_name: KooSimulationPython313.sif
  mode: partition  # partition, specific, any, fixed
  bind:
    - /shared:/shared
    - /data:/data
  env:
    PYTHONPATH: /app
    OMP_NUM_THREADS: "4"

files:
  input_schema:
    required:
      - file_key: training_script
        name: Training Script
        validation:
          extensions: [.py]
          max_size: 10MB
      - file_key: dataset
        name: Dataset File
        validation:
          extensions: [.tar.gz, .zip]
          max_size: 500MB
    optional:
      - file_key: config
        name: Config File
        validation:
          extensions: [.yaml, .json]
          max_size: 1MB

script:
  pre_exec: |
    echo "Starting PyTorch training..."
    export PYTHONUNBUFFERED=1

  main_exec: |
    apptainer exec $APPTAINER_IMAGE \
      python $FILE_TRAINING_SCRIPT \
        --data $FILE_DATASET \
        --output $RESULT_DIR

  post_exec: |
    echo "Training completed"
    ls -lh $RESULT_DIR
```

---

## 🎨 PyQt5 애플리케이션 설계

### UI 구조

```
┌─────────────────────────────────────────────────────────┐
│  Job Template Manager                            [_][□][X] │
├─────────────────────────────────────────────────────────┤
│  ┌─────────┬───────────────────────────────────────────┐ │
│  │ 템플릿   │                                           │ │
│  │ 라이브러리 │     Template Editor / Job Submission     │ │
│  │         │                                           │ │
│  │  🔍 검색  │   ┌─────────────────────────────────┐   │ │
│  │         │   │ Template: PyTorch GPU Training │   │ │
│  │ ML      │   │ Category: ml                   │   │ │
│  │ └ PyTorch│   │ Version: 1.0.0                │   │ │
│  │ └ TensorFlow│ └─────────────────────────────────┘   │ │
│  │         │                                           │ │
│  │ Simulation│  ┌─────────────────────────────────┐   │ │
│  │ └ OpenFOAM│  │ Slurm Configuration             │   │ │
│  │ └ GROMACS │  │ Partition: [compute ▼]         │   │ │
│  │         │   │ Nodes: [1]  CPUs: [4]          │   │ │
│  │ Data    │   │ Memory: [32G]  Time: [02:00:00]│   │ │
│  │ └ Python  │  └─────────────────────────────────┘   │ │
│  │         │                                           │ │
│  │ Custom  │   ┌─────────────────────────────────┐   │ │
│  │ └ (Empty)│   │ File Upload                     │   │ │
│  │         │   │                                 │   │ │
│  │ [+ New] │   │ 📄 training.py (Required)      │   │ │
│  │         │   │    ┌─────────────────────────┐ │   │ │
│  │         │   │    │  Drag & Drop or Browse  │ │   │ │
│  │         │   │    └─────────────────────────┘ │   │ │
│  │         │   │                                 │   │ │
│  │         │   │ 📦 dataset.tar.gz (Required)   │   │ │
│  │         │   │    [Browse...]  ✓ Uploaded     │   │ │
│  │         │   │                                 │   │ │
│  │         │   │ ⚙️ config.yaml (Optional)      │   │ │
│  │         │   │    [Not uploaded]               │   │ │
│  │         │   └─────────────────────────────────┘   │ │
│  │         │                                           │ │
│  │         │   [Preview Script] [Submit Job]          │ │
│  └─────────┴───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 주요 UI 컴포넌트

#### 1. MainWindow (메인 윈도우)
- **QSplitter**: 좌측 템플릿 라이브러리 + 우측 에디터
- **MenuBar**: File, Edit, View, Help
- **StatusBar**: 연결 상태, 작업 진행 상황

#### 2. TemplateLibraryWidget (좌측 패널)
- **QTreeWidget**: 카테고리별 템플릿 트리
- **QLineEdit**: 검색 필터
- **QPushButton**: "New Template" 버튼
- **기능**:
  - 템플릿 카테고리 필터링
  - 템플릿 검색
  - 더블클릭으로 템플릿 로드

#### 3. TemplateEditorWidget (우측 패널)
- **Template Info Section**:
  - `QLineEdit`: Name, Description
  - `QComboBox`: Category
  - `QCheckBox`: Shared

- **Slurm Config Section**:
  - `QComboBox`: Partition
  - `QSpinBox`: Nodes, CPUs
  - `QLineEdit`: Memory, Time
  - 파티션 정책 기반 자동 설정

- **File Upload Section**:
  - `FileUploadWidget` (커스텀): Drag & Drop 지원
  - Required/Optional 파일 목록
  - 파일 검증 상태 표시 (✓ Valid, ✗ Invalid)

- **Script Preview Section**:
  - `QTextEdit` (읽기 전용): 생성된 Bash 스크립트
  - Syntax highlighting (선택사항)

- **Action Buttons**:
  - `QPushButton`: "Preview Script", "Submit Job", "Save Template"

#### 4. FileUploadWidget (파일 업로드)
- **Drag & Drop 영역**: `QFrame` with `dragEnterEvent`, `dropEvent`
- **파일 목록**: `QListWidget`
- **파일 정보 표시**:
  - 파일명, 크기, 상태 (업로드 중, 완료, 오류)
  - Progress bar (업로드 진행 상황)
- **검증 기능**:
  - 확장자 체크
  - 파일 크기 제한
  - 필수/선택 파일 확인

#### 5. ScriptPreviewDialog (스크립트 미리보기)
- **QDialog**: 모달 윈도우
- **QTextEdit**: 생성된 Slurm 스크립트 표시
- **Buttons**: "Copy to Clipboard", "Save as File", "Submit", "Close"

---

## 📦 모듈 구조

```
app/job_template_manager/
├── venv/                          # Python 가상 환경
│
├── src/                           # 소스 코드
│   ├── main.py                    # 애플리케이션 진입점
│   │
│   ├── ui/                        # UI 컴포넌트
│   │   ├── __init__.py
│   │   ├── main_window.py         # MainWindow 클래스
│   │   ├── template_library.py    # TemplateLibraryWidget
│   │   ├── template_editor.py     # TemplateEditorWidget
│   │   ├── file_upload.py         # FileUploadWidget (Drag & Drop)
│   │   ├── script_preview.py      # ScriptPreviewDialog
│   │   └── widgets/               # 재사용 가능한 커스텀 위젯
│   │       ├── slurm_config_form.py
│   │       └── file_item_widget.py
│   │
│   ├── core/                      # 핵심 비즈니스 로직
│   │   ├── __init__.py
│   │   ├── template_manager.py    # 템플릿 CRUD
│   │   ├── template_validator.py  # 템플릿 검증 (backend 코드 이식)
│   │   ├── script_generator.py    # Slurm 스크립트 생성
│   │   ├── file_validator.py      # 파일 검증
│   │   └── api_client.py          # 백엔드 API 통신 (선택사항)
│   │
│   ├── models/                    # 데이터 모델
│   │   ├── __init__.py
│   │   ├── template.py            # Template 클래스
│   │   ├── slurm_config.py        # SlurmConfig 클래스
│   │   ├── file_schema.py         # FileSchema 클래스
│   │   └── uploaded_file.py       # UploadedFile 클래스
│   │
│   ├── utils/                     # 유틸리티
│   │   ├── __init__.py
│   │   ├── yaml_loader.py         # YAML 파일 로드/저장
│   │   ├── file_utils.py          # 파일 크기 파싱, 검증
│   │   └── constants.py           # 상수 정의
│   │
│   └── resources/                 # 리소스 파일
│       ├── icons/                 # 아이콘
│       ├── styles/                # QSS 스타일시트
│       └── templates/             # 사전 정의된 템플릿 YAML
│
├── tests/                         # 테스트 코드
│   ├── test_template_manager.py
│   ├── test_script_generator.py
│   └── test_file_validator.py
│
├── requirements.txt               # Python 패키지 목록
├── setup.py                       # 패키지 설정
├── README.md                      # 사용 가이드
└── PROJECT_PLAN.md               # 이 문서
```

---

## 🔧 기술 스택

### Python 패키지
```txt
# requirements.txt

# UI Framework
PyQt5==5.15.10
PyQt5-stubs==5.15.6.0

# YAML 처리
PyYAML==6.0.1

# HTTP 통신 (백엔드 API 호출용, 선택사항)
requests==2.31.0

# 파일 처리
pathlib2==2.3.7
python-magic==0.4.27  # MIME type 검증

# 유틸리티
python-dateutil==2.8.2

# 개발 도구
black==23.12.1        # 코드 포맷팅
pylint==3.0.3         # 린팅
pytest==7.4.3         # 테스트
pytest-qt==4.2.0      # PyQt 테스트
```

### 개발 환경
- **Python**: 3.12 (기존 venv 버전과 동일)
- **IDE**: VSCode + Python Extension
- **OS**: Linux (Ubuntu 22.04, 기존 환경과 동일)

---

## 🎯 구현 단계

### Phase 1: 프로젝트 초기 설정
**목표**: 개발 환경 구축 및 기본 UI 골격 생성

**작업 항목**:
- [x] 프로젝트 디렉토리 생성 (`app/job_template_manager/`)
- [ ] Python venv 생성 및 활성화
- [ ] `requirements.txt` 작성 및 패키지 설치
- [ ] 기본 `main.py` 작성 (빈 윈도우)
- [ ] `MainWindow` 클래스 구현 (QSplitter 구조)
- [ ] 기본 메뉴바 및 상태바 추가

**검증**:
```bash
cd app/job_template_manager
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python src/main.py  # 빈 윈도우 실행
```

---

### Phase 2: 템플릿 라이브러리 UI
**목표**: 좌측 템플릿 브라우저 구현

**작업 항목**:
- [ ] `TemplateLibraryWidget` 클래스 구현
- [ ] `QTreeWidget`으로 카테고리별 템플릿 표시
- [ ] 템플릿 검색 기능 (`QLineEdit` + 필터링)
- [ ] 템플릿 더블클릭 → 우측 에디터 로드
- [ ] 사전 정의된 템플릿 YAML 파일 추가 (`resources/templates/`)

**템플릿 카테고리**:
- **ML**: PyTorch, TensorFlow, Scikit-learn
- **Simulation**: OpenFOAM, GROMACS, LS-DYNA
- **Data**: Python Data Processing, Jupyter Notebook
- **Custom**: 사용자 정의 템플릿

**검증**:
- 템플릿 트리에서 10개 이상의 템플릿 표시
- 검색으로 "pytorch" 입력 시 PyTorch 템플릿만 필터링

---

### Phase 3: 데이터 모델 및 YAML 로더
**목표**: 백엔드 코드 이식 및 데이터 구조 정의

**작업 항목**:
- [ ] `Template` 클래스 구현 (`models/template.py`)
  - `id`, `name`, `description`, `category`, `version`, `source`, `tags`
  - `slurm`, `apptainer`, `files`, `script` 속성
- [ ] `SlurmConfig` 클래스 (`models/slurm_config.py`)
  - `partition`, `nodes`, `ntasks`, `mem`, `time`
- [ ] `FileSchema` 클래스 (`models/file_schema.py`)
  - `required`, `optional` 파일 목록
  - 파일 검증 규칙 (확장자, 크기)
- [ ] `TemplateValidator` 구현 (`core/template_validator.py`)
  - 백엔드 `template_validator.py` 코드 이식
  - YAML 스키마 검증
- [ ] `YAMLLoader` 구현 (`utils/yaml_loader.py`)
  - 템플릿 로드/저장
  - 백엔드 `template_loader.py` 로직 이식

**검증**:
```python
# 테스트 코드 예시
from src.utils.yaml_loader import YAMLLoader

loader = YAMLLoader('resources/templates')
template = loader.load_template('pytorch-gpu-training')
assert template.name == 'PyTorch GPU Training'
assert template.slurm.partition == 'compute'
```

---

### Phase 4: 템플릿 에디터 UI
**목표**: 우측 템플릿 편집 UI 구현

**작업 항목**:
- [ ] `TemplateEditorWidget` 클래스 구현
- [ ] **Template Info Section**:
  - Name, Description 입력 (`QLineEdit`, `QTextEdit`)
  - Category 선택 (`QComboBox`)
  - Shared 체크박스 (`QCheckBox`)
- [ ] **Slurm Config Section**:
  - Partition 선택 (`QComboBox`)
  - Nodes, CPUs 입력 (`QSpinBox`)
  - Memory, Time 입력 (`QLineEdit`)
  - 파티션 정책 기반 자동 설정 (백엔드 로직 이식)
- [ ] **Script Preview Section**:
  - 읽기 전용 `QTextEdit`
  - 실시간 스크립트 업데이트 (설정 변경 시)
- [ ] 템플릿 로드 시 폼 자동 채우기

**검증**:
- 템플릿 라이브러리에서 템플릿 선택 → 에디터에 정보 표시
- Partition 변경 시 Nodes/CPUs 제한 자동 적용

---

### Phase 5: 파일 업로드 UI
**목표**: Drag & Drop 파일 업로드 구현

**작업 항목**:
- [ ] `FileUploadWidget` 클래스 구현 (`ui/file_upload.py`)
- [ ] Drag & Drop 이벤트 처리:
  - `dragEnterEvent`: 파일 드래그 시 하이라이트
  - `dropEvent`: 파일 드롭 시 업로드
- [ ] 파일 브라우저 (`QFileDialog`)
- [ ] 파일 목록 표시 (`QListWidget`)
  - 파일명, 크기, 상태 아이콘 (✓, ✗, ⏳)
- [ ] 파일 검증 (`FileValidator`)
  - 확장자 체크
  - 파일 크기 제한
  - 필수/선택 파일 확인
- [ ] 파일 삭제 버튼

**검증**:
- STL 파일 드래그 앤 드롭 → 파일 목록에 추가
- 허용되지 않은 확장자 업로드 시 오류 메시지
- 필수 파일 누락 시 Submit 버튼 비활성화

---

### Phase 6: Slurm 스크립트 생성
**목표**: 백엔드 스크립트 생성 로직 이식

**작업 항목**:
- [ ] `ScriptGenerator` 클래스 구현 (`core/script_generator.py`)
- [ ] 백엔드 `generate_slurm_script()` 함수 이식
- [ ] 환경 변수 생성:
  - Slurm 설정 변수 (`JOB_PARTITION`, `JOB_NODES`, ...)
  - Apptainer 이미지 경로 (`APPTAINER_IMAGE`)
  - 업로드된 파일 경로 (`FILE_TRAINING_SCRIPT`, `FILE_DATASET`, ...)
- [ ] Template 스크립트 블록 삽입:
  - `pre_exec`, `main_exec`, `post_exec`
- [ ] 파일 복사 스크립트 추가
- [ ] 실시간 스크립트 업데이트 (설정 변경 시)

**검증**:
```python
# 테스트 코드 예시
from src.core.script_generator import ScriptGenerator

generator = ScriptGenerator()
script = generator.generate(
    template=template,
    uploaded_files={'training_script': '/tmp/train.py'},
    slurm_overrides={'mem': '64G'}
)
assert '#SBATCH --mem=64G' in script
assert 'FILE_TRAINING_SCRIPT="/shared/jobs/$SLURM_JOB_ID/input/train.py"' in script
```

---

### Phase 7: 스크립트 미리보기 및 제출
**목표**: Job 제출 전 스크립트 검토 기능

**작업 항목**:
- [ ] `ScriptPreviewDialog` 클래스 구현 (`ui/script_preview.py`)
- [ ] 생성된 스크립트 표시 (읽기 전용 `QTextEdit`)
- [ ] Syntax highlighting (Bash, 선택사항)
- [ ] "Copy to Clipboard" 버튼 (`QClipboard`)
- [ ] "Save as File" 버튼 (`QFileDialog`)
- [ ] "Submit" 버튼:
  - 스크립트 파일 저장 (`/tmp/slurm_scripts/`)
  - `sbatch` 명령 실행 (subprocess)
  - Job ID 추출 및 표시
- [ ] Job 제출 결과 다이얼로그

**검증**:
- "Preview Script" 클릭 → 다이얼로그 표시
- "Copy to Clipboard" → 클립보드에 스크립트 복사
- "Submit" → `sbatch` 실행 및 Job ID 반환

---

### Phase 8: 템플릿 저장 및 관리
**목표**: 사용자 정의 템플릿 생성/수정/삭제

**작업 항목**:
- [ ] `TemplateManager` 클래스 구현 (`core/template_manager.py`)
- [ ] 템플릿 저장:
  - YAML 파일로 저장 (`/shared/templates/user/{username}/`)
  - SQLite DB에 메타데이터 저장 (선택사항)
- [ ] 템플릿 수정:
  - 기존 YAML 파일 업데이트
- [ ] 템플릿 삭제:
  - 아카이브로 이동 (`/shared/templates/archived/`)
- [ ] 템플릿 내보내기 (Export):
  - YAML 파일 다운로드
- [ ] 템플릿 가져오기 (Import):
  - YAML 파일 업로드 및 검증

**검증**:
- 새 템플릿 작성 → "Save Template" → YAML 파일 생성
- 템플릿 수정 → 기존 파일 업데이트
- 템플릿 삭제 → `archived/` 폴더로 이동

---

### Phase 9: API 통신 (선택사항)
**목표**: 백엔드 API와 연동하여 클라우드 템플릿 동기화

**작업 항목**:
- [ ] `APIClient` 클래스 구현 (`core/api_client.py`)
- [ ] 백엔드 API 엔드포인트:
  - `GET /api/jobs/templates` - 템플릿 목록
  - `GET /api/jobs/templates/{id}` - 템플릿 상세
  - `POST /api/jobs/templates` - 템플릿 생성
  - `PUT /api/jobs/templates/{id}` - 템플릿 수정
  - `DELETE /api/jobs/templates/{id}` - 템플릿 삭제
  - `POST /api/jobs/submit` - Job 제출
- [ ] 인증 (JWT 토큰) 처리
- [ ] 오프라인 모드 지원 (로컬 캐시)

**검증**:
- API 서버 연결 시 클라우드 템플릿 동기화
- 오프라인 시 로컬 YAML 파일만 사용

---

### Phase 10: 스타일링 및 UX 개선
**목표**: 현대적인 UI 디자인 및 사용성 향상

**작업 항목**:
- [ ] QSS 스타일시트 작성 (`resources/styles/`)
  - 다크 모드 / 라이트 모드
  - 아이콘 색상 테마
- [ ] 아이콘 추가 (`resources/icons/`)
  - 템플릿 카테고리 아이콘
  - 파일 타입 아이콘
  - 액션 버튼 아이콘
- [ ] 키보드 단축키:
  - `Ctrl+N`: New Template
  - `Ctrl+S`: Save Template
  - `Ctrl+P`: Preview Script
  - `Ctrl+Enter`: Submit Job
- [ ] 에러 메시지 개선 (`QMessageBox`)
- [ ] 진행 상황 표시 (`QProgressBar`, `QProgressDialog`)

**검증**:
- 스타일 적용 → 대시보드와 유사한 디자인
- 단축키 동작 확인

---

### Phase 11: 테스트 및 디버깅
**목표**: 안정성 및 품질 보증

**작업 항목**:
- [ ] 단위 테스트 작성 (`tests/`)
  - `test_template_manager.py`
  - `test_script_generator.py`
  - `test_file_validator.py`
- [ ] UI 테스트 (`pytest-qt`)
  - 템플릿 로드 시나리오
  - 파일 업로드 시나리오
  - Job 제출 시나리오
- [ ] 에러 처리:
  - 파일 읽기/쓰기 실패
  - 네트워크 오류 (API 통신)
  - YAML 파싱 오류
- [ ] 메모리 누수 검사
- [ ] 크로스 플랫폼 테스트 (Linux, Windows, macOS)

**검증**:
```bash
pytest tests/
```

---

### Phase 12: 배포 및 문서화
**목표**: 사용자 배포 및 가이드 작성

**작업 항목**:
- [ ] PyInstaller로 실행 파일 생성:
  ```bash
  pyinstaller --onefile --windowed src/main.py
  ```
- [ ] 설치 스크립트 작성 (`install.sh`)
- [ ] 사용자 가이드 작성 (`README.md`)
  - 설치 방법
  - 기본 사용법
  - 템플릿 생성 튜토리얼
- [ ] 개발자 문서 작성
  - 아키텍처 다이어그램
  - API 레퍼런스

**검증**:
- 실행 파일로 앱 실행
- 사용자 가이드 따라하기 성공

---

## 📊 기능 매핑표

| 웹 기능 (React) | PyQt5 구현 | 우선순위 |
|---------------|-----------|---------|
| **JobManagement.tsx** | `MainWindow` | High |
| **JobTemplates/index.tsx** | `TemplateLibraryWidget` | High |
| **TemplateEditor.tsx** | `TemplateEditorWidget` | High |
| **FileUploadSection.tsx** | `FileUploadWidget` | High |
| **TemplateFileUpload.tsx** | `FileUploadWidget` | High |
| **useTemplates.ts** | `TemplateManager` | High |
| **templates_api_v2.py** | `YAMLLoader` + `APIClient` | Medium |
| **job_submit_api.py** | `ScriptGenerator` | High |
| **template_validator.py** | `TemplateValidator` | High |
| **scriptUtils.ts** | `ScriptGenerator` | High |

---

## 🔑 핵심 차이점 및 고려사항

### 웹 vs 데스크톱

| 항목 | 웹 (React) | 데스크톱 (PyQt5) |
|-----|-----------|----------------|
| **파일 업로드** | XHR + multipart/form-data | 로컬 파일 시스템 직접 접근 |
| **상태 관리** | React Hooks (useState, useEffect) | Qt Signals/Slots |
| **API 통신** | Axios/Fetch | Requests (선택사항) |
| **스타일** | CSS/Tailwind | QSS (Qt Style Sheets) |
| **인증** | JWT Token in LocalStorage | Keyring 또는 설정 파일 |
| **오프라인 모드** | ServiceWorker (PWA) | 네이티브 오프라인 지원 |

### 구현 시 주의사항

1. **파일 경로**:
   - 웹: `/data/results/{jobId}/{filename}`
   - 데스크톱: 로컬 파일 시스템 경로 사용

2. **API 통신**:
   - 백엔드 API 호출은 선택사항
   - 로컬 YAML 파일만으로도 동작 가능

3. **Apptainer 이미지**:
   - 이미지 목록은 로컬 디렉토리 스캔 (`/opt/apptainers/`)
   - 또는 API에서 가져오기

4. **Job 제출**:
   - `subprocess`로 `sbatch` 명령 실행
   - SSH를 통해 원격 헤드노드에 제출 (선택사항)

5. **보안**:
   - 사용자 인증 (JWT) 구현 필요 시 Keyring 사용
   - YAML 파일 권한 관리

---

## 🚀 실행 예시

### 개발 모드
```bash
cd app/job_template_manager
source venv/bin/activate
python src/main.py
```

### 프로덕션 모드 (실행 파일)
```bash
./dist/job_template_manager
```

---

## 📝 다음 단계

1. **Phase 1 완료 후 검토**:
   - 기본 윈도우 실행 확인
   - UI 레이아웃 검토

2. **백엔드 코드 이식**:
   - `template_validator.py` → `src/core/template_validator.py`
   - `generate_slurm_script()` → `src/core/script_generator.py`

3. **템플릿 YAML 파일 준비**:
   - 기존 `/shared/templates/` 복사
   - `resources/templates/`에 사전 정의된 템플릿 추가

4. **UI 프로토타입 테스트**:
   - 템플릿 로드 → 에디터 표시
   - 파일 업로드 → 스크립트 생성
   - 스크립트 미리보기 → Job 제출

---

## 🎯 성공 기준

- [ ] 웹 대시보드의 Job Template 기능을 100% 재현
- [ ] 독립 실행형 앱으로 웹 브라우저 없이 사용 가능
- [ ] Drag & Drop 파일 업로드 동작
- [ ] 실시간 Slurm 스크립트 미리보기
- [ ] 로컬 YAML 파일 기반 템플릿 관리
- [ ] `sbatch` 명령으로 Job 제출 성공
- [ ] 사용자 가이드 문서 완성

---

## 📚 참고 자료

- **Frontend 코드**:
  - `dashboard/frontend_3010/src/components/JobManagement.tsx`
  - `dashboard/frontend_3010/src/components/JobTemplates/`
  - `dashboard/frontend_3010/src/hooks/useTemplates.ts`

- **Backend 코드**:
  - `dashboard/backend_5010/templates_api_v2.py`
  - `dashboard/backend_5010/job_submit_api.py`
  - `dashboard/backend_5010/template_validator.py`
  - `dashboard/backend_5010/template_service.py`

- **PyQt5 문서**:
  - https://doc.qt.io/qtforpython-5/
  - https://www.riverbankcomputing.com/static/Docs/PyQt5/

---

**작성일**: 2025-12-21
**작성자**: Claude Sonnet 4.5
**버전**: 1.0.0
