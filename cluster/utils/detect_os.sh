#!/bin/bash
################################################################################
# OS 감지 및 오프라인 패키지 디렉토리 설정 유틸리티
#
# 사용법:
#   source "${PROJECT_ROOT}/cluster/utils/detect_os.sh"
#   detect_os_version
#   set_offline_pkg_dir "$PROJECT_ROOT"
#
# export 변수:
#   OS_ID         - ubuntu, centos, rhel 등
#   OS_VERSION    - 22.04, 24.04 등
#   OS_CODENAME   - jammy, noble 등
#   OS_MAJOR      - 22, 24 등
#   OFFLINE_PKG_DIR - 오프라인 패키지 디렉토리 절대 경로
#
# 설계 원칙:
#   - 22.04에서는 기존 동작과 100% 동일 (offline_packages/)
#   - 24.04일 때만 offline_packages_2404/로 분기
#   - 여러 번 source해도 안전 (idempotent)
################################################################################

# 이미 감지된 경우 중복 실행 방지
if [[ -n "${_DETECT_OS_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_DETECT_OS_LOADED=1

detect_os_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-unknown}"
        OS_MAJOR="${VERSION_ID%%.*}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_CODENAME="unknown"
        OS_MAJOR="0"
    fi
    export OS_ID OS_VERSION OS_CODENAME OS_MAJOR
}

# 오프라인 패키지 디렉토리 설정
# 인자: $1 = 프로젝트 루트 경로
# 결과: OFFLINE_PKG_DIR 환경변수 설정
set_offline_pkg_dir() {
    local project_root="${1:-.}"

    # 24.04(noble)인 경우 _2404 디렉토리 사용
    if [[ "$OS_VERSION" == "24.04" || "$OS_CODENAME" == "noble" ]]; then
        OFFLINE_PKG_DIR="${project_root}/offline_packages_2404"
    else
        # 22.04 및 기타 모든 버전: 기존 디렉토리 유지
        OFFLINE_PKG_DIR="${project_root}/offline_packages"
    fi
    export OFFLINE_PKG_DIR
}
