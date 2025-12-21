# Job Template Manager

PyQt5 기반 HPC Slurm Job Template 생성 및 관리 도구

## 설치 방법

### 1. Python 가상 환경 생성 (처음 한 번만)
```bash
cd app/job_template_manager

# --system-site-packages 플래그로 시스템 PyQt5 사용
python3 -m venv venv --system-site-packages
```

**중요**: `--system-site-packages` 플래그는 시스템에 설치된 PyQt5를 venv에서 사용할 수 있게 합니다. 이는 Qt 라이브러리 버전 호환성 문제를 해결합니다.

### 2. 가상 환경 활성화
```bash
source venv/bin/activate
```

### 3. 의존성 패키지 설치
```bash
pip install -r requirements.txt
```

## 실행 방법

### 방법 1: run.sh 스크립트 사용 (권장)
```bash
./run.sh
```

### 방법 2: 수동 실행
```bash
source venv/bin/activate
python src/main.py
```

### 방법 3: 시스템 Python 사용
```bash
python3 src/main.py
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

### Phase 4 ✅
- [x] TemplateEditorWidget (우측 패널)
- [x] Slurm Config 편집 폼 (Partition, Nodes, Tasks, Memory, Time, GPUs)
- [x] 파일 스키마 테이블 표시
- [x] 스크립트 미리보기 (pre_exec, main_exec, post_exec)
- [x] Preview/Submit 버튼 연결

### Phase 5 ✅
- [x] FileUploadWidget (Drag & Drop 지원)
- [x] 파일 브라우저 (QFileDialog)
- [x] 파일 검증 (확장자, 크기)
- [x] 파일 목록 표시 (상태 표시: ✓ 유효, ✗ 검증 실패)
- [x] 파일 환경 변수 생성 (FILE_XXX)
- [x] TemplateEditorWidget에 통합

### Phase 6 ✅
- [x] ScriptGenerator (Slurm 배치 스크립트 생성)
- [x] SBATCH 헤더 생성 (job-name, partition, nodes, ntasks, mem, time, gpus)
- [x] 환경 변수 생성 (JOB_*, APPTAINER_IMAGE, FILE_*, RESULT_DIR)
- [x] 디렉토리 설정 (/shared/jobs/$SLURM_JOB_ID/input, work, output, results)
- [x] 파일 복사 명령 생성
- [x] Template 스크립트 블록 조합 (pre_exec, main_exec, post_exec)
- [x] Job 메타데이터 생성
- [x] 스크립트 파일 저장 (실행 권한 755)

### Phase 7 ✅ - **MVP 완성!**
- [x] ScriptPreviewDialog (생성된 스크립트 미리보기)
  - [x] 스크립트 편집 가능
  - [x] 클립보드 복사
  - [x] 파일로 저장
- [x] JobSubmitter (Job 제출 엔진)
  - [x] sbatch 명령 실행
  - [x] Job ID 자동 추출
  - [x] Slurm 가용성 체크
  - [x] 에러 처리 및 사용자 피드백
- [x] Preview 및 Submit 버튼 연결
  - [x] 필수 파일 체크
  - [x] 스크립트 생성
  - [x] 미리보기 다이얼로그 표시
  - [x] Job 제출 및 결과 표시

### Phase 8 ✅ - **템플릿 관리 완성!**
- [x] TemplateCreatorDialog (템플릿 생성/편집 다이얼로그)
  - [x] 6개 탭 UI (Basic Info, Slurm, Apptainer, Files, Script)
  - [x] 템플릿 생성 모드
  - [x] 템플릿 편집 모드
  - [x] 실시간 검증
- [x] TemplateManager (템플릿 관리자)
  - [x] 템플릿 저장 (YAML 파일)
  - [x] 템플릿 업데이트
  - [x] 템플릿 삭제 (아카이브)
  - [x] 템플릿 복제
  - [x] 템플릿 내보내기
  - [x] 템플릿 가져오기
  - [x] 템플릿 검증
- [x] 메인 윈도우 통합
  - [x] 메뉴바 (New, Edit, Duplicate, Delete, Import, Export)
  - [x] 키보드 단축키 (Ctrl+N, Ctrl+E, Ctrl+D, etc.)
  - [x] 템플릿 라이브러리 컨텍스트 메뉴
  - [x] 템플릿 새로고침 (F5)

## 🎉 완전한 기능의 앱 완성!

**핵심 기능 (MVP - Phase 1-7)**:
1. ✅ 템플릿 라이브러리 (검색, 카테고리별 분류)
2. ✅ 템플릿 상세 보기 (Slurm Config, Apptainer, 파일 스키마)
3. ✅ Slurm 설정 편집
4. ✅ 파일 업로드 (Drag & Drop, 검증)
5. ✅ Slurm 스크립트 자동 생성
6. ✅ 스크립트 미리보기 및 편집
7. ✅ Slurm Job 제출 및 Job ID 추출

**템플릿 관리 기능 (Phase 8)** - ⭐ NEW!
8. ✅ 템플릿 생성/편집/삭제
9. ✅ 템플릿 복제
10. ✅ 템플릿 내보내기/가져오기 (YAML)
11. ✅ 템플릿 검증
12. ✅ 컨텍스트 메뉴 및 키보드 단축키

**다음 단계 (Phase 9-12)** - 선택적 편의 기능:
- [ ] API 통합 (백엔드 연동)
- [ ] Job 모니터링 (squeue 통합)
- [ ] 스타일링 및 UX 개선 (다크 모드, 아이콘)
- [ ] 추가 테스팅 및 배포

자세한 개발 계획은 [PROJECT_PLAN.md](PROJECT_PLAN.md)를 참조하세요.

## 파일 구조

```
app/job_template_manager/
├── src/
│   ├── main.py                    # 애플리케이션 진입점
│   ├── ui/
│   │   ├── main_window.py         # 메인 윈도우
│   │   ├── template_library.py    # 템플릿 라이브러리 위젯
│   │   ├── template_editor.py     # 템플릿 에디터 위젯
│   │   ├── file_upload.py         # 파일 업로드 위젯 (Drag & Drop)
│   │   └── script_preview_dialog.py  # 스크립트 미리보기 다이얼로그
│   ├── models/
│   │   └── template.py            # 데이터 모델 (Template, SlurmConfig 등)
│   ├── utils/
│   │   ├── yaml_loader.py         # YAML 템플릿 로더
│   │   ├── script_generator.py    # Slurm 스크립트 생성기
│   │   └── job_submitter.py       # Job 제출 엔진 (sbatch 실행)
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
