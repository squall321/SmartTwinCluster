#!/bin/bash
################################################################################
# 전체 HPC 시스템 시작 스크립트
# Slurm 클러스터 + 웹 대시보드 통합 시작
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 배너 출력
echo ""
echo "================================================================================"
echo -e "${CYAN}                    🚀 HPC 클러스터 전체 시스템 시작                    ${NC}"
echo "================================================================================"
echo ""
echo -e "${BLUE}시작할 서비스:${NC}"
echo "  1️⃣  Slurm 클러스터 서비스 (Munge, slurmdbd, slurmctld, slurmd)"
echo "  2️⃣  웹 대시보드 서비스 (Frontend, Backend, Prometheus, Node Exporter)"
echo ""

# 인자 파싱
MOCK_MODE=false
SKIP_SLURM=false
SKIP_WEB=false

show_help() {
    echo "사용법:"
    echo "  ./start_all_services.sh               모든 서비스 시작 (기본)"
    echo "  ./start_all_services.sh --mock        웹만 Mock 모드로 시작"
    echo "  ./start_all_services.sh --skip-slurm  Slurm 건너뛰고 웹만 시작"
    echo "  ./start_all_services.sh --skip-web    웹 건너뛰고 Slurm만 시작"
    echo "  ./start_all_services.sh --help        도움말 표시"
    echo ""
    exit 0
}

for arg in "$@"; do
    case $arg in
        --mock)
            MOCK_MODE=true
            ;;
        --skip-slurm)
            SKIP_SLURM=true
            ;;
        --skip-web)
            SKIP_WEB=true
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}❌ 알 수 없는 옵션: $arg${NC}"
            show_help
            ;;
    esac
done

# 상충 옵션 확인
if [ "$SKIP_SLURM" = true ] && [ "$SKIP_WEB" = true ]; then
    echo -e "${RED}❌ 오류: --skip-slurm과 --skip-web을 동시에 사용할 수 없습니다.${NC}"
    exit 1
fi

################################################################################
# Phase 1: Slurm 클러스터 서비스 시작
################################################################################

if [ "$SKIP_SLURM" = false ]; then
    echo ""
    echo "================================================================================"
    echo -e "${MAGENTA}Phase 1: Slurm 클러스터 서비스 시작${NC}"
    echo "================================================================================"
    echo ""

    if [ -f "./start_slurm_services.sh" ]; then
        ./start_slurm_services.sh

        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✅ Phase 1 완료: Slurm 서비스 시작 성공${NC}"
        else
            echo ""
            echo -e "${RED}❌ Phase 1 실패: Slurm 서비스 시작 실패${NC}"
            echo -e "${YELLOW}계속 진행하시겠습니까? (y/N): ${NC}"
            read -r -n 1 response
            echo ""
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo "종료합니다."
                exit 1
            fi
        fi
    else
        echo -e "${RED}❌ 오류: start_slurm_services.sh 파일을 찾을 수 없습니다.${NC}"
        exit 1
    fi

    # Slurm 서비스 안정화 대기
    echo ""
    echo -e "${YELLOW}⏱️  Slurm 서비스 안정화 대기 중... (5초)${NC}"
    sleep 5
else
    echo ""
    echo "================================================================================"
    echo -e "${YELLOW}Phase 1: Slurm 클러스터 서비스 건너뜀 (--skip-slurm)${NC}"
    echo "================================================================================"
fi

################################################################################
# Phase 2: 웹 대시보드 서비스 시작
################################################################################

