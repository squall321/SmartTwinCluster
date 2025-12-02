#!/bin/bash
################################################################################
# SSH 키 기반 인증 자동 설정
# 한 번만 설정하면 비밀번호 입력 없이 SSH 접속 가능
################################################################################

show_help() {
    cat << 'EOF'
================================================================================
🔑 SSH 키 기반 인증 자동 설정 스크립트
================================================================================

사용법:
    ./setup_ssh_passwordless.sh [옵션] [CONFIG_FILE]

옵션:
    -h, --help      이 도움말 표시
    -c, --config    설정 파일 경로 지정 (기본값: my_cluster.yaml)

예제:
    # 기본 설정 파일 사용
    ./setup_ssh_passwordless.sh

    # 커스텀 설정 파일 사용
    ./setup_ssh_passwordless.sh my_custom_cluster.yaml
    ./setup_ssh_passwordless.sh -c /path/to/cluster.yaml

기능:
    1. SSH 키 생성 (없는 경우 자동 생성)
    2. 모든 노드에 공개키 복사 (ssh-copy-id)
    3. /etc/hosts 파일 업데이트 (모든 노드에 배포)
    4. NOPASSWD sudoers 설정 (클러스터 관리 명령용)

필수 조건:
    - my_cluster.yaml (또는 지정된 설정 파일)
    - Python3 + PyYAML
    - 모든 노드에 동일한 SSH 비밀번호 (최초 1회만 입력)

설정 파일 예시 (my_cluster.yaml):
    nodes:
      controller:
        hostname: controller
        ip_address: 192.168.1.10
        ssh_user: admin
      compute_nodes:
        - hostname: node001
          ip_address: 192.168.1.11
          ssh_user: admin

    # 선택적: SSH 비밀번호 (입력 생략 가능)
    cluster_info:
      ssh_password: your_password_here

EOF
    exit 0
}

# 옵션 파싱
CONFIG_FILE="my_cluster.yaml"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -*)
            echo "❌ 알 수 없는 옵션: $1"
            echo "   사용법: ./setup_ssh_passwordless.sh --help"
            exit 1
            ;;
        *)
            # 위치 인자로 설정 파일 지정
            CONFIG_FILE="$1"
            shift
            ;;
    esac
done

echo "================================================================================"
echo "🔑 SSH 키 기반 인증 자동 설정"
echo "================================================================================"
echo ""
echo "💡 이 스크립트를 실행하면:"
echo "   - SSH 키 생성 (없는 경우)"
echo "   - 모든 노드에 공개키 복사"
echo "   - 이후 비밀번호 입력 없이 SSH 접속 가능"
echo ""
echo "📋 설정 파일: $CONFIG_FILE"
echo ""

# YAML에서 노드 정보 읽기
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    exit 1
fi

echo "📝 $CONFIG_FILE에서 노드 정보 읽는 중..."
echo ""

# Python으로 노드 목록 추출 (multi-head와 single-head 모두 지원)
NODES=$(CONFIG_FILE="$CONFIG_FILE" python3 << 'EOFPY'
import yaml
import os

config_file = os.environ.get('CONFIG_FILE', 'my_cluster.yaml')

with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

nodes_config = config['nodes']

# Use dict to deduplicate by hostname (first occurrence wins)
nodes_dict = {}

# Support both single-head (controller) and multi-head (controllers) formats
if 'controllers' in nodes_config and isinstance(nodes_config['controllers'], list):
    # Multi-head format: all controllers
    for node in nodes_config['controllers']:
        ssh_user = node['ssh_user']
        ip = node['ip_address']
        hostname = node['hostname']
        if hostname not in nodes_dict:
            nodes_dict[hostname] = f"{ssh_user}@{ip}#{hostname}"
elif 'controller' in nodes_config:
    # Single-head format: single controller
    controller = nodes_config['controller']
    ssh_user = controller['ssh_user']
    ip = controller['ip_address']
    hostname = controller['hostname']
    if hostname not in nodes_dict:
        nodes_dict[hostname] = f"{ssh_user}@{ip}#{hostname}"

# 계산 노드
for node in nodes_config['compute_nodes']:
    ssh_user = node['ssh_user']
    ip = node['ip_address']
    hostname = node['hostname']
    if hostname not in nodes_dict:
        nodes_dict[hostname] = f"{ssh_user}@{ip}#{hostname}"

# Print all unique nodes
for node_info in nodes_dict.values():
    print(node_info)
EOFPY
)

