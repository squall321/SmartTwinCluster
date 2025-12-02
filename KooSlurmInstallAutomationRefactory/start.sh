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
    echo "  ./start.sh          Production Mode (기본)"
    echo "  ./start.sh --mock   Mock Mode (테스트용)"
    echo "  ./start.sh --help   이 도움말 표시"
    echo ""
    echo "모드 설명:"
    echo "  📊 Production Mode:"
    echo "     - 실제 Slurm 클러스터 연동"
    echo "     - 실시간 Job/Node 데이터"
    echo "     - Prometheus 메트릭 수집"
    echo "     - 운영 환경용"
    echo ""
    echo "  🎭 Mock Mode:"
    echo "     - Slurm 없이 실행 가능"
    echo "     - 고정된 테스트 데이터"
    echo "     - 클러스터에 영향 없음"
    echo "     - 개발/테스트/데모용"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 인자 파싱
MOCK_MODE=false

for arg in "$@"; do
    case $arg in
        --mock)
            MOCK_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            # 다른 인자는 그대로 전달
            ;;
    esac
done

# Mock Mode 선택
if [ "$MOCK_MODE" = true ]; then
    if [ -f "dashboard/start_mock.sh" ]; then
        echo "🎭 HPC 웹 서비스 시작 중 (Mock Mode)..."
        ./dashboard/start_mock.sh
    else
        echo "❌ 오류: dashboard/start_mock.sh 파일을 찾을 수 없습니다."
        echo "   현재 디렉토리: $(pwd)"
        exit 1
    fi
else
    if [ -f "dashboard/start_complete.sh" ]; then
        echo "🚀 HPC 웹 서비스 시작 중 (Production Mode)..."
        ./dashboard/start_complete.sh
    else
        echo "❌ 오류: dashboard/start_complete.sh 파일을 찾을 수 없습니다."
        echo "   현재 디렉토리: $(pwd)"
        exit 1
    fi
fi
