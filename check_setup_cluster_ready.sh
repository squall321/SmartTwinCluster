#!/bin/bash

echo "=========================================="
echo "🔍 setup_cluster_full.sh 준비 상태 점검"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ISSUES=()

################################################################################
# 1. install_slurm_accounting.sh 확인
################################################################################

echo "1️⃣  install_slurm_accounting.sh 확인..."
echo "----------------------------------------"

if [ -f "install_slurm_accounting.sh" ]; then
    echo "   ✅ 파일 존재"
    
    # Type=notify 확인
    if grep -q "Type=notify" install_slurm_accounting.sh; then
        echo "   ✅ slurmdbd Type=notify (공식 권장)"
    else
        echo "   ❌ slurmdbd Type이 notify가 아님"
        ISSUES+=("install_slurm_accounting.sh의 Type을 notify로 수정 필요")
    fi
    
    # MariaDB 최적화 확인
    if grep -q "innodb_buffer_pool_size" install_slurm_accounting.sh; then
        echo "   ✅ MariaDB 최적화 포함"
    else
        echo "   ⚠️  MariaDB 최적화 없음 (권장)"
    fi
else
    echo "   ❌ 파일 없음"
    ISSUES+=("install_slurm_accounting.sh 파일이 없음")
fi

echo ""

################################################################################
# 2. install_slurm_cgroup_v2.sh 확인
################################################################################

echo "2️⃣  install_slurm_cgroup_v2.sh 확인..."
echo "----------------------------------------"

if [ -f "install_slurm_cgroup_v2.sh" ]; then
    echo "   ✅ 파일 존재"
    
    # systemd 서비스 파일 생성 확인
    if grep -q "systemd.*service" install_slurm_cgroup_v2.sh; then
        echo "   ⚠️  systemd 서비스 파일 생성 포함"
    else
        echo "   ℹ️  systemd 서비스 파일 생성 없음 (별도 스크립트 필요)"
    fi
else
    echo "   ❌ 파일 없음"
    ISSUES+=("install_slurm_cgroup_v2.sh 파일이 없음")
fi

echo ""

################################################################################
# 3. setup_cluster_full.sh 확인
################################################################################

echo "3️⃣  setup_cluster_full.sh 확인..."
echo "----------------------------------------"

if [ -f "setup_cluster_full.sh" ]; then
    echo "   ✅ 파일 존재"
    
    # Step 6.5 확인
    if grep -q "Step 6.5" setup_cluster_full.sh; then
        echo "   ✅ Step 6.5 (slurmdbd) 추가됨"
    else
        echo "   ❌ Step 6.5 없음"
        ISSUES+=("setup_cluster_full.sh에 Step 6.5 추가 필요")
    fi
    
    # install_slurm_accounting.sh 호출 확인
    if grep -q "install_slurm_accounting.sh" setup_cluster_full.sh; then
        echo "   ✅ install_slurm_accounting.sh 호출"
    else
        echo "   ❌ install_slurm_accounting.sh 호출 없음"
        ISSUES+=("Step 6.5에서 install_slurm_accounting.sh 호출 필요")
    fi
    
    # systemd 서비스 생성 확인
    if grep -q "create_slurm_systemd_services" setup_cluster_full.sh; then
        echo "   ✅ systemd 서비스 생성 포함"
    else
        echo "   ⚠️  systemd 서비스 생성 없음"
        ISSUES+=("Step 6 이후 systemd 서비스 생성 추가 권장")
    fi
    
    # SSH 타임아웃 확인
    if grep -q "timeout.*ssh" setup_cluster_full.sh; then
        echo "   ✅ SSH 타임아웃 설정"
    else
        echo "   ⚠️  SSH 타임아웃 없음 (권장)"
    fi
else
    echo "   ❌ 파일 없음"
    ISSUES+=("setup_cluster_full.sh 파일이 없음")
fi

echo ""

################################################################################
# 4. create_slurm_systemd_services.sh 확인
################################################################################

echo "4️⃣  create_slurm_systemd_services.sh 확인..."
echo "----------------------------------------"

if [ -f "create_slurm_systemd_services.sh" ]; then
    echo "   ✅ 파일 존재"
    
    if grep -q "Type=notify" create_slurm_systemd_services.sh; then
        echo "   ✅ Type=notify 설정"
    fi
else
    echo "   ❌ 파일 없음"
    ISSUES+=("create_slurm_systemd_services.sh 파일이 없음")
fi