if [ -z "$NODES" ]; then
    echo "❌ 노드 정보를 읽을 수 없습니다!"
    exit 1
fi

echo "📋 설정할 노드 목록:"
NODE_COUNT=0
echo "$NODES" | while IFS='#' read -r user_ip hostname; do
    echo "  - $hostname ($user_ip)"
done
NODE_COUNT=$(echo "$NODES" | wc -l)
echo ""
echo "총 ${NODE_COUNT}개 노드"
echo ""

# SSH 키 확인 및 생성 (먼저!)
SSH_KEY="$HOME/.ssh/id_rsa"

# ~/.ssh 디렉토리 확인 및 생성
if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 SSH 키가 없습니다. 새로 생성합니다..."
    echo ""

    # 비밀번호 없는 키로 자동 생성 (권장)
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -C "slurm-cluster-key" -N ""

    if [ $? -eq 0 ]; then
        echo "✅ SSH 키 생성 완료: $SSH_KEY"
    else
        echo "❌ SSH 키 생성 실패!"
        exit 1
    fi
else
    echo "✅ 기존 SSH 키 사용: $SSH_KEY"
fi

echo ""

################################################################################
# sshpass 설정 - 비밀번호 한 번만 입력
################################################################################

# sshpass 설치 확인
USE_SSHPASS=false

# SSH 키가 이미 모든 노드에 배포되어 있는지 확인
echo "🔍 기존 SSH 키 배포 상태 확인 중..."
NEEDS_PASSWORD=false
NODES_WITHOUT_KEY=0

# 모든 노드 체크 (최대 5개만 빠르게 테스트)
while IFS='#' read -r test_user_ip test_hostname; do
    if ! ssh -o BatchMode=yes -o ConnectTimeout=2 "$test_user_ip" "echo OK" > /dev/null 2>&1; then
        ((NODES_WITHOUT_KEY++))
        if [ $NODES_WITHOUT_KEY -ge 1 ]; then
            NEEDS_PASSWORD=true
            break
        fi
    fi
done < <(echo "$NODES" | head -5)

if [ "$NEEDS_PASSWORD" = true ]; then
    echo "   → SSH 키가 없는 노드 발견. 비밀번호 설정이 필요합니다."
else
    echo "   → SSH 키가 이미 배포되어 있습니다."
fi

if [ "$NEEDS_PASSWORD" = true ]; then
    echo ""
    echo "================================================================================"
    echo "🔐 비밀번호 입력 (한 번만)"
    echo "================================================================================"
    echo ""
    echo "⚠️  모든 노드에 동일한 비밀번호를 사용한다고 가정합니다."
    echo "   (다른 경우 수동으로 ssh-copy-id를 실행하세요)"
    echo ""

    # 설정 파일에서 비밀번호 읽기 시도
    PASSWORD=$(CONFIG_FILE="$CONFIG_FILE" python3 << 'EOFPY' 2>/dev/null || echo ""
import yaml
import os
config_file = os.environ.get('CONFIG_FILE', 'my_cluster.yaml')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)
password = config.get('cluster_info', {}).get('ssh_password', '')
if password and password != 'your_password_here':
    print(password)
