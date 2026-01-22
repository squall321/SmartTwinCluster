#!/bin/bash
################################################################################
# 프론트엔드 빌드 래퍼 스크립트 (프로젝트 메인에서 실행)
#
# 설명:
#   dashboard/build_all_frontends.sh를 프로젝트 루트에서 실행하기 위한 래퍼
#
# 사용법:
#   ./build_frontends.sh                      # 전체 프론트엔드 빌드
#   ./build_frontends.sh --frontend <name>    # 특정 프론트엔드만 빌드
#
# 옵션:
#   --frontend <name>   특정 프론트엔드만 빌드
#                       (예: frontend_3010, vnc_service_8002, auth_portal_4431)
#
# 예제:
#   ./build_frontends.sh                              # 전체 빌드
#   ./build_frontends.sh --frontend frontend_3010     # Dashboard만 빌드
#   ./build_frontends.sh --frontend vnc_service_8002  # VNC만 빌드
#
# 모든 옵션은 build_all_frontends.sh와 동일합니다.
#
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# dashboard/build_all_frontends.sh를 실행하되,
# 현재 디렉토리는 프로젝트 루트로 유지
exec "$SCRIPT_DIR/dashboard/build_all_frontends.sh" "$@"
