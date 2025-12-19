#!/bin/bash
################################################################################
# 환경 변수 생성 래퍼 스크립트 (프로젝트 루트 실행용)
################################################################################

# 프로젝트 루트로 이동
cd "$(dirname "$0")"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "사용법: $0 <command> [options]"
    echo ""
    echo "명령어:"
    echo "  sso             SSO 환경 변수 생성 (auth_portal_4430)"
    echo "  all             모든 서비스 환경 변수 생성"
    echo ""
    echo "SSO 옵션:"
    echo "  --config, -c    YAML 설정 파일 경로 (필수)"
    echo "  --output, -o    출력 파일 경로 (기본: .env)"
    echo "  --no-secrets    시크릿 제외 (예: .env.example용)"
    echo "  --force, -f     기존 파일 덮어쓰기"
    echo "  --print         파일 생성 대신 stdout 출력"
    echo ""
    echo "예시:"
    echo "  # SSO 환경변수 생성"
    echo "  $0 sso --config my_multihead_cluster.yaml"
    echo ""
    echo "  # 프로덕션용 .env 생성"
    echo "  $0 sso -c cluster.yaml -o dashboard/auth_portal_4430/.env.production"
    echo ""
    echo "  # 버전관리용 .env.example 생성 (시크릿 제외)"
    echo "  $0 sso -c cluster.yaml --no-secrets -o .env.example"
}

generate_sso_env() {
    local SSO_SCRIPT="dashboard/auth_portal_4430/generate_sso_env.py"

    # Python 스크립트 존재 확인
    if [ ! -f "$SSO_SCRIPT" ]; then
        echo -e "${RED}❌ 오류: $SSO_SCRIPT 파일을 찾을 수 없습니다.${NC}"
        exit 1
    fi

    # 인자 전달
    python3 "$SSO_SCRIPT" "$@"
}

# 인자 없으면 사용법 출력
if [ $# -eq 0 ]; then
    print_usage
    exit 1
fi

# 명령어 파싱
COMMAND=$1
shift

case "$COMMAND" in
    sso)
        echo -e "${BLUE}🔐 SSO 환경 변수 생성 중...${NC}"
        generate_sso_env "$@"
        ;;
    all)
        echo -e "${BLUE}📦 모든 서비스 환경 변수 생성 중...${NC}"

        # SSO 환경변수
        if [ -n "$1" ]; then
            echo -e "${YELLOW}→ SSO 환경변수 생성${NC}"
            generate_sso_env "$@"
        else
            echo -e "${YELLOW}⚠️  --config 옵션이 필요합니다${NC}"
            echo "  예: $0 all --config my_multihead_cluster.yaml"
            exit 1
        fi

        echo -e "${GREEN}✅ 완료${NC}"
        ;;
    help|--help|-h)
        print_usage
        exit 0
        ;;
    *)
        echo -e "${RED}❌ 알 수 없는 명령어: $COMMAND${NC}"
        print_usage
        exit 1
        ;;
esac
