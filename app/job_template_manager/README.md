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

- [x] 프로젝트 초기 설정
- [x] 기본 main.py 작성
- [x] MainWindow 클래스 (QSplitter 구조)
- [ ] TemplateLibraryWidget
- [ ] TemplateEditorWidget
- [ ] FileUploadWidget
- [ ] ScriptGenerator

자세한 개발 계획은 [PROJECT_PLAN.md](PROJECT_PLAN.md)를 참조하세요.

## 라이선스

Internal Use Only
