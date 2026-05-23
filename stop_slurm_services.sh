#!/bin/bash
################################################################################
# Slurm 서비스 정지 스크립트
# 모든 Slurm 관련 서비스를 올바른 순서로 정지합니다.
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
echo "🛑 Slurm 서비스 정지"
echo "================================================================================"
echo ""

# YAML 파일에서 설정 읽기
if [ ! -f "my_multihead_cluster.yaml" ]; then
    echo -e "${RED}❌ my_multihead_cluster.yaml 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

# Python으로 YAML 파싱
CONTROLLER_HOSTNAME=$(python3 -c "import yaml; print(yaml.safe_load(open('my_multihead_cluster.yaml'))['nodes']['controller']['hostname'])")
SSH_USER=$(python3 -c "import yaml; print(yaml.safe_load(open('my_multihead_cluster.yaml'))['nodes']['controller']['ssh_user'])")

# 컴퓨트 노드 목록 가져오기
COMPUTE_NODES=($(python3 -c "
import yaml
with open('my_multihead_cluster.yaml') as f:
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
# Step 1: slurmd 서비스 정지 (Compute Nodes)
################################################################################

echo "1️⃣  slurmd 서비스 정지 (Compute Nodes)..."
echo "--------------------------------------------------------------------------------"

for node in "${COMPUTE_NODES[@]}"; do
    node_name=$(echo $node | cut -d'@' -f2)
    echo "  📍 $node_name: slurmd 정지"

    if ssh -o ConnectTimeout=10 $node "
        sudo systemctl stop slurmd 2>/dev/null || true
        sudo pkill -9 slurmd 2>/dev/null || true
    " 2>/dev/null; then
        sleep 1

        # 상태 확인
        if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active --quiet slurmd" 2>/dev/null; then
            echo -e "    ${YELLOW}⚠️  여전히 실행 중 (강제 종료 시도)${NC}"
            ssh -o ConnectTimeout=5 $node "sudo pkill -9 slurmd" 2>/dev/null || true
        else
            echo -e "    ${GREEN}✅ slurmd 정지 완료${NC}"
        fi
    else
        echo -e "    ${YELLOW}⚠️  SSH 연결 실패 (이미 정지되었거나 접근 불가)${NC}"
    fi
done

echo ""

################################################################################
# Step 2: slurmctld 서비스 정지 (Controller)
################################################################################

echo "2️⃣  slurmctld 서비스 정지..."
echo "--------------------------------------------------------------------------------"

if [ -f "/etc/systemd/system/slurmctld.service" ]; then
    echo "  📍 Controller: slurmctld 정지"

    sudo systemctl stop slurmctld 2>/dev/null || true
    sleep 1

    # 프로세스 강제 종료
    sudo pkill -9 slurmctld 2>/dev/null || true
    sleep 1

    # 상태 확인
    if sudo systemctl is-active --quiet slurmctld; then
        echo -e "  ${YELLOW}⚠️  여전히 실행 중 (강제 종료 재시도)${NC}"
        sudo pkill -9 slurmctld 2>/dev/null || true
        sleep 1
    fi

    if pgrep -x slurmctld > /dev/null; then
        echo -e "  ${RED}❌ slurmctld 프로세스 종료 실패${NC}"
    else
        echo -e "  ${GREEN}✅ slurmctld 정지 완료${NC}"
    fi
else
    echo "  ⏭️  slurmctld 서비스 파일 없음 (건너뜀)"
fi

echo ""

################################################################################
# Step 3: slurmdbd 서비스 정지 (있을 경우)
################################################################################

echo "3️⃣  slurmdbd 서비스 정지..."
echo "--------------------------------------------------------------------------------"

if [ -f "/etc/systemd/system/slurmdbd.service" ]; then
    echo "  📍 slurmdbd 정지"

    sudo systemctl stop slurmdbd 2>/dev/null || true
    sleep 1

    # 프로세스 강제 종료
    sudo pkill -9 slurmdbd 2>/dev/null || true
    sleep 1

    # 상태 확인
    if sudo systemctl is-active --quiet slurmdbd; then
        echo -e "  ${YELLOW}⚠️  여전히 실행 중 (강제 종료 재시도)${NC}"
        sudo pkill -9 slurmdbd 2>/dev/null || true
        sleep 1
    fi

    if pgrep -x slurmdbd > /dev/null; then
        echo -e "  ${RED}❌ slurmdbd 프로세스 종료 실패${NC}"
    else
        echo -e "  ${GREEN}✅ slurmdbd 정지 완료${NC}"
    fi
else
    echo "  ⏭️  slurmdbd 미설치 (건너뜀)"
fi

echo ""

################################################################################
# Step 4: MariaDB 서비스 정지 (선택 사항)
################################################################################

echo "4️⃣  MariaDB 서비스 정지 (선택 사항)..."
echo "--------------------------------------------------------------------------------"

read -p "  ❓ MariaDB도 정지하시겠습니까? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if systemctl list-unit-files | grep -q "mariadb.service\|mysql.service"; then
        echo "  📍 MariaDB 정지"
        sudo systemctl stop mariadb 2>/dev/null || sudo systemctl stop mysql 2>/dev/null || true
        sleep 2

        if sudo systemctl is-active --quiet mariadb 2>/dev/null || sudo systemctl is-active --quiet mysql 2>/dev/null; then
            echo -e "  ${YELLOW}⚠️  MariaDB 정지 실패${NC}"
        else
            echo -e "  ${GREEN}✅ MariaDB 정지 완료${NC}"
        fi
    else
        echo "  ⏭️  MariaDB 미설치 (건너뜀)"
    fi
else
    echo "  ⏭️  MariaDB 정지 건너뜀"
fi

echo ""

################################################################################
# Step 5: Munge 서비스 정지 (선택 사항)
################################################################################

echo "5️⃣  Munge 서비스 정지 (선택 사항)..."
echo "--------------------------------------------------------------------------------"

read -p "  ❓ Munge도 정지하시겠습니까? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Controller에서 Munge 정지
    echo "  📍 Controller: Munge 정지"
    sudo systemctl stop munge 2>/dev/null || true

    if sudo systemctl is-active --quiet munge; then
        echo -e "    ${YELLOW}⚠️  Munge 정지 실패${NC}"
    else
        echo -e "    ${GREEN}✅ Munge 정지 완료${NC}"
    fi

    # 모든 컴퓨트 노드에서 Munge 정지
    echo "  📍 Compute Nodes: Munge 정지"
    for node in "${COMPUTE_NODES[@]}"; do
        node_name=$(echo $node | cut -d'@' -f2)
        echo -n "    $node_name: "

        if ssh -o ConnectTimeout=5 $node "sudo systemctl stop munge 2>/dev/null || true" 2>/dev/null; then
            sleep 1
            if ssh -o ConnectTimeout=5 $node "sudo systemctl is-active --quiet munge" 2>/dev/null; then
                echo -e "${YELLOW}정지 실패${NC}"
            else
                echo -e "${GREEN}✅ 정지 완료${NC}"
            fi
        else
            echo -e "${YELLOW}SSH 연결 실패${NC}"
        fi
    done
else
    echo "  ⏭️  Munge 정지 건너뜀 (다음 Slurm 시작을 위해 실행 유지)"
fi

echo ""

################################################################################
# Step 6: 서비스 상태 최종 확인
################################################################################

echo "6️⃣  서비스 상태 최종 확인..."
echo "--------------------------------------------------------------------------------"

echo "  📍 Controller 서비스:"
services=("munge" "slurmctld")
if [ -f "/etc/systemd/system/slurmdbd.service" ]; then
    services+=("slurmdbd")
fi
if systemctl list-unit-files | grep -q "mariadb.service\|mysql.service"; then
    services+=("mariadb")
fi

for service in "${services[@]}"; do
    echo -n "    $service: "
    if sudo systemctl is-active --quiet $service 2>/dev/null; then
        echo -e "${YELLOW}⚠️  실행 중${NC}"
    else
        echo -e "${GREEN}✅ 정지됨${NC}"
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
            echo -e "${YELLOW}⚠️  실행 중${NC}"
        else
            echo -e "${GREEN}✅ 정지됨${NC}"
        fi
    done
done

echo ""

################################################################################
# Step 7: 프로세스 확인
################################################################################

echo "7️⃣  Slurm 프로세스 확인..."
echo "--------------------------------------------------------------------------------"

echo "  📍 Controller:"
slurm_processes=$(ps aux | grep -E "slurm(ctld|dbd)" | grep -v grep | wc -l)
if [ $slurm_processes -eq 0 ]; then
    echo -e "    ${GREEN}✅ Slurm 프로세스 없음 (정상 정지)${NC}"
else
    echo -e "    ${YELLOW}⚠️  $slurm_processes 개의 Slurm 프로세스 실행 중:${NC}"
    ps aux | grep -E "slurm(ctld|dbd)" | grep -v grep | awk '{print "      - " $11 " (PID: " $2 ")"}'
fi

echo ""
echo "  📍 Compute Nodes:"
for node in "${COMPUTE_NODES[@]}"; do
    node_name=$(echo $node | cut -d'@' -f2)
    echo -n "    $node_name: "

    slurmd_count=$(ssh -o ConnectTimeout=5 $node "ps aux | grep slurmd | grep -v grep | wc -l" 2>/dev/null || echo "0")
    if [ "$slurmd_count" -eq 0 ]; then
        echo -e "${GREEN}✅ slurmd 프로세스 없음${NC}"
    else
        echo -e "${YELLOW}⚠️  $slurmd_count 개의 slurmd 프로세스 실행 중${NC}"
    fi
done

echo ""
echo "================================================================================"
echo -e "${GREEN}✅ Slurm 서비스 정지 완료!${NC}"
echo "================================================================================"
echo ""
echo "💡 서비스 재시작:"
echo "  ./start_slurm_services.sh"
echo ""
echo "💡 서비스 상태 확인:"
echo "  sudo systemctl status slurmctld"
echo "  sudo systemctl status slurmdbd"
echo ""
