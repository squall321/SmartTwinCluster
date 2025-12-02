#!/bin/bash
################################################################################
# 웹 서비스 설치 래퍼 스크립트 (프로젝트 루트 실행용)
################################################################################

# 프로젝트 루트로 이동
cd "$(dirname "$0")"

# 실제 설치 스크립트 존재 확인
if [ ! -f "web_services/scripts/setup_web_services.sh" ]; then
    echo "❌ 오류: web_services/scripts/setup_web_services.sh 파일을 찾을 수 없습니다."
    exit 1
fi

# 모든 인자를 그대로 전달하여 실행
./web_services/scripts/setup_web_services.sh "$@"
