#!/bin/bash
################################################################################
# 통합 자동화 스크립트 - Slurm 23.11.x + cgroup v2 완전 지원
# Slurm 클러스터 + MPI + Apptainer + cgroup v2 완전 자동 설치
################################################################################

set -e  # 에러 발생시 중단

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

show_help() {
    cat << 'EOF'
================================================================================
🚀 Slurm 클러스터 통합 설치 스크립트 (온라인 버전)
================================================================================

사용법:
    ./setup_cluster_full.sh [옵션]

옵션:
    -h, --help      이 도움말 표시
    -c, --config    설정 파일 경로 지정 (기본값: my_multihead_cluster.yaml)
    -y, --yes       모든 확인 프롬프트에 자동 yes

설치 단계:
    Step 1:  사전 준비 (SSH 키, /etc/hosts)
    Step 2:  Python 가상환경 설정
    Step 3:  설정 파일 검증
    Step 4:  Munge 인증 설치 (컨트롤러)
    Step 5:  Slurm 23.11.x 컴파일 및 설치 (컨트롤러)
    Step 6:  Slurm 설정 파일 생성
    Step 7:  계산 노드에 Slurm 설치
    Step 8:  MPI 설치 (선택)
    Step 9:  설정 파일 배포
    Step 10: Slurm 서비스 시작
    Step 11: PATH 설정
    Step 12: cgroup v2 검증
    Step 13: 최종 검증

필수 조건:
    - Ubuntu 22.04 LTS
    - my_multihead_cluster.yaml 설정 파일
    - 인터넷 연결 (패키지 다운로드)
    - root 권한 (sudo)

설정 파일 필수 항목:
    nodes:
      controller:
        hostname: controller
        ip_address: 192.168.1.10
        ssh_user: admin
      compute_nodes:
        - hostname: node001
          ip_address: 192.168.1.11
          ssh_user: admin

    slurm:
      slurm_uid: 1001
      slurm_gid: 1001
      munge_uid: 1002
      munge_gid: 1002

예제:
    # 기본 실행 (대화형)
    ./setup_cluster_full.sh

    # 커스텀 설정 파일
    ./setup_cluster_full.sh -c /path/to/cluster.yaml

관련 스크립트:
    - setup_ssh_passwordless.sh  : SSH 키 설정 (Step 1 자동 호출)
    - setup_cluster_full_offline.sh : 오프라인 설치 버전

EOF
    exit 0
}

# 옵션 파싱
CONFIG_FILE="my_multihead_cluster.yaml"
AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -*)
            echo "❌ 알 수 없는 옵션: $1"
            echo "   사용법: ./setup_cluster_full.sh --help"
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

echo ""

################################################################################
# Step 2: 가상환경 활성화
################################################################################

echo "🐍 Step 2/11: Python 가상환경 확인..."
echo "--------------------------------------------------------------------------------"

if [ ! -d "venv" ]; then
    echo "⚠️  가상환경이 없습니다. 생성합니다..."
    python3 -m venv venv
fi

source venv/bin/activate
echo "✅ 가상환경 활성화 완료"
echo ""

################################################################################
# Step 3: 설정 검증
################################################################################

echo "🔍 Step 3/11: 설정 파일 검증..."
echo "--------------------------------------------------------------------------------"

if [ -f "validate_config.py" ]; then
    python3 validate_config.py my_multihead_cluster.yaml
    if [ $? -ne 0 ]; then
        echo "❌ 설정 파일 검증 실패"
        exit 1
    fi
    echo "✅ 설정 파일 검증 완료"
else
    echo "⚠️  validate_config.py가 없습니다. 건너뜁니다."
fi

echo ""

################################################################################
# Step 4: SSH 연결 테스트 및 자동 설정
################################################################################

echo "🔗 Step 4/11: SSH 연결 테스트 및 자동 설정..."
echo "--------------------------------------------------------------------------------"

