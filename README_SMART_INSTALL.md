# 스마트 오프라인 설치 시스템

## 🎯 핵심 기능

✅ **설치 전 전체 점검**: Critical 패키지 감지 → 문제 있으면 즉시 중단  
✅ **이미 설치된 패키지 건너뛰기**: 버전 관계없이 무조건 Skip (안전)  
✅ **상세한 리포트 생성**: 어떤 패키지를 왜 건너뛰는지 명확히 표시  
✅ **Critical 패키지 보호**: systemd, libc6 등 절대 건드리지 않음  

---

## 📁 새로 생성된 파일들

```
KooSlurmInstallAutomationRefactory/
├── offline_packages/
│   └── precheck_packages.py              [NEW] 사전 점검 도구
│
├── install_offline_packages_smart.sh      [NEW] 스마트 APT 설치
├── setup_cluster_full_multihead_offline_smart.sh  [NEW] 메인 스크립트
└── SMART_OFFLINE_INSTALLATION.md          [NEW] 사용 가이드
```

---

## 🚀 사용법

### 1. 사전 점검만 실행

```bash
python3 offline_packages/precheck_packages.py \
    --deb-dir offline_packages/apt_packages \
    --requirements dashboard/backend_5010/requirements.txt \
    --requirements dashboard/kooCAEWebServer_5000/requirements.txt
```

**출력 파일**:
- `precheck_report.txt` - 전체 점검 리포트
- `apt_skip_list.txt` - 건너뛸 APT 패키지 목록  
- `python_skip_list.txt` - 건너뛸 Python 패키지 목록

**종료 코드**:
- `0` = Critical 이슈 없음 → 설치 가능
- `1` = Critical 이슈 발견 → 설치 불가

---

### 2. 스마트 오프라인 설치 (원스텝)

```bash
sudo ./setup_cluster_full_multihead_offline_smart.sh
```

**실행 흐름**:
```
Phase 0: 사전 점검
  ├─ precheck_packages.py 실행
  ├─ Critical 이슈 검사
  └─ Skip 리스트 생성
       ↓
Phase 1: 스마트 APT 설치
  ├─ apt_skip_list.txt 로드
  ├─ 각 .deb 파일 점검
  ├─ Critical/Skip/설치완료 → SKIP
  └─ 나머지만 설치
       ↓
Phase 2: 멀티헤드 클러스터 구성
  └─ (기존 로직)
```

---

## 📊 설치 전 점검 리포트 예제

```
================================================================================
   오프라인 패키지 설치 전 점검 리포트
================================================================================

검사 일시: 2025-12-04 15:30:00
호스트명: controller1

📊 통계
--------------------------------------------------------------------------------
시스템에 설치된 APT 패키지: 1245
오프라인 .deb 패키지: 523
Python requirements: 28

⚠️  발견된 이슈
--------------------------------------------------------------------------------
🔴 Critical: 3    ← 즉시 조치 필요
🟡 Warning: 12   ← 검토 권장  
🔵 Info: 145     ← 건너뛸 패키지

🔴 CRITICAL 이슈 (즉시 조치 필요)
================================================================================

[1] systemd
    설치된 버전: 249.11-0ubuntu3.17
    새 버전: 249.11-0ubuntu3.15
    이유: Critical system package - NEVER update
    조치: SKIP: Remove systemd_*.deb from offline package directory

[2] libc6
    설치된 버전: 2.35-0ubuntu3.11
    새 버전: 2.35-0ubuntu3.8
    이유: Critical system package - NEVER update
    조치: SKIP: Remove libc6_*.deb from offline package directory

✅ 다음 단계
================================================================================
🔴 CRITICAL 이슈 해결이 필요합니다:

1. 다음 패키지들을 오프라인 패키지 디렉토리에서 제거하세요:

   rm -f apt_packages/systemd_*.deb
   rm -f apt_packages/libc6_*.deb

2. 제거 후 이 스크립트를 다시 실행하세요.
3. CRITICAL 이슈가 없으면 설치를 진행할 수 있습니다.
```

