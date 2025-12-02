#!/bin/bash
################################################################################
# 전체 HPC 시스템 정지 스크립트
# Slurm 클러스터 + 웹 대시보드 통합 정지
################################################################################

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
echo -e "${CYAN}                    🛑 HPC 클러스터 전체 시스템 정지                    ${NC}"
echo "================================================================================"
echo ""
echo -e "${BLUE}정지할 서비스:${NC}"
echo "  1️⃣  웹 대시보드 서비스 (Frontend, Backend, Prometheus, Node Exporter)"
echo "  2️⃣  Slurm 클러스터 서비스 (slurmd, slurmctld, slurmdbd, Munge)"
echo ""

# 인자 파싱
SKIP_SLURM=false
SKIP_WEB=false
FORCE=false

show_help() {
    echo "사용법:"
    echo "  ./stop_all_services.sh               모든 서비스 정지 (기본)"
    echo "  ./stop_all_services.sh --skip-slurm  Slurm 건너뛰고 웹만 정지"
    echo "  ./stop_all_services.sh --skip-web    웹 건너뛰고 Slurm만 정지"
    echo "  ./stop_all_services.sh --force       확인 없이 강제 정지"
    echo "  ./stop_all_services.sh --help        도움말 표시"
    echo ""
    exit 0
}

for arg in "$@"; do
    case $arg in
        --skip-slurm)
            SKIP_SLURM=true
            ;;
        --skip-web)
            SKIP_WEB=true
            ;;
        --force|-f)
            FORCE=true
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

# 확인 프롬프트 (--force가 아닐 경우)
if [ "$FORCE" = false ]; then
    echo -e "${YELLOW}⚠️  경고: 모든 HPC 서비스를 정지합니다.${NC}"
    echo -e "${YELLOW}   실행 중인 Slurm 작업이 있다면 영향을 받을 수 있습니다.${NC}"
    echo ""
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "정지 취소됨."
        exit 0
    fi
fi

################################################################################
# Phase 1: 웹 대시보드 서비스 정지 (먼저 정지)
################################################################################

if [ "$SKIP_WEB" = false ]; then
    echo ""
    echo "================================================================================"
    echo -e "${MAGENTA}Phase 1: 웹 대시보드 서비스 정지${NC}"
    echo "================================================================================"
    echo ""

    if [ -f "./stop.sh" ]; then
        ./stop.sh

        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✅ Phase 1 완료: 웹 대시보드 정지 성공${NC}"
        else
            echo ""
            echo -e "${YELLOW}⚠️  Phase 1 경고: 웹 대시보드 정지 시 일부 문제 발생${NC}"
        fi
    else
        echo -e "${RED}❌ 오류: stop.sh 파일을 찾을 수 없습니다.${NC}"
    fi

    # 웹 서비스 정지 후 대기
    echo ""
    echo -e "${YELLOW}⏱️  웹 서비스 정리 대기 중... (3초)${NC}"
    sleep 3
else
    echo ""
    echo "================================================================================"
    echo -e "${YELLOW}Phase 1: 웹 대시보드 서비스 건너뜀 (--skip-web)${NC}"
    echo "================================================================================"
fi

################################################################################
# Phase 2: Slurm 클러스터 서비스 정지
################################################################################

if [ "$SKIP_SLURM" = false ]; then
    echo ""
    echo "================================================================================"
    echo -e "${MAGENTA}Phase 2: Slurm 클러스터 서비스 정지${NC}"
    echo "================================================================================"
    echo ""

    if [ -f "./stop_slurm_services.sh" ]; then
        # stop_slurm_services.sh는 대화형이므로 입력 자동화
        if [ "$FORCE" = true ]; then
            # --force 모드: MariaDB와 Munge도 자동으로 정지
            echo "y" | ./stop_slurm_services.sh
            echo "y" | ./stop_slurm_services.sh  # 두 번째 프롬프트 (Munge)
        else
            ./stop_slurm_services.sh
        fi

        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✅ Phase 2 완료: Slurm 서비스 정지 성공${NC}"
        else
            echo ""
            echo -e "${RED}❌ Phase 2 실패: Slurm 서비스 정지 실패${NC}"
            echo -e "${YELLOW}강제 종료를 시도하시겠습니까? (y/N): ${NC}"
            read -r -n 1 response
            echo ""
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}강제 종료 시도 중...${NC}"

                # Controller에서 강제 종료
                sudo pkill -9 slurmctld slurmdbd 2>/dev/null || true

                echo -e "${GREEN}✅ 강제 종료 완료${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ 오류: stop_slurm_services.sh 파일을 찾을 수 없습니다.${NC}"
    fi
else
    echo ""
    echo "================================================================================"
    echo -e "${YELLOW}Phase 2: Slurm 클러스터 서비스 건너뜀 (--skip-slurm)${NC}"
    echo "================================================================================"
fi

################################################################################
# 최종 상태 확인
################################################################################

echo ""
echo "================================================================================"
echo -e "${CYAN}                        ✅ 시스템 정지 완료!                        ${NC}"
echo "================================================================================"
echo ""

# 서비스 상태 확인
echo -e "${BLUE}📊 최종 상태 확인:${NC}"
echo "--------------------------------------------------------------------------------"

if [ "$SKIP_SLURM" = false ]; then
    echo ""
    echo -e "${BLUE}Slurm 서비스:${NC}"

    slurm_services=("slurmctld" "slurmdbd" "munge")
    for service in "${slurm_services[@]}"; do
        echo -n "  $service: "
        if sudo systemctl is-active --quiet $service 2>/dev/null; then
            echo -e "${YELLOW}⚠️  여전히 실행 중${NC}"
        else
            echo -e "${GREEN}✅ 정지됨${NC}"
        fi
    done

    # 프로세스 확인
    echo ""
    slurm_processes=$(ps aux | grep -E "slurm(ctld|dbd|d)" | grep -v grep | wc -l)
    if [ $slurm_processes -eq 0 ]; then
        echo -e "  ${GREEN}✅ Slurm 프로세스 없음 (정상 정지)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $slurm_processes 개의 Slurm 프로세스 실행 중${NC}"
    fi
fi

if [ "$SKIP_WEB" = false ]; then
    echo ""
    echo -e "${BLUE}웹 대시보드 서비스:${NC}"

    web_ports=("5010" "9090" "9100" "3010")
    all_stopped=true

    for port in "${web_ports[@]}"; do
        if lsof -i :$port -sTCP:LISTEN >/dev/null 2>&1; then
            echo -e "  ${YELLOW}⚠️  포트 $port 여전히 사용 중${NC}"
            all_stopped=false
        fi
    done

    if [ "$all_stopped" = true ]; then
        echo -e "  ${GREEN}✅ 모든 웹 서비스 포트 정리됨${NC}"
    fi
fi

echo ""
echo "================================================================================"
echo -e "${GREEN}💡 다음 단계:${NC}"
echo "================================================================================"
echo ""
echo "  • 시스템 재시작:    ./start_all_services.sh"
echo "  • Slurm만 재시작:   ./start_slurm_services.sh"
echo "  • 웹만 재시작:      ./start.sh"
echo ""
echo "  • 상태 확인:"
echo "    - Slurm:          sinfo"
echo "    - 웹 서비스:      lsof -i -P -n | grep LISTEN"
echo "    - 프로세스:       ps aux | grep slurm"
echo ""
echo "================================================================================"
