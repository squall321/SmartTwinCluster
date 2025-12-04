# 스마트 오프라인 설치 가이드

## 📋 개요

이 가이드는 **이미 설치된 패키지를 자동으로 건너뛰고**, **Critical 시스템 패키지를 보호**하는 스마트 오프라인 설치 시스템에 대한 설명입니다.

## 🆕 새로운 기능

### 1. **사전 점검 시스템 (Pre-Check)**
- 설치 전에 패키지 충돌 감지
- Critical 시스템 패키지 보호
- Python 패키지 충돌 검사
- 문제가 있으면 설치 전에 리포트 생성 후 중단

### 2. **스마트 Skip 모드**
- 이미 설치된 패키지 자동 건너뛰기
- 버전 관계없이 무조건 건너뛰기 (안전)
- Skip 리스트 파일 기반 제어

### 3. **상세한 리포트**
- 설치 전 점검 리포트
- 설치 후 검증 리포트
- 건너뛴 패키지 목록
- 실패한 패키지 목록

---

## 🚀 빠른 시작

### 사전 점검 + 스마트 설치 (원스텝)

```bash
sudo ./setup_cluster_full_multihead_offline_smart.sh
```

---

## 📖 구성 요소

### 1. precheck_packages.py

**설치 전 패키지 점검 도구**

```bash
python3 offline_packages/precheck_packages.py \
    --deb-dir offline_packages/apt_packages \
    --requirements dashboard/backend_5010/requirements.txt
```

**출력**:
- `precheck_report.txt`: 전체 점검 리포트
- `apt_skip_list.txt`: 건너뛸 APT 패키지 목록
- `python_skip_list.txt`: 건너뛸 Python 패키지 목록

### 2. install_offline_packages_smart.sh

**Skip 리스트 기반 스마트 APT 설치**

```bash
sudo bash install_offline_packages_smart.sh \
    --deb-dir offline_packages/apt_packages \
    --skip-installed
```

### 3. setup_cluster_full_multihead_offline_smart.sh

**통합 메인 스크립트**

```bash
sudo ./setup_cluster_full_multihead_offline_smart.sh
```

---

## 📊 리포트 예제

```
================================================================================
   오프라인 패키지 설치 전 점검 리포트
================================================================================

📊 통계
시스템에 설치된 APT 패키지: 1245
오프라인 .deb 패키지: 523

⚠️  발견된 이슈
🔴 Critical: 3    ← 즉시 조치 필요
🟡 Warning: 12   ← 검토 권장
🔵 Info: 145     ← 건너뛸 패키지

🔴 CRITICAL 이슈
[1] systemd - Critical system package
    조치: rm -f apt_packages/systemd_*.deb

✅ 다음 단계
CRITICAL 이슈를 해결한 후 설치를 진행하세요.
```

---

## ⚠️ Critical 패키지

다음 패키지는 절대 업데이트하지 않습니다:

```
systemd, init, libc6, libc-bin, base-files, base-passwd
dpkg, apt, coreutils, bash, dash, util-linux
```

---

## 🛠️ 사용 예제

### 1. 사전 점검만 실행

```bash
python3 offline_packages/precheck_packages.py \
    --deb-dir offline_packages/apt_packages
```

### 2. Dry-run 모드

```bash
sudo ./setup_cluster_full_multihead_offline_smart.sh --dry-run
```

### 3. 사전 점검 없이 빠른 설치 (위험)

```bash
sudo ./setup_cluster_full_multihead_offline_smart.sh --skip-precheck
```

---

자세한 내용은 `OFFLINE_INSTALLATION_GUIDE.md`를 참조하세요.