EOFPY
)

    if [ -n "$PASSWORD" ]; then
        echo "✅ 설정 파일에서 SSH 비밀번호를 읽었습니다."
    else
        read -s -p "SSH 비밀번호: " PASSWORD
        echo ""
        if [ -z "$PASSWORD" ]; then
            echo "❌ 비밀번호가 입력되지 않았습니다."
            exit 1
        fi
    fi

    # sshpass 설치 확인/설치
    if ! command -v sshpass &> /dev/null; then
        echo ""
        echo "📦 sshpass 설치 중..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y sshpass > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            sudo yum install -y sshpass > /dev/null 2>&1
        fi
    fi

    if command -v sshpass &> /dev/null; then
        USE_SSHPASS=true
        echo "✅ sshpass 사용 가능"
    else
        echo "⚠️  sshpass를 설치할 수 없습니다. 수동으로 비밀번호를 입력해야 합니다."
    fi
fi

echo ""

# /etc/hosts 업데이트
echo "🔧 /etc/hosts 파일 업데이트 중..."
echo ""

# 백업 생성
if [ -f /etc/hosts ]; then
    sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
fi

# 클러스터 섹션 마커
CLUSTER_START="# === HPC Cluster Nodes (Auto-generated by setup_ssh_passwordless.sh) ==="
CLUSTER_END="# === End of HPC Cluster Nodes ==="

# 기존 클러스터 섹션 제거
if grep -q "$CLUSTER_START" /etc/hosts 2>/dev/null; then
    sudo sed -i "/$CLUSTER_START/,/$CLUSTER_END/d" /etc/hosts
fi

# 새 클러스터 섹션 생성
{
    echo ""
    echo "$CLUSTER_START"
    echo "$NODES" | while IFS='#' read -r user_ip hostname; do
        ip=$(echo "$user_ip" | cut -d'@' -f2)
        echo "$ip    $hostname"
    done
    echo "$CLUSTER_END"
} | sudo tee -a /etc/hosts > /dev/null

echo "✅ /etc/hosts 업데이트 완료 (백업: /etc/hosts.backup.*)"
echo ""

echo "================================================================================"
echo "📤 각 노드에 공개키 복사 및 설정 중..."
echo "================================================================================"
echo ""

if [ "$USE_SSHPASS" = true ]; then
    echo "✅ sshpass를 사용하여 자동으로 진행합니다."
else
    echo "⚠️  SSH 키가 이미 배포된 노드는 자동으로 진행됩니다."
fi
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_NODES=""

# 파일 디스크립터 3을 루프 입력용으로 사용 (stdin을 interactive 명령에 남겨둠)
exec 3< <(echo "$NODES")

while IFS='#' read -r user_ip hostname <&3; do
    echo "----------------------------------------"
    echo "📤 $hostname ($user_ip)"
    echo "----------------------------------------"

    USER_NAME=$(echo "$user_ip" | cut -d'@' -f1)

    # 이미 SSH 키가 배포되어 있는지 확인
    ALREADY_SETUP=false
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "$user_ip" "echo OK" > /dev/null 2>&1; then
        ALREADY_SETUP=true
        echo "   ✅ SSH 키 이미 배포됨"
    fi

    # SSH 키 복사 (필요한 경우만)
    if [ "$ALREADY_SETUP" = false ]; then
        echo "   [1/4] SSH 공개키 복사 중..."

        # USE_SSHPASS가 false인데 SSH 키가 없는 경우 -> 비밀번호 필요
        if [ "$USE_SSHPASS" = false ] && [ -z "$PASSWORD" ]; then
            # 이 시점에서 비밀번호가 필요함 - 한 번만 요청
            echo ""
            echo "   ⚠️  이 노드에 SSH 키가 없습니다. 비밀번호가 필요합니다."
            read -s -p "   SSH 비밀번호 (모든 노드에 동일하게 적용됨): " PASSWORD
            echo ""
            if [ -n "$PASSWORD" ] && command -v sshpass &> /dev/null; then
                USE_SSHPASS=true
            elif [ -n "$PASSWORD" ]; then
                # sshpass가 없어도 비밀번호가 있으면 설치 시도
                echo "   📦 sshpass 설치 중..."
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update > /dev/null 2>&1
                    sudo apt-get install -y sshpass > /dev/null 2>&1
                elif command -v yum &> /dev/null; then
                    sudo yum install -y sshpass > /dev/null 2>&1
                fi
                if command -v sshpass &> /dev/null; then
                    USE_SSHPASS=true
                    echo "   ✅ sshpass 설치 완료"
                fi
            fi
        fi

        COPY_OK=false
        if [ "$USE_SSHPASS" = true ] && [ -n "$PASSWORD" ]; then
            # sshpass로 자동 처리 (비밀번호 묻지 않음)
            sshpass -p "$PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "$user_ip" > /dev/null 2>&1 && COPY_OK=true
        elif [ -n "$PASSWORD" ]; then
            # sshpass 없이 expect 스크립트로 자동화 시도
            if command -v expect &> /dev/null; then
                expect << EXPECT_EOF > /dev/null 2>&1 && COPY_OK=true