echo ""

################################################################################
# 5. 현재 시스템 상태 확인
################################################################################

echo "5️⃣  현재 시스템 상태 확인..."
echo "----------------------------------------"

# slurmctld
if sudo systemctl is-active --quiet slurmctld 2>/dev/null; then
    echo "   ✅ slurmctld 실행 중"
    
    # Type 확인
    TYPE=$(sudo systemctl show slurmctld -p Type --value 2>/dev/null)
    if [ "$TYPE" = "notify" ]; then
        echo "      ✅ Type=notify"
    else
        echo "      ⚠️  Type=$TYPE (notify 권장)"
    fi
else
    echo "   ℹ️  slurmctld 미실행 (정상, 아직 설치 안했을 수 있음)"
fi

# slurmdbd
if sudo systemctl is-active --quiet slurmdbd 2>/dev/null; then
    echo "   ✅ slurmdbd 실행 중"
    
    TYPE=$(sudo systemctl show slurmdbd -p Type --value 2>/dev/null)
    if [ "$TYPE" = "notify" ]; then
        echo "      ✅ Type=notify"
    else
        echo "      ⚠️  Type=$TYPE (notify 권장)"
    fi
else
    echo "   ℹ️  slurmdbd 미실행"
fi

# slurmd (원격) - YAML에서 노드 정보 읽기
CONFIG_FILE="${1:-my_multihead_cluster.yaml}"
if [ -f "$CONFIG_FILE" ] && python3 -c "import yaml" 2>/dev/null; then
    while IFS='|' read -r node_ip ssh_user hostname; do
        if timeout 5 ssh -o ConnectTimeout=5 -o BatchMode=yes ${ssh_user}@${node_ip} "sudo systemctl is-active --quiet slurmd" 2>/dev/null; then
            echo "   ✅ $hostname ($node_ip): slurmd 실행 중"

            TYPE=$(timeout 5 ssh -o BatchMode=yes ${ssh_user}@${node_ip} "sudo systemctl show slurmd -p Type --value" 2>/dev/null)
            if [ "$TYPE" = "notify" ]; then
                echo "      ✅ Type=notify"
            else
                echo "      ⚠️  Type=$TYPE (notify 권장)"
            fi
        else
            echo "   ℹ️  $hostname ($node_ip): slurmd 미실행 또는 연결 불가"
        fi
    done < <(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
for n in c.get('nodes',{}).get('compute_nodes',[]):
    print(f\"{n.get('ip_address')}|{n.get('ssh_user','root')}|{n.get('hostname')}\")
")
else
    echo "   ⚠️  YAML 설정 파일 없음 - 원격 노드 점검 건너뜀"
fi

echo ""

################################################################################
# 결과 요약
################################################################################

echo "=========================================="
echo "📋 점검 결과"
echo "=========================================="
echo ""

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo "✅ 모든 점검 통과!"
    echo ""
    echo "setup_cluster_full.sh를 실행할 준비가 되었습니다."
    echo ""
    echo "실행 방법:"
    echo "  ./setup_cluster_full.sh"
    echo ""
else
    echo "⚠️  해결해야 할 문제: ${#ISSUES[@]}개"
    echo ""
    for i in "${!ISSUES[@]}"; do
        echo "$((i+1)). ${ISSUES[$i]}"
    done
    echo ""
    echo "수정 필요한 사항이 있습니다."
fi

echo ""

################################################################################
# 권장 수정 사항
################################################################################

if [ ${#ISSUES[@]} -gt 0 ]; then
    echo "=========================================="
    echo "🔧 권장 수정 방법"
    echo "=========================================="
    echo ""
    
    if [[ " ${ISSUES[@]} " =~ "systemd 서비스 생성" ]]; then
        echo "1. setup_cluster_full.sh에 systemd 서비스 생성 추가:"
        echo "   Step 6 (Slurm 설치) 이후에 다음 추가:"
        echo ""
        echo "   if [ -f \"create_slurm_systemd_services.sh\" ]; then"
        echo "       chmod +x create_slurm_systemd_services.sh"
        echo "       sudo ./create_slurm_systemd_services.sh"
        echo "   fi"
        echo ""
    fi
    
    if [[ " ${ISSUES[@]} " =~ "Type을 notify로" ]]; then
        echo "2. install_slurm_accounting.sh의 Type 수정:"
        echo "   이미 수정 스크립트 있음 (재실행 필요 없음)"
        echo ""
    fi
fi

echo ""