# SSH 연결 테스트
if [ -f "test_connection.py" ]; then
    python3 test_connection.py my_multihead_cluster.yaml
    SSH_TEST_RESULT=$?

    if [ $SSH_TEST_RESULT -ne 0 ]; then
        echo "⚠️  SSH 연결 실패 - 자동 설정 시도 중..."
        echo ""

        # setup_ssh_passwordless.sh 자동 실행
        if [ -f "setup_ssh_passwordless.sh" ]; then
            echo "🔑 SSH 키 자동 설정 중..."
            chmod +x setup_ssh_passwordless.sh
            ./setup_ssh_passwordless.sh

            if [ $? -eq 0 ]; then
                echo ""
                echo "✅ SSH 키 설정 완료! 연결 재테스트 중..."
                python3 test_connection.py my_multihead_cluster.yaml

                if [ $? -eq 0 ]; then
                    echo "✅ SSH 연결 테스트 성공!"
                else
                    echo "❌ SSH 연결 여전히 실패"
                    echo "💡 수동으로 확인이 필요합니다:"
                    echo "   1. SSH 키 생성: ssh-keygen -t rsa -b 4096"
                    echo "   2. 공개키 복사: ssh-copy-id <user>@<node_ip>"
                    echo "   3. 연결 테스트: ssh <node_ip> 'hostname'"
                    exit 1
                fi
            else
                echo "❌ SSH 키 자동 설정 실패"
                echo "💡 수동으로 설정하세요: ./setup_ssh_passwordless.sh"
                exit 1
            fi
        else
            echo "❌ setup_ssh_passwordless.sh를 찾을 수 없습니다."
            echo "💡 수동으로 SSH 키를 설정하세요:"
            echo "   1. SSH 키 생성: ssh-keygen -t rsa -b 4096"
            echo "   2. 공개키 복사: ssh-copy-id <user>@<node_ip>"
            exit 1
        fi
    else
        echo "✅ SSH 연결 테스트 완료 (이미 설정됨)"
    fi
else
    echo "⚠️  test_connection.py가 없습니다."
    echo "   SSH 키가 설정되어 있는지 수동으로 확인하세요."
fi

echo ""

################################################################################
# Step 4.3: /etc/hosts 자동 설정 (YAML 기반)
################################################################################

echo "🌐 Step 4.3/11: /etc/hosts 자동 설정 (YAML 기반)..."
echo "--------------------------------------------------------------------------------"
echo "모든 노드의 /etc/hosts 파일을 my_multihead_cluster.yaml 기반으로 업데이트합니다."
echo "SSH 키 설정 및 호스트명 해석을 위해 필수입니다."
echo ""

