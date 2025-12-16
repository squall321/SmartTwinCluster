#!/bin/bash
################################################################################
# HPC 웹 서비스 시작 스크립트 (프로젝트 루트용)
#
# 사용법:
#   ./start.sh          # Production Mode (기본)
#   ./start.sh --mock   # Mock Mode (테스트용)
#   ./start.sh --help   # 도움말
################################################################################

cd "$(dirname "$0")"

# 도움말 출력
show_help() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 HPC 웹 서비스 시작 스크립트"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "사용법:"
    echo "  ./start.sh                 Production Mode (Gunicorn, 기본)"
    echo "  ./start.sh --dev           Development Mode (Flask dev server)"
    echo "  ./start.sh --mock          Mock Mode (테스트용)"
    echo "  ./start.sh --help          이 도움말 표시"
    echo ""
    echo "모드 설명:"
    echo "  🏭 Production Mode (기본):"
    echo "     - Gunicorn WSGI 서버"
    echo "     - 리소스 제한 적용 가능"
    echo "     - 실제 Slurm 클러스터 연동"
    echo "     - 프로덕션 환경용"
    echo ""
    echo "  🔧 Development Mode:"
    echo "     - Flask 개발 서버"
    echo "     - 코드 변경 시 자동 재시작"
    echo "     - 디버깅 활성화"
    echo "     - 개발 환경용"
    echo ""
    echo "  🎭 Mock Mode:"
    echo "     - Flask 개발 서버"
    echo "     - Slurm 없이 실행 가능"
    echo "     - 고정된 테스트 데이터"
    echo "     - 개발/테스트/데모용"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 인자 파싱
MODE="production"  # Default: production

for arg in "$@"; do
    case $arg in
        --dev)
            MODE="development"
            shift
            ;;
        --mock)
            MODE="mock"
            shift
            ;;
        --production)
            MODE="production"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            # 다른 인자는 무시
            ;;
    esac
done

# 모드 선택
case $MODE in
    development)
        if [ -f "dashboard/start_dev.sh" ]; then
            echo "🔧 HPC 웹 서비스 시작 중 (Development Mode - Flask)..."
            ./dashboard/start_dev.sh
        else
            echo "❌ 오류: dashboard/start_dev.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
    mock)
        if [ -f "dashboard/start_mock.sh" ]; then
            echo "🎭 HPC 웹 서비스 시작 중 (Mock Mode - Flask)..."
            ./dashboard/start_mock.sh
        else
            echo "❌ 오류: dashboard/start_mock.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
    production)
        if [ -f "dashboard/start_production.sh" ]; then
            echo "🏭 HPC 웹 서비스 시작 중 (Production Mode - Gunicorn)..."
            ./dashboard/start_production.sh
        else
            echo "❌ 오류: dashboard/start_production.sh 파일을 찾을 수 없습니다."
            echo "   현재 디렉토리: $(pwd)"
            exit 1
        fi
        ;;
esac
