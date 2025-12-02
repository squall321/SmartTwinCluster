# Apptainer 관리 기능 - 추가된 파일 목록

## 📁 새로 생성된 파일 및 디렉토리

### 1. 디렉토리
```
apptainers/                              # Apptainer 이미지 저장소
```

### 2. Apptainer 디렉토리 내부
```
apptainers/README.md                     # Apptainer 사용 가이드
apptainers/ubuntu_python.def             # 예제 definition 파일
```

### 3. 메인 스크립트
```
sync_apptainers_to_nodes.sh              # Apptainer 동기화 메인 스크립트
setup_apptainer_features.sh              # 기능 설정 및 검증 스크립트
test_apptainer_sync.sh                   # 동기화 테스트 스크립트 (dry-run)
chmod_apptainer_scripts.sh               # 스크립트 권한 설정
```

### 4. 문서
```
APPTAINER_MANAGEMENT_GUIDE.md            # 전체 관리 가이드
APPTAINER_SETUP_COMPLETE.md              # 설치 완료 가이드
APPTAINER_INTEGRATION_SUMMARY.md         # 통합 요약
APPTAINER_FILES_LIST.md                  # 이 파일
```

### 5. 수정된 파일
```
setup_cluster_full.sh                    # Step 13 추가
.gitignore                               # *.sif 패턴 추가
```

## 📊 파일 트리 구조

```
KooSlurmInstallAutomationRefactory/
│
├── apptainers/                          [신규 디렉토리]
│   ├── README.md                        [신규]
│   └── ubuntu_python.def                [신규]
│
├── sync_apptainers_to_nodes.sh          [신규]
├── setup_apptainer_features.sh          [신규]
├── test_apptainer_sync.sh               [신규]
├── chmod_apptainer_scripts.sh           [신규]
│
├── APPTAINER_MANAGEMENT_GUIDE.md        [신규]
├── APPTAINER_SETUP_COMPLETE.md          [신규]
├── APPTAINER_INTEGRATION_SUMMARY.md     [신규]
├── APPTAINER_FILES_LIST.md              [신규]
│
├── setup_cluster_full.sh                [수정됨 - Step 13 추가]
├── .gitignore                           [수정됨 - *.sif 추가]
└── my_cluster.yaml                      [기존 - Apptainer 설정 포함]
```

## 🔧 각 파일의 역할

### 스크립트 파일

| 파일 | 용도 | 필수 여부 |
|------|------|----------|
| `sync_apptainers_to_nodes.sh` | Apptainer 이미지를 계산 노드로 동기화 | ✅ 필수 |
| `setup_apptainer_features.sh` | 환경 설정 및 검증 | ⭐ 권장 |
| `test_apptainer_sync.sh` | 동기화 테스트 (dry-run) | 💡 선택 |
| `chmod_apptainer_scripts.sh` | 스크립트 권한 일괄 설정 | 💡 선택 |

### 문서 파일

| 파일 | 내용 | 대상 독자 |
|------|------|----------|
| `APPTAINER_INTEGRATION_SUMMARY.md` | 전체 기능 요약 및 빠른 시작 | 모든 사용자 |
| `APPTAINER_MANAGEMENT_GUIDE.md` | 상세한 사용 가이드 | 심화 사용자 |
| `APPTAINER_SETUP_COMPLETE.md` | 설치 완료 후 가이드 | 처음 사용자 |
| `apptainers/README.md` | Apptainer 디렉토리 사용법 | Apptainer 사용자 |
| `APPTAINER_FILES_LIST.md` | 추가된 파일 목록 | 개발자/관리자 |

### Definition 파일

| 파일 | 설명 |
|------|------|
| `apptainers/ubuntu_python.def` | Ubuntu 22.04 + Python 과학 라이브러리 예제 |

## 📝 파일 크기 및 복잡도

### 스크립트
- `sync_apptainers_to_nodes.sh`: ~450줄 (메인 로직)
- `setup_apptainer_features.sh`: ~250줄 (검증 및 설정)
- `test_apptainer_sync.sh`: ~50줄 (간단한 래퍼)
- `chmod_apptainer_scripts.sh`: ~40줄 (권한 설정)

### 문서
- `APPTAINER_MANAGEMENT_GUIDE.md`: ~600줄 (전체 가이드)
- `APPTAINER_SETUP_COMPLETE.md`: ~400줄 (설치 가이드)
- `APPTAINER_INTEGRATION_SUMMARY.md`: ~350줄 (요약)
- `apptainers/README.md`: ~200줄 (디렉토리 가이드)

## 🔑 핵심 파일

가장 중요한 파일 3개:

1. **sync_apptainers_to_nodes.sh**
   - 실제 동기화를 수행하는 메인 스크립트
   - YAML 파싱, SSH 연결, rsync 전송 처리

2. **APPTAINER_INTEGRATION_SUMMARY.md**
   - 전체 기능의 시작점
   - 빠른 시작 가이드 포함

3. **setup_cluster_full.sh** (수정됨)
   - Step 13에 Apptainer 동기화 통합
   - 자동 설치 프로세스의 일부

## 💾 Git 관리

### 추적할 파일 (.git add)
```bash
git add apptainers/README.md
git add apptainers/*.def
git add sync_apptainers_to_nodes.sh
git add setup_apptainer_features.sh
git add test_apptainer_sync.sh
git add chmod_apptainer_scripts.sh
git add APPTAINER_*.md
git add .gitignore
git add setup_cluster_full.sh
```

### 제외할 파일 (.gitignore)
```bash
apptainers/*.sif        # 이미지 파일 (용량 큼)
*.sif                   # 모든 SIF 파일
```

## 📦 배포 체크리스트

프로젝트를 배포하거나 복제할 때 확인사항:

- [ ] `apptainers/` 디렉토리 생성됨
- [ ] 모든 `.sh` 파일에 실행 권한 있음 (chmod +x)
- [ ] `my_cluster.yaml`에 노드 정보 정의됨
- [ ] Python3 + pyyaml 설치됨
- [ ] SSH 키 설정됨
- [ ] rsync 설치됨
- [ ] 문서 파일들 모두 존재함

## 🔄 업데이트 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|----------|
| 2025-10-13 | 1.0 | 초기 Apptainer 관리 기능 추가 |

## 🚀 시작하는 방법

```bash
# 1. 권한 설정
chmod +x chmod_apptainer_scripts.sh
./chmod_apptainer_scripts.sh

# 2. 환경 확인
./setup_apptainer_features.sh

# 3. 테스트
./test_apptainer_sync.sh

# 4. 실제 사용
./sync_apptainers_to_nodes.sh
```

## 📞 지원

문제가 발생하면 다음 순서로 확인:

1. `./setup_apptainer_features.sh` 실행하여 환경 검증
2. `APPTAINER_MANAGEMENT_GUIDE.md`의 문제 해결 섹션 참고
3. 로그 파일 확인
4. 이슈 등록

---

**생성일**: 2025-10-13  
**버전**: 1.0  
**프로젝트**: KooSlurmInstallAutomationRefactory