---

## ⚠️ Critical 패키지 목록

**절대 업데이트하지 않는 패키지들**:

```
systemd          - Init 시스템
init             - Init
libc6            - C 라이브러리
libc-bin         - C 라이브러리 바이너리
base-files       - 기본 시스템 파일
base-passwd      - 기본 사용자/그룹
dpkg             - 패키지 관리자
apt              - APT
coreutils        - 기본 유틸리티
bash             - 셸
dash             - 셸
util-linux       - 시스템 유틸리티
libsystemd0      - Systemd 라이브러리
udev             - 디바이스 관리자
mount            - 마운트 유틸리티
login            - 로그인 유틸리티
```

→ 이 패키지들을 업데이트하면 **시스템이 부팅되지 않을 수 있습니다**.

---

## 🔧 옵션

### precheck_packages.py 옵션

```bash
--deb-dir DIR              .deb 파일 디렉토리 (필수)
--requirements FILE        requirements.txt (여러 개 가능)
--output-report FILE       리포트 파일명
--skip-installed           이미 설치된 패키지 Skip (기본: ON)
--critical-only            Critical 이슈만 보고
--json                     JSON 형식 출력
```

### install_offline_packages_smart.sh 옵션

```bash
--deb-dir DIR              .deb 파일 디렉토리
--skip-installed           이미 설치된 패키지 Skip
--skip-list FILE           Skip 리스트 파일
--dry-run                  계획만 표시
--force                    경고 무시
```

### setup_cluster_full_multihead_offline_smart.sh 옵션

```bash
--skip-installed           이미 설치된 패키지 Skip (기본: ON)
--no-skip-installed        이미 설치된 패키지도 설치 시도
--skip-precheck            사전 점검 건너뛰기 (권장 안함)
--dry-run                  계획만 표시
--install-apt              APT 패키지 설치 활성화
```

---

## 🛠️ 문제 해결

### Q: Critical 이슈가 계속 나옵니다

```bash
# 1. 리포트 확인
cat precheck_report.txt

# 2. 해당 패키지 제거
cd offline_packages/apt_packages
rm -f systemd_*.deb libc6_*.deb

# 3. 다시 점검
python3 ../../offline_packages/precheck_packages.py --deb-dir .
```

### Q: Skip 리스트를 수동으로 편집하고 싶습니다

```bash
# apt_skip_list.txt 직접 편집
vi apt_skip_list.txt

# 패키지 이름을 한 줄에 하나씩
nginx-core
python3-minimal

# 저장 후 설치
sudo bash install_offline_packages_smart.sh \
    --deb-dir offline_packages/apt_packages \
    --skip-list apt_skip_list.txt
```

### Q: 사전 점검 없이 빠르게 설치하고 싶습니다 (위험)

```bash
sudo ./setup_cluster_full_multihead_offline_smart.sh --skip-precheck
```

---

## 📈 비교

| 항목 | 기존 오프라인 설치 | 스마트 오프라인 설치 |
|------|-------------------|-------------------|
| 사전 점검 | ❌ | ✅ |
| Critical 보호 | ❌ | ✅ |
| Skip 모드 | ❌ | ✅ |
| 리포트 생성 | ❌ | ✅ |
| 설치 실패 위험 | 높음 | 낮음 |
| 설치 시간 | 동일 | 약간 느림 (점검 시간) |

---

## 📚 참고 문서

- 상세 가이드: `SMART_OFFLINE_INSTALLATION.md`
- 기존 가이드: `OFFLINE_INSTALLATION_GUIDE.md`
- 소스 코드:
  - [precheck_packages.py](offline_packages/precheck_packages.py)
  - [install_offline_packages_smart.sh](install_offline_packages_smart.sh)
  - [setup_cluster_full_multihead_offline_smart.sh](setup_cluster_full_multihead_offline_smart.sh)

---

**작성일**: 2025-12-04  
**버전**: 1.0.0  
**작성자**: Claude Code
