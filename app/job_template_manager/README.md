# Job Template Manager

PyQt5 기반 HPC Slurm Job Template 생성 및 관리 도구

## 설치 방법

### 1. Python 가상 환경 활성화
```bash
cd app/job_template_manager
source venv/bin/activate
```

### 2. 의존성 패키지 설치
```bash
pip install -r requirements.txt
```

## 실행 방법

### 개발 모드
```bash
python src/main.py
```

## 프로젝트 구조

```
app/job_template_manager/
├── venv/                   # Python 가상 환경
├── src/                    # 소스 코드
│   ├── main.py             # 애플리케이션 진입점
│   ├── ui/                 # UI 컴포넌트
│   │   └── main_window.py  # 메인 윈도우
│   ├── core/               # 비즈니스 로직
│   ├── models/             # 데이터 모델
│   ├── utils/              # 유틸리티
│   └── resources/          # 리소스 파일
├── tests/                  # 테스트 코드
├── requirements.txt        # Python 패키지 목록
├── PROJECT_PLAN.md         # 프로젝트 계획 문서
└── README.md               # 이 파일
```

## 현재 구현 상태

### Phase 1 ✅
- [x] 프로젝트 초기 설정
- [x] 기본 main.py 작성
- [x] MainWindow 클래스 (QSplitter 구조)
- [x] 메뉴바, 상태바

### Phase 2 ✅
- [x] TemplateLibraryWidget (QTreeWidget)
- [x] 템플릿 검색 기능
- [x] 샘플 템플릿 YAML 파일 (3개)
- [x] 컨텍스트 메뉴

### Phase 3 ✅
- [x] Template 데이터 모델
- [x] SlurmConfig, ApptainerConfig 모델
- [x] YAML 로더 (scan_templates, save_template)
- [x] TemplateLibraryWidget에 YAML 로더 통합

### 다음 단계 (Phase 4)
- [ ] TemplateEditorWidget (Slurm Config 폼)
- [ ] FileUploadWidget (Drag & Drop)
- [ ] ScriptGenerator (Bash 스크립트 생성)

자세한 개발 계획은 [PROJECT_PLAN.md](PROJECT_PLAN.md)를 참조하세요.

## 파일 구조

```
app/job_template_manager/
├── src/
│   ├── main.py                    # 애플리케이션 진입점
│   ├── ui/
│   │   ├── main_window.py         # 메인 윈도우
│   │   └── template_library.py    # 템플릿 라이브러리 위젯
│   ├── models/
│   │   └── template.py            # 데이터 모델 (Template, SlurmConfig 등)
│   ├── utils/
│   │   └── yaml_loader.py         # YAML 템플릿 로더
│   └── resources/
│       └── templates/             # 템플릿 YAML 파일
│           ├── ml/                # ML 템플릿
│           ├── simulation/        # Simulation 템플릿
│           └── data/              # Data 템플릿
├── PROJECT_PLAN.md                # 프로젝트 계획 (12 Phase)
├── README.md                      # 이 파일
└── requirements.txt               # Python 의존성
```

## 라이선스

Internal Use Only
