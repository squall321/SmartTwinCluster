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

# source 시 자동 호출: OFFLINE_PKG_DIR이 비어있을 때만 자동 감지 수행
# (sudo -E 등으로 환경변수가 부분 상속되어 함수 정의가 누락되는 케이스 방어)
if [[ -z "${OFFLINE_PKG_DIR:-}" ]]; then
    detect_os_version
    # 호출자의 PROJECT_ROOT 사용, 없으면 source 한 스크립트의 상위로 추정
    _detect_root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    set_offline_pkg_dir "$_detect_root"
    unset _detect_root
fi
