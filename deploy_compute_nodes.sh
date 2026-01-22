#!/bin/bash
################################################################################
# 계산 노드 배포 래퍼 스크립트 (프로젝트 메인에서 실행)
#
# 설명:
#   offline_deploy/deploy_to_compute_node.sh를 프로젝트 루트에서 실행하기 위한 래퍼
#
# 사용법:
#   ./deploy_compute_nodes.sh [OPTIONS]
#
# 모든 옵션은 deploy_to_compute_node.sh와 동일합니다.
#
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# offline_deploy/deploy_to_compute_node.sh를 실행하되,
# 현재 디렉토리는 프로젝트 루트로 유지
exec "$SCRIPT_DIR/offline_deploy/deploy_to_compute_node.sh" "$@"
