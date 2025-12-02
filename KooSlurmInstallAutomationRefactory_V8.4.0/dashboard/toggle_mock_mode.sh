#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "🔄 Mock Mode 전환"
echo "=========================================="
echo ""
echo "현재 실행 중인 서버를 종료하고 다른 모드로 재시작합니다."
echo ""
echo "선택:"
echo "  1) Production Mode (실제 Slurm)"
echo "  2) Mock Mode (테스트 데이터)"
echo "  3) 취소"
echo ""
read -p "선택 (1-3): " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}→ Production Mode로 전환 중...${NC}"
        cd "$SCRIPT_DIR"
        ./stop_all.sh
        sleep 2
        ./start_all.sh
        ;;
    2)
        echo ""
        echo -e "${YELLOW}→ Mock Mode로 전환 중...${NC}"
        cd "$SCRIPT_DIR"
        ./stop_all.sh
        sleep 2
        ./start_all_mock.sh
        ;;
    3)
        echo "취소됨"
        exit 0
        ;;
    *)
        echo "잘못된 선택"
        exit 1
        ;;
esac
