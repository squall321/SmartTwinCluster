#!/bin/bash
################################################################################
# 헬스 체크 래퍼 스크립트 (프로젝트 루트 실행용)
################################################################################

# 프로젝트 루트로 이동
cd "$(dirname "$0")"

# 헬스 체크 스크립트 존재 확인
if [ ! -f "web_services/scripts/health_check.sh" ]; then
    echo "❌ 오류: web_services/scripts/health_check.sh 파일을 찾을 수 없습니다."
    exit 1
fi

# 헬스 체크 실행
./web_services/scripts/health_check.sh "$@"
