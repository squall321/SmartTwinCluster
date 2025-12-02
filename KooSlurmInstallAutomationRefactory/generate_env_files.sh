#!/bin/bash
################################################################################
# 환경 변수 생성 래퍼 스크립트 (프로젝트 루트 실행용)
################################################################################

# 프로젝트 루트로 이동
cd "$(dirname "$0")"

# Python 스크립트 존재 확인
if [ ! -f "web_services/scripts/generate_env_files.py" ]; then
    echo "❌ 오류: web_services/scripts/generate_env_files.py 파일을 찾을 수 없습니다."
    exit 1
fi

# 환경 인자 확인
if [ $# -eq 0 ]; then
    echo "사용법: $0 <environment>"
    echo ""
    echo "환경:"
    echo "  development    개발 환경 (.env 파일 생성)"
    echo "  production     프로덕션 환경 (.env 파일 생성)"
    echo ""
    echo "예시:"
    echo "  $0 development"
    echo "  $0 production"
    exit 1
fi

# Python 스크립트 실행
python3 web_services/scripts/generate_env_files.py "$@"