if [ "$SKIP_WEB" = false ]; then
    echo ""
    echo "================================================================================"
    echo -e "${MAGENTA}Phase 2: 웹 대시보드 서비스 시작${NC}"
    echo "================================================================================"
    echo ""

    if [ "$MOCK_MODE" = true ]; then
        echo -e "${BLUE}🎭 Mock Mode로 웹 서비스 시작 중...${NC}"
        if [ -f "./start.sh" ]; then
            ./start.sh --mock
        else
            echo -e "${RED}❌ 오류: start.sh 파일을 찾을 수 없습니다.${NC}"
            exit 1
        fi
    else
        echo -e "${BLUE}🚀 Production Mode로 웹 서비스 시작 중...${NC}"
        if [ -f "./start.sh" ]; then
            ./start.sh
        else
            echo -e "${RED}❌ 오류: start.sh 파일을 찾을 수 없습니다.${NC}"
            exit 1
        fi
    fi

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ Phase 2 완료: 웹 대시보드 시작 성공${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠️  Phase 2 경고: 웹 대시보드 시작 시 일부 문제 발생${NC}"
    fi
else
    echo ""
    echo "================================================================================"
    echo -e "${YELLOW}Phase 2: 웹 대시보드 서비스 건너뜀 (--skip-web)${NC}"
    echo "================================================================================"
fi

################################################################################
# 최종 상태 확인
################################################################################

echo ""
echo "================================================================================"
echo -e "${CYAN}                        🎉 시스템 시작 완료!                        ${NC}"
echo "================================================================================"
echo ""

# Slurm 상태 확인
if [ "$SKIP_SLURM" = false ]; then
    echo -e "${BLUE}📊 Slurm 클러스터 상태:${NC}"
    echo "--------------------------------------------------------------------------------"

    if command -v sinfo &> /dev/null; then
        sinfo 2>/dev/null || echo -e "${YELLOW}  ⚠️  sinfo 실행 실패 (PATH 확인 필요)${NC}"
        echo ""

        echo -e "${BLUE}📋 실행 중인 작업:${NC}"
        squeue 2>/dev/null || echo -e "${YELLOW}  ⚠️  squeue 실행 실패${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Slurm 명령어를 찾을 수 없습니다.${NC}"
        echo "  💡 Tip: export PATH=\$PATH:/usr/local/slurm/bin"
    fi
    echo ""
fi

# 웹 서비스 상태 확인
if [ "$SKIP_WEB" = false ]; then
    echo -e "${BLUE}🌐 웹 대시보드 서비스 상태:${NC}"
    echo "--------------------------------------------------------------------------------"

    services=(
        "5010:Backend API"
        "9090:Prometheus"
        "9100:Node Exporter"
    )

    for service_info in "${services[@]}"; do
        port=$(echo $service_info | cut -d: -f1)
        name=$(echo $service_info | cut -d: -f2)

        if lsof -i :$port -sTCP:LISTEN >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅${NC} $name (포트 $port) - 실행 중"
        else
            echo -e "  ${RED}❌${NC} $name (포트 $port) - 중지됨"
        fi
    done
    echo ""
fi

echo "================================================================================"
echo -e "${GREEN}💡 유용한 정보:${NC}"
echo "================================================================================"
echo ""

if [ "$SKIP_SLURM" = false ]; then
    echo -e "${BLUE}Slurm 명령어:${NC}"
    echo "  • 노드 상태:     sinfo -N -l"
    echo "  • 작업 제출:     sbatch <script.sh>"
    echo "  • 작업 확인:     squeue"
    echo "  • 로그 확인:     sudo journalctl -u slurmctld -f"
    echo ""
fi

if [ "$SKIP_WEB" = false ]; then
    echo -e "${BLUE}웹 대시보드 접속:${NC}"
    if [ "$MOCK_MODE" = true ]; then
        echo "  • Frontend:      http://localhost:3010 (개발 서버)"
    else
        echo "  • Frontend:      http://localhost (Nginx)"
    fi
    echo "  • Backend API:   http://localhost:5010"
    echo "  • Prometheus:    http://localhost:9090"
    echo ""
fi

echo -e "${BLUE}시스템 관리:${NC}"
echo "  • 전체 중지:     ./stop_all_services.sh"
echo "  • Slurm만 중지:  ./stop_slurm_services.sh"
echo "  • 웹만 중지:     ./stop.sh"
echo ""
echo "================================================================================"