spawn ssh-copy-id -o StrictHostKeyChecking=no $user_ip
expect {
    "password:" { send "$PASSWORD\r"; exp_continue }
    "Password:" { send "$PASSWORD\r"; exp_continue }
    eof
}
EXPECT_EOF
            else
                # expect도 없으면 수동으로 한 번만 진행 (최후의 수단)
                echo "   ⚠️  자동화 도구 없음. 이 노드만 수동 입력 필요."
                ssh-copy-id -o StrictHostKeyChecking=no "$user_ip" 2>/dev/null && COPY_OK=true
            fi
        else
            # 비밀번호 없이 ssh-copy-id 시도 (이미 인증 방법이 있을 수 있음)
            ssh-copy-id -o StrictHostKeyChecking=no "$user_ip" 2>/dev/null && COPY_OK=true
        fi

        if [ "$COPY_OK" = true ]; then
            echo "   ✅ 공개키 복사 완료"
        else
            echo "   ❌ 공개키 복사 실패"
            ((FAIL_COUNT++))
            FAILED_NODES="$FAILED_NODES\n  - $hostname ($user_ip)"
            echo ""
            continue
        fi
    fi

    ((SUCCESS_COUNT++))

    # 접속 테스트
    echo "   [2/4] 접속 테스트..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$user_ip" "echo OK" > /dev/null 2>&1; then
        echo "   ⚠️  접속 테스트 실패"
        echo ""
        continue
    fi
    echo "   ✅ 접속 성공"

    # sudoers 파일 생성 (로컬에 임시 파일로)
    SUDOERS_TMP="/tmp/cluster-sudoers.$$"
    cat > "$SUDOERS_TMP" << EOF