if [ -f "complete_slurm_setup.py" ]; then
    echo "📝 complete_slurm_setup.py --only-hosts 실행 중..."
    echo "   (SSH 키 설정 + /etc/hosts 업데이트만 수행)"
    echo ""

    # --only-hosts: SSH 키 설정 및 /etc/hosts 업데이트만 수행
    python3 complete_slurm_setup.py --only-hosts

    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ SSH 키 및 /etc/hosts 설정 완료 (모든 노드)"
        echo ""

        # 검증: 각 노드에서 컨트롤러 호스트명 해석 확인
        echo "🔍 검증: 노드에서 컨트롤러 호스트명 해석 테스트..."

        mapfile -t COMPUTE_NODES < <(python3 << 'EOFPY'
import yaml
with open('my_multihead_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    print(f"{node['ssh_user']}@{node['ip_address']}:{node['hostname']}")
EOFPY
)

        CONTROLLER_HOSTNAME=$(python3 << 'EOFPY'
import yaml
with open('my_multihead_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
print(config['nodes']['controller']['hostname'])
EOFPY
)

        ALL_OK=true
        for node_info in "${COMPUTE_NODES[@]}"; do
            node_addr=$(echo "$node_info" | cut -d':' -f1)
            node_name=$(echo "$node_info" | cut -d':' -f2)

            if ssh -o ConnectTimeout=5 "$node_addr" "getent hosts $CONTROLLER_HOSTNAME" &>/dev/null; then
                echo "  ✅ $node_name: $CONTROLLER_HOSTNAME 해석 성공"
            else
                echo "  ❌ $node_name: $CONTROLLER_HOSTNAME 해석 실패"
                ALL_OK=false
            fi
        done

        if [ "$ALL_OK" = false ]; then
            echo ""
            echo "⚠️  일부 노드에서 호스트명 해석 실패"
            echo "💡 수동으로 확인하세요:"
            echo "   ssh 노드IP 'cat /etc/hosts | grep $CONTROLLER_HOSTNAME'"
        fi
    else
        echo ""
        echo "❌ /etc/hosts 설정 실패"
        echo "💡 수동으로 확인하세요:"
        echo "   - /etc/hosts 파일에 노드 IP/호스트명 추가"
        echo "   - SSH 키 설정: ssh-copy-id <user>@<node_ip>"
        echo ""
        echo "🔧 또는 수동으로 실행:"
        echo "   python3 complete_slurm_setup.py --only-hosts"
    fi
else
    echo "⚠️  complete_slurm_setup.py를 찾을 수 없습니다."
    echo "💡 수동으로 /etc/hosts를 설정하세요:"
    echo "   예: sudo bash -c 'echo \"<node_ip> <hostname>\" >> /etc/hosts'"
fi

echo ""

################################################################################
# Step 4.5: RebootProgram 설정 (YAML 기반 자동)
################################################################################

# YAML에 reboot_program이 정의되어 있으면 자동으로 설정
if [ -f "my_multihead_cluster.yaml" ] && grep -q "reboot_program:" my_multihead_cluster.yaml; then
    echo "🔄 Step 4.5/11: RebootProgram 자동 설정 (YAML 기반)..."
    echo "--------------------------------------------------------------------------------"
    echo "✅ YAML에 reboot_program 설정이 감지되었습니다."
    echo "   웹 대시보드에서 노드 재부팅 기능을 위한 환경을 설정합니다."
    echo ""
    
    if [ -f "./setup_reboot_program.sh" ]; then
        ./setup_reboot_program.sh
        
        if [ $? -eq 0 ]; then
            echo "✅ RebootProgram 설정 완료"
        else
            echo "⚠️  RebootProgram 설정 실패 (계속 진행)"
        fi
    else
        echo "⚠️  setup_reboot_program.sh를 찾을 수 없습니다."
        echo "   먼저 ./refactor_reboot_setup_to_yaml_fixed.sh를 실행하세요."
    fi
    
    echo ""
else
    echo "ℹ️  YAML에 reboot_program 설정이 없습니다 (웹 재부팅 기능 비활성화)"
    echo ""
fi


################################################################################
# Step 5: Munge 설치
################################################################################

echo "🔐 Step 5/11: Munge 인증 시스템 설치..."
echo "--------------------------------------------------------------------------------"
echo "Munge는 Slurm 노드 간 인증에 필수입니다."
echo ""

read -p "Munge를 자동 설치하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ -f "install_munge_auto.sh" ]; then
        chmod +x install_munge_auto.sh
        ./install_munge_auto.sh
        
        if [ $? -eq 0 ]; then
            echo "✅ Munge 자동 설치 완료"
        else
            echo "⚠️  Munge 자동 설치 실패 (계속 진행)"
        fi
    else
        echo "⚠️  install_munge_auto.sh가 없습니다."
        echo "💡 수동으로 Munge를 설치하세요."
    fi
else
    echo "⏭️  Munge 설치 건너뜀"
fi

echo ""

################################################################################
# Step 6: Slurm 23.11.x + cgroup v2 설치 (컨트롤러)
################################################################################

echo "🚀 Step 6/11: Slurm 23.11.x + cgroup v2 설치 (컨트롤러)..."
echo "--------------------------------------------------------------------------------"
echo "Slurm 23.11.10을 cgroup v2 완전 지원으로 설치합니다."
echo "(시간이 걸릴 수 있습니다 - 약 15-20분)"
echo ""

read -p "컨트롤러에 Slurm을 설치하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    chmod +x install_slurm_cgroup_v2.sh
    sudo bash install_slurm_cgroup_v2.sh
    
    if [ $? -eq 0 ]; then
        echo "✅ 컨트롤러 Slurm 설치 완료"
    else
        echo "❌ 컨트롤러 Slurm 설치 실패"
        exit 1
    fi
else
    echo "⏭️  컨트롤러 Slurm 설치 건너뜀"
fi

echo ""

################################################################################
# Step 6.1: systemd 서비스 파일 생성 (Type=notify)
################################################################################

echo "📝 Step 6.1/13: systemd 서비스 파일 생성..."
echo "--------------------------------------------------------------------------------"
echo "Slurm 공식 권장: Type=notify"
echo ""

if [ -f "create_slurm_systemd_services.sh" ]; then
    chmod +x create_slurm_systemd_services.sh
    sudo bash create_slurm_systemd_services.sh
    
    if [ $? -eq 0 ]; then
        echo "✅ systemd 서비스 파일 생성 완료"
    else
        echo "⚠️  systemd 서비스 파일 생성 실패 (계속 진행)"
    fi
else
    echo "⚠️  create_slurm_systemd_services.sh를 찾을 수 없습니다."
    echo "💡 기본 systemd 서비스를 사용합니다."
fi

echo ""

################################################################################
# Step 6.5: Slurm Accounting (slurmdbd) 설치
################################################################################

echo "🗄️  Step 6.5/13: Slurm Accounting (slurmdbd) 설치..."
echo "--------------------------------------------------------------------------------"
echo "slurmdbd는 Slurm의 Accounting 기능을 제공합니다."
echo "QoS (Quality of Service) 기능을 사용하려는 경우 필수입니다."
echo ""
echo "📌 QoS 기능:"
echo "  - 그룹별 CPU/메모리 제한"
echo "  - 작업 우선순위 관리"
echo "  - 리소스 사용량 추적"
echo "  - Dashboard Apply Configuration 기능"
echo ""
echo "⚠️  QoS가 필요없다면 건너뛸 수 있습니다."
echo "   (기본 Slurm 기능은 정상 작동합니다)"
echo ""

read -p "slurmdbd를 설치하시겠습니까? (권장: Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if [ -f "install_slurm_accounting.sh" ]; then
        chmod +x install_slurm_accounting.sh
        sudo bash install_slurm_accounting.sh

        if [ $? -eq 0 ]; then
            echo "✅ slurmdbd 설치 완료"
            SLURMDBD_INSTALLED=true

            echo ""
            echo "🔧 slurmdbd 환경 정리 중..."
            echo "--------------------------------------------------------------------------------"

            # 1. DbdHost 설정 수정 (localhost → 실제 호스트명)
            HOSTNAME=$(hostname -f)
            echo "📝 DbdHost를 '$HOSTNAME'으로 설정..."
            sudo sed -i "s/^DbdHost=localhost/DbdHost=$HOSTNAME/" /usr/local/slurm/etc/slurmdbd.conf

            # 2. 기존 slurmdbd 프로세스 완전 정리
            echo "🧹 기존 slurmdbd 프로세스 정리..."
            sudo systemctl stop slurmdbd 2>/dev/null || true
            sleep 2

            # 남아있는 프로세스 강제 종료
            sudo pkill -9 slurmdbd 2>/dev/null || true
            sleep 1

            # PID 파일 정리
            sudo rm -f /run/slurm/slurmdbd.pid /var/run/slurm/slurmdbd.pid 2>/dev/null || true

            # 3. systemd 서비스 재시작
            echo "🔄 slurmdbd 서비스 재시작..."
            sudo systemctl daemon-reload
            sudo systemctl enable slurmdbd
            sudo systemctl start slurmdbd

            # 4. 초기화 대기
            echo "⏱️  slurmdbd 초기화 대기 중 (10초)..."
            sleep 10

            # 5. 상태 확인
            if sudo systemctl is-active --quiet slurmdbd; then
                echo "✅ slurmdbd 정상 시작 완료"
            else
                echo "❌ slurmdbd 시작 실패"
                echo ""
                echo "🔍 로그 확인:"
                sudo journalctl -u slurmdbd -n 20 --no-pager
                echo ""
                echo "또는:"
                echo "   sudo tail -50 /var/log/slurm/slurmdbd.log"
                SLURMDBD_INSTALLED=false
            fi
        else
            echo "⚠️  slurmdbd 설치 실패"
            echo "   QoS 기능을 사용할 수 없지만, 기본 Slurm은 정상 작동합니다."
            SLURMDBD_INSTALLED=false
        fi
    else
        echo "⚠️  install_slurm_accounting.sh를 찾을 수 없습니다."
        echo "💡 수동으로 slurmdbd를 설치하세요."
        SLURMDBD_INSTALLED=false
    fi
else
    echo "⏭️  slurmdbd 설치 건너뛰 (QoS 기능 비활성화)"
    SLURMDBD_INSTALLED=false
fi

echo ""

################################################################################
# Step 7: 계산 노드에 Slurm 설치
################################################################################

echo "📦 Step 7/14: 계산 노드에 Slurm 23.11.x 설치..."
echo "--------------------------------------------------------------------------------"

# my_multihead_cluster.yaml에서 모든 compute_nodes 읽기 (viz 노드 포함)
# 형식: ip|ssh_user|hostname
mapfile -t COMPUTE_NODE_INFO < <(python3 << 'EOFPY'
import yaml
with open('my_multihead_cluster.yaml', 'r') as f:
    config = yaml.safe_load(f)
for node in config['nodes']['compute_nodes']:
    ip = node.get('ip_address', '')
    user = node.get('ssh_user', 'root')
    hostname = node.get('hostname', '')
    print(f"{ip}|{user}|{hostname}")
EOFPY
)

echo "📋 검색된 계산 노드 (viz 노드 포함):"
for info in "${COMPUTE_NODE_INFO[@]}"; do
    IFS='|' read -r node_ip ssh_user hostname <<< "$info"
    echo "  - $hostname ($node_ip) - user: $ssh_user"
done
echo ""

read -p "계산 노드에 Slurm을 설치하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    for info in "${COMPUTE_NODE_INFO[@]}"; do
        IFS='|' read -r node_ip ssh_user hostname <<< "$info"
        echo ""
        echo "📦 $hostname ($node_ip): Slurm 설치 중..."

        # 스크립트 복사
        scp install_slurm_cgroup_v2.sh ${ssh_user}@${node_ip}:/tmp/

        # 원격 실행
        ssh ${ssh_user}@${node_ip} "cd /tmp && sudo bash install_slurm_cgroup_v2.sh"

        if [ $? -eq 0 ]; then
            echo "✅ $hostname: Slurm 설치 완료"
        else
            echo "⚠️  $hostname: Slurm 설치 실패 (계속 진행)"
        fi
    done
    
    echo ""
    echo "✅ 모든 계산 노드 Slurm 설치 완료"

################################################################################
# Step 7.5: 원격 노드 systemd 서비스 설정
################################################################################

echo "📤 Step 7.5/14: 원격 노드 systemd 서비스 설정..."
echo "--------------------------------------------------------------------------------"

read -p "원격 노드에 systemd 서비스를 설정하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    for info in "${COMPUTE_NODE_INFO[@]}"; do
        IFS='|' read -r node_ip ssh_user hostname <<< "$info"
        echo ""
        echo "📤 $hostname ($node_ip): systemd 서비스 설정 중..."

        # setup_slurmd_service_remote.sh 복사 및 실행
        if [ -f "setup_slurmd_service_remote.sh" ]; then
            scp setup_slurmd_service_remote.sh ${ssh_user}@${node_ip}:/tmp/
            # Run without TTY allocation (non-interactive mode)
            timeout 60 ssh -o ConnectTimeout=10 ${ssh_user}@${node_ip} "cd /tmp && sudo bash setup_slurmd_service_remote.sh" || {
                echo "⚠️  $hostname: 타임아웃 - 수동 확인 필요"
            }

            if [ $? -eq 0 ]; then
                echo "✅ $hostname: systemd 서비스 설정 완료"
            else
                echo "⚠️  $hostname: systemd 서비스 설정 실패"
            fi
        else
            echo "⚠️  setup_slurmd_service_remote.sh 파일이 없습니다"
            echo "     이 파일은 다음을 자동화합니다:"
            echo "     - /run/slurm 디렉토리 생성"
            echo "     - slurmd.service 파일 생성 (root 실행)"
            echo "     - systemd daemon-reload 및 enable"
        fi
    done

    echo ""
    echo "✅ systemd 서비스 설정 완료"
else
    echo "⏭️  systemd 서비스 설정 건너뜀"
fi

echo ""

else
    echo "⏭️  계산 노드 Slurm 설치 건너뜀"
fi

echo ""

################################################################################
# Step 8: Slurm 설정 파일 생성 (cgroup v2)
################################################################################

echo "🔧 Step 8/14: Slurm 설정 파일 생성 (cgroup v2 지원)..."
echo "--------------------------------------------------------------------------------"

read -p "Slurm 설정 파일을 생성하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    chmod +x configure_slurm_from_yaml.py
    python3 configure_slurm_from_yaml.py
        echo "  💡 YAML 기반 동적 설정 생성 사용"
    
    if [ $? -eq 0 ]; then
        echo "✅ Slurm 설정 파일 생성 완료"
    else
        echo "❌ 설정 파일 생성 실패"
        exit 1
    fi
else
    echo "⏭️  설정 파일 생성 건너뜀"
fi

echo ""

################################################################################
# Step 9: 설정 파일을 계산 노드에 배포
################################################################################

echo "📤 Step 9/14: 설정 파일을 계산 노드에 배포..."
echo "--------------------------------------------------------------------------------"

read -p "설정 파일을 계산 노드에 배포하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    for info in "${COMPUTE_NODE_INFO[@]}"; do
        IFS='|' read -r node_ip ssh_user hostname <<< "$info"
        echo ""
        echo "📤 $hostname ($node_ip): 설정 파일 복사 중..."

        # slurm.conf 복사
        scp /usr/local/slurm/etc/slurm.conf ${ssh_user}@${node_ip}:/tmp/
        ssh ${ssh_user}@${node_ip} "sudo mv /tmp/slurm.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/slurm.conf"

        # cgroup.conf 복사
        scp /usr/local/slurm/etc/cgroup.conf ${ssh_user}@${node_ip}:/tmp/
        ssh ${ssh_user}@${node_ip} "sudo mv /tmp/cgroup.conf /usr/local/slurm/etc/ && sudo chown slurm:slurm /usr/local/slurm/etc/cgroup.conf"

        # systemd 서비스 파일 복사
        scp /etc/systemd/system/slurmd.service ${ssh_user}@${node_ip}:/tmp/
        ssh ${ssh_user}@${node_ip} "sudo mv /tmp/slurmd.service /etc/systemd/system/ && sudo systemctl daemon-reload"

        echo "✅ $hostname: 설정 파일 배포 완료"
    done
    
    echo ""
    echo "✅ 모든 노드에 설정 파일 배포 완료"
else
    echo "⏭️  설정 파일 배포 건너뜀"
fi

echo ""

################################################################################
# Step 10: Slurm 서비스 시작
################################################################################

echo "▶️  Step 10/14: Slurm 서비스 시작..."
echo "--------------------------------------------------------------------------------"

read -p "Slurm 서비스를 시작하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # 컨트롤러
    echo ""
    echo "🔧 컨트롤러: slurmctld 시작 중..."
    sudo systemctl enable slurmctld

    # Stop first to avoid "Address already in use" error
    sudo systemctl stop slurmctld 2>/dev/null || true
    sleep 1
    sudo systemctl start slurmctld

    sleep 3

    if sudo systemctl is-active --quiet slurmctld; then
        echo "✅ slurmctld 시작 성공"
    else
        echo "❌ slurmctld 시작 실패"
        sudo systemctl status slurmctld --no-pager
    fi
    
    # 계산 노드
    for info in "${COMPUTE_NODE_INFO[@]}"; do
        IFS='|' read -r node_ip ssh_user hostname <<< "$info"
        echo ""
        echo "🔧 $hostname ($node_ip): slurmd 시작 중..."

        # Stop first, then start (avoid restart timeout issues)
        timeout 60 ssh -o ConnectTimeout=10 ${ssh_user}@${node_ip} "sudo systemctl enable slurmd && sudo systemctl stop slurmd 2>/dev/null || true && sleep 1 && sudo systemctl start slurmd" || { echo "⚠️  $hostname: 타임아웃 - 수동 확인 필요"; }

        sleep 2

        if ssh ${ssh_user}@${node_ip} "sudo systemctl is-active --quiet slurmd"; then
            echo "✅ $hostname: slurmd 시작 성공"
        else
            echo "⚠️  $hostname: slurmd 시작 실패"
            ssh ${ssh_user}@${node_ip} "sudo systemctl status slurmd --no-pager"
        fi
    done
    
    echo ""
    echo "✅ Slurm 서비스 시작 완료"
else
    echo "⏭️  서비스 시작 건너뜀"
fi

echo ""

################################################################################
# Step 11: PATH 영구 설정 및 확인
################################################################################

echo "🛤️  Step 11/14: PATH 영구 설정 및 확인..."
echo "--------------------------------------------------------------------------------"

# /etc/profile.d/slurm.sh 확인
if [ -f "/etc/profile.d/slurm.sh" ]; then
    echo "✅ /etc/profile.d/slurm.sh 파일 존재"
else
    echo "⚠️  /etc/profile.d/slurm.sh 파일이 없습니다. 생성합니다..."
    sudo tee /etc/profile.d/slurm.sh > /dev/null << 'SLURM_PATH_EOF'
# Slurm Environment
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
export MANPATH=/usr/local/slurm/share/man:$MANPATH
SLURM_PATH_EOF
    sudo chmod 644 /etc/profile.d/slurm.sh
    echo "✅ /etc/profile.d/slurm.sh 파일 생성 완료"
fi

echo ""

# 현재 터미널에 PATH 적용
echo "⚡ 현재 터미널에 PATH 적용 중..."
source /etc/profile.d/slurm.sh 2>/dev/null || export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
echo "✅ PATH 적용 완료"

echo ""

# 사용자별 .bashrc 업데이트 (선택)
if ! grep -q "slurm.sh" ~/.bashrc 2>/dev/null && ! grep -q "/usr/local/slurm/bin" ~/.bashrc 2>/dev/null; then
    echo "📝 사용자 ~/.bashrc 업데이트..."
    read -p "~/.bashrc에 Slurm PATH를 추가하시겠습니까? (권장) (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "" >> ~/.bashrc
        echo "# Slurm PATH (added by setup_cluster_full.sh)" >> ~/.bashrc
        echo "source /etc/profile.d/slurm.sh 2>/dev/null || export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:\$PATH" >> ~/.bashrc
        echo "✅ ~/.bashrc 업데이트 완료"
    else
        echo "⏭️  ~/.bashrc 업데이트 건너뜀"
    fi
else
    echo "✅ ~/.bashrc에 이미 Slurm PATH가 설정되어 있습니다"
fi

echo ""

# 명령어 확인
echo "🧪 Slurm 명령어 확인..."
COMMANDS_OK=true

for cmd in sinfo squeue sbatch srun scancel; do
    if command -v "$cmd" &> /dev/null; then
        echo "  ✅ $cmd"
    else
        echo "  ❌ $cmd (not found)"
        COMMANDS_OK=false
    fi
done

echo ""

if [ "$COMMANDS_OK" = true ]; then
    echo "✅ 모든 Slurm 명령어가 정상적으로 설정되었습니다!"
    
    # 버전 확인
    if command -v sinfo &> /dev/null; then
        VERSION=$(sinfo --version 2>/dev/null | head -1)
        if [ -n "$VERSION" ]; then
            echo "📊 $VERSION"
        fi
    fi
else
    echo "⚠️  일부 명령어를 찾을 수 없습니다."
    echo "   현재 터미널에서 사용하려면: source /etc/profile.d/slurm.sh"
    echo "   새 터미널을 열면 자동으로 로드됩니다."
fi

echo ""

################################################################################
# Step 12: MPI 설치 (선택)
################################################################################

echo "📦 Step 12/14: MPI 라이브러리 설치 (선택)..."
echo "--------------------------------------------------------------------------------"

read -p "MPI 라이브러리를 설치하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f "install_mpi.py" ]; then
        python3 install_mpi.py
        if [ $? -eq 0 ]; then
            echo "✅ MPI 설치 완료"
        else
            echo "⚠️  MPI 설치 실패"
        fi
    else
        echo "⚠️  install_mpi.py가 없습니다."
    fi
else
    echo "⏭️  MPI 설치 건너뜀"
fi

echo ""

################################################################################
# 완료 및 검증
################################################################################


echo "================================================================================"
echo "🎉 Slurm 23.11.x + cgroup v2 설치 완료!"

echo "================================================================================"
echo ""

sleep 3

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

echo "🔍 클러스터 상태 확인..."
echo ""

if command -v sinfo &> /dev/null; then
    echo "📊 노드 상태:"
    sinfo || true
    echo ""
    
    echo "📋 노드 상세 정보:"
    sinfo -N || true
    echo ""
else
    echo "⚠️  sinfo 명령을 찾을 수 없습니다"
    echo "   PATH를 설정하세요: source /etc/profile.d/slurm.sh"
fi

echo ""

echo "================================================================================"
echo "📋 다음 단계"

echo "================================================================================"
echo ""
echo "🚀 서비스가 실행 중이 아니라면:"
echo "   ./start_slurm_cluster.sh"
echo ""
echo "🛑 서비스를 중지하려면:"
echo "   ./stop_slurm_cluster.sh"
echo ""
echo "1️⃣  Slurm 명령어 사용 (이미 설정됨):"
echo "   sinfo              # 클러스터 상태 확인"
echo "   squeue             # 작업 큐 확인"
echo "   sbatch test.sh     # 작업 제출"
echo ""
echo "   만약 명령어가 안 되면:"
echo "   source /etc/profile.d/slurm.sh"
echo "   또는 새 터미널을 여세요"
echo ""
echo "2️⃣  노드가 DOWN 상태라면 활성화:"
echo "   scontrol update NodeName=node001 State=RESUME"
echo "   scontrol update NodeName=node002 State=RESUME"
echo ""
echo "3️⃣  cgroup v2 작동 확인:"
echo "   mount | grep cgroup2"
echo "   /usr/local/slurm/sbin/slurmd -V | grep systemd"
echo ""
echo "4️⃣  테스트 Job 제출:"
echo "   cat > test_job.sh <<'EOF'"
echo "   #!/bin/bash"
echo "   #SBATCH --job-name=cgroup_test"
echo "   #SBATCH --output=test_%j.out"
echo "   #SBATCH --cpus-per-task=2"
echo "   #SBATCH --mem=1G"
echo "   echo 'Testing cgroup v2...'"
echo "   echo 'CPUs: '\$SLURM_CPUS_PER_TASK"
echo "   echo 'Memory: '\$SLURM_MEM_PER_NODE' MB'"
echo "   cat /proc/self/cgroup"
echo "   EOF"
echo ""
echo "   sbatch test_job.sh"
echo "   squeue"
echo ""
echo "5️⃣  리소스 제한 테스트 (메모리):"
echo "   cat > mem_test.sh <<'EOF'"
echo "   #!/bin/bash"
echo "   #SBATCH --mem=512M"
echo "   # 1GB 할당 시도 (512MB 제한에 걸려 종료됨)"
echo "   python3 -c 'x=[0]*(1024**3//8); import time; time.sleep(5)'"
echo "   EOF"
echo ""
echo "   sbatch mem_test.sh  # cgroup이 정상이면 메모리 초과로 종료"
echo ""
echo "6️⃣  Dashboard 실시간 모니터링:"
echo "   cd dashboard/backend"
echo "   export MOCK_MODE=false"
echo "   python app.py"
echo ""
echo "   # 브라우저: http://localhost:3000"
echo "   # Save/Load → Sync Nodes from Slurm"
echo ""

echo "================================================================================"
echo ""
echo "✨ cgroup v2 주요 기능:"
echo "  ✅ CPU 코어 제한 - 할당된 CPU만 사용"
echo "  ✅ 메모리 제한 - 초과 시 자동 종료"
echo "  ✅ CPU 친화성 - 특정 코어에 고정"
echo "  ✅ 실시간 모니터링 - Dashboard 연동"
echo ""
echo "📚 상세 가이드:"
echo "  cat CGROUP_V2_INSTALLATION_GUIDE.md"
echo ""
echo "🔗 문서:"
echo "  - Slurm cgroup: https://slurm.schedmd.com/cgroup.html"
echo "  - Dashboard: cat dashboard/SLURM_INTEGRATION_GUIDE.md"
echo ""

################################################################################
# Step 13: Apptainer 이미지 동기화 (선택)
################################################################################

echo "🐳 Step 13/14: Apptainer 이미지 동기화 (선택)..."
echo "--------------------------------------------------------------------------------"
echo "apptainers/ 디렉토리의 .def 및 .sif 파일을"
echo "모든 계산 노드의 /scratch/apptainers/로 복사합니다."
echo ""

if [ -d "apptainers" ]; then
    # .def 및 .sif 파일 개수 확인
    local_def_count=$(find apptainers -type f -name "*.def" 2>/dev/null | wc -l)
    local_sif_count=$(find apptainers -type f -name "*.sif" 2>/dev/null | wc -l)
    
    if [ $local_def_count -gt 0 ] || [ $local_sif_count -gt 0 ]; then
        echo "📦 발견된 파일:"
        echo "   - Definition 파일 (.def): $local_def_count"
        echo "   - Image 파일 (.sif): $local_sif_count"
        echo ""
        
        read -p "Apptainer 이미지를 계산 노드에 동기화하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ -f "sync_apptainers_to_nodes.sh" ]; then
                chmod +x sync_apptainers_to_nodes.sh
                ./sync_apptainers_to_nodes.sh
                
                if [ $? -eq 0 ]; then
                    echo "✅ Apptainer 이미지 동기화 완료"
                else
                    echo "⚠️  Apptainer 이미지 동기화 실패"
                fi
            else
                echo "⚠️  sync_apptainers_to_nodes.sh를 찾을 수 없습니다."
            fi
        else
            echo "⏭️  Apptainer 이미지 동기화 건너뜀"
            echo "   나중에 수동으로 실행: ./sync_apptainers_to_nodes.sh"
        fi
    else
        echo "ℹ️  apptainers/ 디렉토리에 파일이 없습니다."
        echo "   .def 또는 .sif 파일을 추가한 후:"
        echo "   ./sync_apptainers_to_nodes.sh"
    fi
else
    echo "⚠️  apptainers/ 디렉토리가 없습니다."
fi

echo ""

################################################################################
# Step 12: Apptainer 배포 (선택적)
################################################################################

echo "📦 Step 12/12: Apptainer 바이너리 및 이미지 배포..."
echo "--------------------------------------------------------------------------------"
echo ""
echo "Apptainer를 모든 노드에 배포하시겠습니까?"
echo "  - Apptainer 바이너리 (로컬 빌드) 설치"
echo "  - 노드 타입별 컨테이너 이미지 로컬 복사"
echo "  - 네트워크 병목 방지 (각 노드 로컬 디스크 사용)"
echo ""
read -p "배포 하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f "deploy_apptainers.sh" ]; then
        chmod +x deploy_apptainers.sh
        echo "🚀 Apptainer 배포 시작..."
        ./deploy_apptainers.sh

        if [ $? -eq 0 ]; then
            echo "✅ Apptainer 배포 완료"
        else
            echo "⚠️  Apptainer 배포 중 일부 실패"
            echo "   나중에 수동으로 실행: ./deploy_apptainers.sh"
        fi
    else
        echo "❌ deploy_apptainers.sh를 찾을 수 없습니다."
    fi
else
    echo "⏭️  Apptainer 배포 건너뜀"
    echo "   나중에 수동으로 실행:"
    echo "     ./deploy_apptainers.sh           # 전체 배포"
    echo "     ./deploy_apptainers.sh --update  # 이미지만 업데이트"
fi

echo ""

echo "================================================================================"
echo ""
echo "🎊 완료! Happy Computing with cgroup v2! 🚀"
echo ""
