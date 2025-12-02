#!/bin/bash
################################################################################
# Slurm 서비스 시작 스크립트
# 모든 Slurm 관련 서비스를 올바른 순서로 시작합니다.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "================================================================================"
echo "🚀 Slurm 서비스 시작"
echo "================================================================================"
echo ""

# YAML 파일에서 설정 읽기
if [ ! -f "my_cluster.yaml" ]; then
    echo -e "${RED}❌ my_cluster.yaml 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

# Python으로 YAML 파싱
CONTROLLER_HOSTNAME=$(python3 -c "import yaml; print(yaml.safe_load(open('my_cluster.yaml'))['nodes']['controller']['hostname'])")
SSH_USER=$(python3 -c "import yaml; print(yaml.safe_load(open('my_cluster.yaml'))['nodes']['controller']['ssh_user'])")

# 컴퓨트 노드 목록 가져오기
COMPUTE_NODES=($(python3 -c "
import yaml
with open('my_cluster.yaml') as f:
    config = yaml.safe_load(f)
    for node in config['nodes']['compute_nodes']:
        print(f\"{node['ssh_user']}@{node['ip_address']}\")
"))

echo "📋 설정 정보:"
echo "  - Controller: $CONTROLLER_HOSTNAME"
echo "  - SSH User: $SSH_USER"
echo "  - Compute Nodes: ${#COMPUTE_NODES[@]}개"
echo ""

################################################################################
# Step 1: Munge 서비스 시작 (인증 서비스)
################################################################################

echo "1️⃣  Munge 서비스 시작..."
echo "--------------------------------------------------------------------------------"

# Controller에서 Munge 시작
echo "  📍 Controller: Munge 시작"
if sudo systemctl is-active --quiet munge; then
    echo -e "    ${YELLOW}⚠️  이미 실행 중${NC}"
else
    sudo systemctl start munge
    sleep 2
    if sudo systemctl is-active --quiet munge; then
        echo -e "    ${GREEN}✅ Munge 시작 완료${NC}"
    else
        echo -e "    ${RED}❌ Munge 시작 실패${NC}"
        sudo systemctl status munge --no-pager
        exit 1
    fi
fi

# 모든 컴퓨트 노드에서 Munge 시작
echo "  📍 Compute Nodes: Munge 시작"
for node in "${COMPUTE_NODES[@]}"; do
    node_name=$(echo $node | cut -d'@' -f2)
    echo -n "    $node_name: "

    if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active --quiet munge" 2>/dev/null; then
        echo -e "${YELLOW}이미 실행 중${NC}"
    else
        if ssh -o ConnectTimeout=5 $node "sudo systemctl start munge" 2>/dev/null; then
            sleep 1
            if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active --quiet munge" 2>/dev/null; then
                echo -e "${GREEN}✅ 시작 완료${NC}"
            else
                echo -e "${RED}❌ 시작 실패${NC}"
            fi
        else
            echo -e "${RED}❌ SSH 연결 실패${NC}"
        fi
    fi
done

echo ""

################################################################################
# Step 2: MariaDB 서비스 시작 (slurmdbd 사용 시)
################################################################################

echo "2️⃣  MariaDB 서비스 확인..."
echo "--------------------------------------------------------------------------------"

if systemctl list-unit-files | grep -q "mariadb.service\|mysql.service"; then
    if sudo systemctl is-active --quiet mariadb 2>/dev/null || sudo systemctl is-active --quiet mysql 2>/dev/null; then
        echo -e "  ${YELLOW}⚠️  MariaDB 이미 실행 중${NC}"
    else
        echo "  📍 MariaDB 시작"
        sudo systemctl start mariadb 2>/dev/null || sudo systemctl start mysql 2>/dev/null || true
        sleep 2
        if sudo systemctl is-active --quiet mariadb 2>/dev/null || sudo systemctl is-active --quiet mysql 2>/dev/null; then
            echo -e "  ${GREEN}✅ MariaDB 시작 완료${NC}"
        else
            echo -e "  ${YELLOW}⚠️  MariaDB 시작 실패 (필수 아님)${NC}"
        fi
    fi
else
    echo "  ⏭️  MariaDB 미설치 (건너뜀)"
fi

echo ""

################################################################################
# Step 3: slurmdbd 서비스 시작 (있을 경우)
################################################################################

echo "3️⃣  slurmdbd 서비스 시작..."
echo "--------------------------------------------------------------------------------"

if [ -f "/etc/systemd/system/slurmdbd.service" ]; then
    echo "  📍 slurmdbd 시작"

    # 기존 프로세스 정리
    sudo pkill -9 slurmdbd 2>/dev/null || true
    sleep 1

    # 서비스 시작
    sudo systemctl start slurmdbd
    sleep 3

    # 상태 확인
    if sudo systemctl is-active --quiet slurmdbd; then
        echo -e "  ${GREEN}✅ slurmdbd 시작 완료${NC}"

        # 로그 확인
        if sudo tail -5 /var/log/slurm/slurmdbd.log 2>/dev/null | grep -q "error\|fatal"; then
            echo -e "  ${YELLOW}⚠️  로그에 경고 발견:${NC}"
            sudo tail -3 /var/log/slurm/slurmdbd.log
        fi
    else
        echo -e "  ${RED}❌ slurmdbd 시작 실패${NC}"
        sudo systemctl status slurmdbd --no-pager
    fi
else
    echo "  ⏭️  slurmdbd 미설치 (건너뜀)"
fi

echo ""

################################################################################
# Step 4: slurmctld 서비스 시작 (Controller)
################################################################################

echo "4️⃣  slurmctld 서비스 시작..."
echo "--------------------------------------------------------------------------------"

if [ -f "/etc/systemd/system/slurmctld.service" ]; then
    echo "  📍 Controller: slurmctld 시작"

    # 기존 프로세스 정리
    sudo pkill -9 slurmctld 2>/dev/null || true
    sleep 1

    # 서비스 시작
    sudo systemctl start slurmctld
    sleep 3

    # 상태 확인
    if sudo systemctl is-active --quiet slurmctld; then
        echo -e "  ${GREEN}✅ slurmctld 시작 완료${NC}"

        # 포트 확인
        if sudo ss -tulpn | grep -q ":6817.*slurmctld"; then
            echo "  ✓ 포트 6817 리스닝 확인"
        else
            echo -e "  ${YELLOW}⚠️  포트 6817 리스닝 대기 중...${NC}"
        fi
    else
        echo -e "  ${RED}❌ slurmctld 시작 실패${NC}"
        sudo systemctl status slurmctld --no-pager
        exit 1
    fi
else
    echo -e "  ${RED}❌ slurmctld 서비스 파일 없음${NC}"
    exit 1
fi

echo ""

################################################################################
# Step 5: slurmd 서비스 시작 (Compute Nodes)
################################################################################

echo "5️⃣  slurmd 서비스 시작 (Compute Nodes)..."
echo "--------------------------------------------------------------------------------"

# slurmctld가 준비될 때까지 대기
echo "  ⏱️  slurmctld 준비 대기 중..."
sleep 5

for node in "${COMPUTE_NODES[@]}"; do
    node_name=$(echo $node | cut -d'@' -f2)
    echo "  📍 $node_name: slurmd 시작"

    # 원격 노드에서 서비스 시작
    if ssh -o ConnectTimeout=10 $node "
        sudo pkill -9 slurmd 2>/dev/null || true
        sleep 1
        sudo systemctl start slurmd
    " 2>/dev/null; then
        sleep 2

        # 상태 확인
        if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active --quiet slurmd" 2>/dev/null; then
            echo -e "    ${GREEN}✅ slurmd 시작 완료${NC}"
        else
            echo -e "    ${RED}❌ slurmd 시작 실패${NC}"
        fi
    else
        echo -e "    ${RED}❌ SSH 연결 또는 명령 실행 실패${NC}"
    fi
done

echo ""

################################################################################
# Step 6: 서비스 상태 확인
################################################################################

echo "6️⃣  서비스 상태 최종 확인..."
echo "--------------------------------------------------------------------------------"

echo "  📍 Controller 서비스:"
services=("munge" "slurmctld")
if [ -f "/etc/systemd/system/slurmdbd.service" ]; then
    services+=("slurmdbd")
fi

for service in "${services[@]}"; do
    echo -n "    $service: "
    if sudo systemctl is-active --quiet $service; then
        echo -e "${GREEN}✅ 실행 중${NC}"
    else
        echo -e "${RED}❌ 중지됨${NC}"
    fi
done

echo ""
echo "  📍 Compute Nodes 서비스:"
for node in "${COMPUTE_NODES[@]}"; do
    node_name=$(echo $node | cut -d'@' -f2)
    echo "    $node_name:"

    for service in "munge" "slurmd"; do
        echo -n "      $service: "
        if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active --quiet $service" 2>/dev/null; then
            echo -e "${GREEN}✅ 실행 중${NC}"
        else
            echo -e "${RED}❌ 중지됨${NC}"
        fi
    done
done

echo ""

################################################################################
# Step 7: Slurm 클러스터 상태 확인
################################################################################

echo "7️⃣  Slurm 클러스터 상태..."
echo "--------------------------------------------------------------------------------"

if command -v sinfo &> /dev/null; then
    echo "  📊 노드 상태:"
    sinfo -N -l 2>/dev/null || echo -e "  ${YELLOW}⚠️  sinfo 명령 실패${NC}"

    echo ""
    echo "  📊 파티션 상태:"
    sinfo 2>/dev/null || echo -e "  ${YELLOW}⚠️  sinfo 명령 실패${NC}"
else
    echo -e "  ${YELLOW}⚠️  sinfo 명령어 없음 (PATH 확인 필요)${NC}"
    echo "  💡 Tip: export PATH=\$PATH:/usr/local/slurm/bin"
fi

echo ""
echo "================================================================================"
echo -e "${GREEN}✅ Slurm 서비스 시작 완료!${NC}"
echo "================================================================================"
echo ""
echo "💡 유용한 명령어:"
echo "  • 노드 상태 확인: sinfo -N -l"
echo "  • 작업 큐 확인: squeue"
echo "  • 서비스 로그: sudo journalctl -u slurmctld -f"
echo ""