# Allow $USER_NAME to run cluster management commands without password
# Generated by setup_ssh_passwordless.sh
# File operations (both /bin and /usr/bin paths for compatibility)
$USER_NAME ALL=(ALL) NOPASSWD: /bin/cp *, /usr/bin/cp *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/rm *, /usr/bin/rm *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/mv *, /usr/bin/mv *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/chown *, /usr/bin/chown *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/chmod *, /usr/bin/chmod *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/mkdir *, /usr/bin/mkdir *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/tee *, /usr/bin/tee *
# Systemctl
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl *
# Package management
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/dpkg *
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/apt-get *
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/apt *
# GlusterFS
$USER_NAME ALL=(ALL) NOPASSWD: /usr/sbin/gluster *
EOF

    # sudoers 파일을 원격 노드에 복사 및 설치
    echo "   [3/4] NOPASSWD sudoers 설정 중..."
    scp -o BatchMode=yes -o StrictHostKeyChecking=no "$SUDOERS_TMP" "$user_ip:/tmp/cluster-sudoers" > /dev/null 2>&1

    # sudoers 설치 명령어
    # 소유권: root:root, 권한: 440 필수
    SUDOERS_INSTALL_CMD='visudo -c -f /tmp/cluster-sudoers && cp /tmp/cluster-sudoers /etc/sudoers.d/cluster-automation && chown root:root /etc/sudoers.d/cluster-automation && chmod 440 /etc/sudoers.d/cluster-automation && rm -f /tmp/cluster-sudoers'

    SUDOERS_OK=false

    # 방법 1: 이미 NOPASSWD sudoers가 설정되어 있으면 BatchMode로 성공
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user_ip" \
        "sudo -n bash -c '$SUDOERS_INSTALL_CMD'" 2>/dev/null; then
        SUDOERS_OK=true
    fi

    # 방법 2: sshpass + SUDO_ASKPASS 사용 (가장 안정적)
    if [ "$SUDOERS_OK" = false ] && [ "$USE_SSHPASS" = true ] && [ -n "$PASSWORD" ]; then
        # 원격에 askpass 스크립트 생성 - 비밀번호를 base64로 인코딩하여 전달
        ENCODED_PW=$(echo -n "$PASSWORD" | base64)
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$user_ip" \
            "echo '#!/bin/bash' > /tmp/askpass.sh && echo 'echo $ENCODED_PW | base64 -d' >> /tmp/askpass.sh && chmod +x /tmp/askpass.sh && export SUDO_ASKPASS=/tmp/askpass.sh && sudo -A bash -c '$SUDOERS_INSTALL_CMD'; EXIT_CODE=\$?; rm -f /tmp/askpass.sh; exit \$EXIT_CODE" 2>/dev/null && SUDOERS_OK=true
    fi

    # 방법 3: sshpass + sudo -S (대체)
    if [ "$SUDOERS_OK" = false ] && [ "$USE_SSHPASS" = true ] && [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no "$user_ip" \
            "echo '$PASSWORD' | sudo -S bash -c '$SUDOERS_INSTALL_CMD'" 2>/dev/null && SUDOERS_OK=true
    fi

    # 방법 4: 비밀번호가 있으면 sudo -S로 파이프 (sshpass 없이도 동작)
    if [ "$SUDOERS_OK" = false ] && [ -n "$PASSWORD" ]; then
        ssh -o StrictHostKeyChecking=no "$user_ip" \
            "echo '$PASSWORD' | sudo -S bash -c '$SUDOERS_INSTALL_CMD'" 2>/dev/null && SUDOERS_OK=true
    fi

    # 방법 5: 비밀번호가 없으면 한 번만 요청하고 저장
    if [ "$SUDOERS_OK" = false ] && [ -z "$PASSWORD" ]; then
        echo ""
        echo "   ⚠️  sudo 비밀번호가 필요합니다 (모든 노드에 동일하게 적용됨)"
        read -s -p "   sudo 비밀번호: " PASSWORD
        echo ""
        if [ -n "$PASSWORD" ]; then
            # sshpass 설치 시도
            if ! command -v sshpass &> /dev/null; then
                sudo apt-get update > /dev/null 2>&1 && sudo apt-get install -y sshpass > /dev/null 2>&1
            fi
            if command -v sshpass &> /dev/null; then
                USE_SSHPASS=true
            fi
            # 다시 시도
            ssh -o StrictHostKeyChecking=no "$user_ip" \
                "echo '$PASSWORD' | sudo -S bash -c '$SUDOERS_INSTALL_CMD'" 2>/dev/null && SUDOERS_OK=true
        fi
    fi

    # 방법 6: interactive (최후의 수단 - 이 노드만)
    if [ "$SUDOERS_OK" = false ]; then
        echo "   ⚠️  자동화 실패. 이 노드만 수동 입력 필요."
        ssh -t -o StrictHostKeyChecking=no "$user_ip" \
            "sudo bash -c '$SUDOERS_INSTALL_CMD'" 2>/dev/null && SUDOERS_OK=true
    fi

    if [ "$SUDOERS_OK" = true ]; then
        echo "   ✅ NOPASSWD sudoers 설정 완료"
    else
        echo "   ⚠️  sudoers 설정 실패"
    fi

    # 로컬 임시 파일 삭제
    rm -f "$SUDOERS_TMP"

    # /etc/hosts 파일 복사
    echo "   [4/4] /etc/hosts 파일 배포 중..."
    scp -o BatchMode=yes -o StrictHostKeyChecking=no /etc/hosts "$user_ip:/tmp/hosts.tmp" > /dev/null 2>&1

    HOSTS_OK=false
    HOSTS_INSTALL_CMD='cp /tmp/hosts.tmp /etc/hosts && rm -f /tmp/hosts.tmp'

    # 방법 1: sudoers가 성공적으로 설정되었으면 NOPASSWD로 시도
    if [ "$SUDOERS_OK" = true ]; then
        if ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$user_ip" \
            "sudo -n bash -c '$HOSTS_INSTALL_CMD'" 2>/dev/null; then
            HOSTS_OK=true
        fi
    fi

    # 방법 2: sshpass + SUDO_ASKPASS (가장 안정적)
    if [ "$HOSTS_OK" = false ] && [ "$USE_SSHPASS" = true ] && [ -n "$PASSWORD" ]; then
        ENCODED_PW=$(echo -n "$PASSWORD" | base64)
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$user_ip" \
            "echo '#!/bin/bash' > /tmp/askpass.sh && echo 'echo $ENCODED_PW | base64 -d' >> /tmp/askpass.sh && chmod +x /tmp/askpass.sh && export SUDO_ASKPASS=/tmp/askpass.sh && sudo -A bash -c '$HOSTS_INSTALL_CMD'; EXIT_CODE=\$?; rm -f /tmp/askpass.sh; exit \$EXIT_CODE" 2>/dev/null && HOSTS_OK=true
    fi

    # 방법 3: sshpass + sudo -S with echo (대체)
    if [ "$HOSTS_OK" = false ] && [ "$USE_SSHPASS" = true ] && [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no "$user_ip" \
            "echo '$PASSWORD' | sudo -S bash -c '$HOSTS_INSTALL_CMD'" 2>/dev/null && HOSTS_OK=true
    fi

    # 방법 4: 비밀번호가 있으면 sudo -S로 파이프 (sshpass 없이도 동작)
    if [ "$HOSTS_OK" = false ] && [ -n "$PASSWORD" ]; then
        ssh -o StrictHostKeyChecking=no "$user_ip" \
            "echo '$PASSWORD' | sudo -S bash -c '$HOSTS_INSTALL_CMD'" 2>/dev/null && HOSTS_OK=true
    fi

    # 방법 5: interactive (최후의 수단)
    if [ "$HOSTS_OK" = false ]; then
        ssh -t -o StrictHostKeyChecking=no "$user_ip" \
            "sudo bash -c '$HOSTS_INSTALL_CMD'" 2>/dev/null && HOSTS_OK=true
    fi

    if [ "$HOSTS_OK" = true ]; then
        echo "   ✅ /etc/hosts 배포 완료"
    else
        echo "   ⚠️  /etc/hosts 배포 실패"
    fi

    echo ""
done

# 파일 디스크립터 3 닫기
exec 3<&-

echo "================================================================================"
echo "✅ SSH 키 설정 완료!"
echo "================================================================================"
echo ""

echo "📊 결과 요약:"
echo "  - 설정 완료: $SUCCESS_COUNT개 노드"
if [ $FAIL_COUNT -gt 0 ]; then
    echo "  - 설정 실패: $FAIL_COUNT개 노드"
    echo -e "    $FAILED_NODES"
fi
echo ""

echo "🧪 테스트:"
while IFS='#' read -r user_ip hostname; do
    echo "  ssh $user_ip 'hostname'"
done < <(echo "$NODES")
echo ""

echo "✨ 이제 다음 명령어들이 비밀번호 없이 작동합니다:"
echo "  - ssh node001 'command'"
echo "  - scp file.txt node001:/tmp/"
echo "  - ./setup_cluster_full.sh  ← 비밀번호 입력 없이 진행!"
echo ""

echo "================================================================================"
echo ""

# 자동 테스트 제안
read -p "지금 SSH 접속 테스트를 하시겠습니까? (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "🧪 SSH 접속 테스트 중..."
    echo ""

    while IFS='#' read -r user_ip hostname; do
        echo -n "  $hostname ($user_ip): "

        # 비밀번호 없이 접속 시도
        RESULT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$user_ip" "hostname" 2>/dev/null)

        if [ $? -eq 0 ]; then
            echo "✅ $RESULT"
        else
            echo "❌ 접속 실패 (비밀번호가 필요함)"
        fi
    done < <(echo "$NODES")

    echo ""
fi

echo "================================================================================"
echo "📋 다음 단계:"
echo ""
echo "  1. setup_cluster_full.sh 또는 setup_cluster_full_multihead.sh 실행 (비밀번호 입력 없음!)"
echo "     ./setup_cluster_full.sh"
echo "     ./setup_cluster_full_multihead.sh $CONFIG_FILE"
echo ""
echo "  2. 또는 개별 노드 접속 테스트"
echo "     ssh <hostname>"
echo ""
echo "================================================================================"

################################################################################
# 시간 동기화 설정 (Munge 인증에 필수)
################################################################################

echo ""
read -p "🕐 모든 노드에 시간 동기화를 설정하시겠습니까? (Munge 필수) (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "================================================================================"
    echo "🕐 시간 동기화 설정 중..."
    echo "================================================================================"
    echo ""

    # 먼저 로컬에서 설정
    if [ -f "setup_time_sync.sh" ]; then
        echo "📍 로컬 시간 동기화 설정..."
        sudo bash setup_time_sync.sh "$CONFIG_FILE"
        echo ""

        # 원격 노드에 배포
        echo "📤 원격 노드에 시간 동기화 설정 배포 중..."
        echo ""

        while IFS='#' read -r user_ip hostname <&4; do
            echo -n "  $hostname: "

            # 스크립트와 설정 파일 복사
            if scp -o BatchMode=yes -o ConnectTimeout=5 setup_time_sync.sh "$CONFIG_FILE" "$user_ip:/tmp/" 2>/dev/null; then
                # 원격 실행 (sudo -S로 비밀번호 입력 지원)
                if [ -n "$PASSWORD" ]; then
                    # 저장된 비밀번호 사용
                    result=$(ssh -o BatchMode=yes -o ConnectTimeout=30 "$user_ip" \
                        "cd /tmp && echo '$PASSWORD' | sudo -S bash setup_time_sync.sh $CONFIG_FILE 2>&1" 2>&1)
                else
                    # 비밀번호 없이 시도
                    result=$(ssh -o BatchMode=yes -o ConnectTimeout=30 "$user_ip" \
                        "cd /tmp && sudo bash setup_time_sync.sh $CONFIG_FILE 2>&1" 2>&1)
                fi

                if echo "$result" | grep -q "설정 완료\|✅"; then
                    echo "✅ 완료"
                else
                    echo "⚠️  설정 실패"
                    # 오류 내용 표시 (처음 2줄만)
                    echo "$result" | grep -i "error\|실패\|failed\|permission\|denied" | head -2 | sed 's/^/      /'
                fi
            else
                echo "⚠️  파일 복사 실패"
            fi
        done 4< <(echo "$NODES")

        echo ""
        echo "🔍 시간 동기화 상태 확인:"
        echo ""

        while IFS='#' read -r user_ip hostname <&4; do
            time_result=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$user_ip" "date '+%Y-%m-%d %H:%M:%S'" 2>/dev/null || echo "연결 실패")
            echo "  $hostname: $time_result"
        done 4< <(echo "$NODES")

        echo ""
    else
        echo "⚠️  setup_time_sync.sh를 찾을 수 없습니다"
        echo "   수동 설정이 필요합니다."
    fi
fi

echo ""
echo "================================================================================"
echo "🎉 모든 설정 완료!"
echo "================================================================================"
