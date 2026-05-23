#!/bin/bash
################################################################################
# Slurm 바이너리 자동 설치 스크립트
# 모든 노드에 Slurm을 컴파일하고 설치
# Usage: ./install_slurm_binary.sh [CONFIG_FILE]
################################################################################


# --config <yaml> 옵션 처리 (기본: my_multihead_cluster.yaml)
CONFIG_FILE="${CONFIG_FILE:-my_multihead_cluster.yaml}"
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        *) _args+=("$1"); shift ;;
    esac
done
set -- "${_args[@]+"${_args[@]}"}"
[[ ! -f "$CONFIG_FILE" ]] && { echo "❌ YAML 없음: $CONFIG_FILE"; echo "사용: $0 [--config <yaml>]"; exit 1; }
echo "📄 Config: $CONFIG_FILE"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SLURM_VERSION="23.02.7"
SLURM_URL="https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2"
INSTALL_PREFIX="/usr/local/slurm"
CONFIG_DIR="${INSTALL_PREFIX}/etc"

################################################################################
# YAML 설정 파일에서 모든 정보 읽기
################################################################################
CONFIG_FILE="${1:-my_multihead_cluster.yaml}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    echo "   Usage: $0 [config.yaml]"
    exit 1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "❌ Python yaml 모듈이 필요합니다: pip3 install pyyaml"
    exit 1
fi

# YAML에서 노드 정보 읽기
echo "📖 설정 파일 읽는 중: $CONFIG_FILE"

# UID/GID 기본값
SLURM_UID=1001
SLURM_GID=1001

# YAML 파싱
read_config() {
    python3 << EOFPY
import yaml

with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)

nodes = config.get('nodes', {})

# UID/GID
slurm_conf = config.get('slurm', {})
print(f"SLURM_UID={slurm_conf.get('slurm_uid', 1001)}")
print(f"SLURM_GID={slurm_conf.get('slurm_gid', 1001)}")

# 컨트롤러 정보
if 'controllers' in nodes:
    ctrl = nodes['controllers'][0]
else:
    ctrl = nodes.get('controller', {})

print(f"CONTROLLER_HOST={ctrl.get('hostname', 'controller')}")
print(f"CONTROLLER_IP={ctrl.get('ip_address', '')}")
print(f"CONTROLLER_USER={ctrl.get('ssh_user', 'root')}")

# 계산 노드 목록
compute_nodes = nodes.get('compute_nodes', [])
ips = []
names = []
users = []
for node in compute_nodes:
    ips.append(node.get('ip_address', ''))
    names.append(node.get('hostname', ''))
    users.append(node.get('ssh_user', 'root'))

print(f"NODE_IPS=({' '.join(ips)})")
print(f"NODE_NAMES=({' '.join(names)})")
print(f"NODE_USERS=({' '.join(users)})")
EOFPY
}

# 설정 로드
eval "$(read_config)"

# 첫 번째 노드의 사용자를 기본값으로 사용
USER_NAME="${NODE_USERS[0]:-$CONTROLLER_USER}"

echo ""
echo "================================================================================"
echo "🚀 Slurm 바이너리 자동 설치"
echo "================================================================================"
echo ""
echo "Slurm 버전: ${SLURM_VERSION}"
echo "설치 경로: ${INSTALL_PREFIX}"
echo "UID/GID: slurm=$SLURM_UID:$SLURM_GID"
echo ""
echo "대상 노드:"
echo "  - 컨트롤러: $CONTROLLER_HOST ($CONTROLLER_IP)"
for i in "${!NODE_IPS[@]}"; do
  echo "  - ${NODE_NAMES[$i]}: ${NODE_IPS[$i]}"
done
echo ""

read -p "계속하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
  echo "취소되었습니다."
  exit 0
fi

# 비밀번호 입력 (sshpass 사용 시)
if command -v sshpass &> /dev/null; then
    echo ""
    echo "📝 노드 비밀번호 입력 (선택사항)"
    echo "SSH 키 인증이 설정되어 있으면 Enter를 누르세요."
    read -s -p "비밀번호 (없으면 Enter): " PASSWORD
    echo ""
fi

echo ""
echo "================================================================================"
echo "1단계: 컨트롤러에서 Slurm 다운로드 및 컴파일"
echo "================================================================================"
echo ""

cd ~

if [ ! -f "slurm-${SLURM_VERSION}.tar.bz2" ]; then
    echo "📥 Slurm 다운로드 중..."
    wget -q --show-progress ${SLURM_URL}
else
    echo "✅ Slurm 소스 이미 다운로드됨"
fi

if [ ! -d "slurm-${SLURM_VERSION}" ]; then
    echo "📦 압축 해제 중..."
    tar -xjf slurm-${SLURM_VERSION}.tar.bz2
fi

cd slurm-${SLURM_VERSION}

echo "🔧 Configure 실행 중..."
./configure \
    --prefix=${INSTALL_PREFIX} \
    --sysconfdir=${CONFIG_DIR} \
    --with-munge=/usr \
    --enable-pam \
    > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Configure 실패"
    echo "필수 패키지를 설치하세요:"
    echo "  sudo apt-get install build-essential libmunge-dev libpam0g-dev libreadline-dev"
    exit 1
fi

echo "⚙️  컴파일 중 (시간이 걸릴 수 있습니다)..."
make -j$(nproc) > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 컴파일 실패"
    exit 1
fi

echo "📦 설치 중..."
sudo make install > /dev/null 2>&1

# ldconfig 설정 (동적 라이브러리 캐시 갱신)
echo "🔗 라이브러리 캐시 갱신 중..."
echo "/usr/local/slurm/lib" | sudo tee /etc/ld.so.conf.d/slurm.conf > /dev/null
sudo ldconfig

echo "✅ 컨트롤러 Slurm 설치 완료"

echo ""
echo "================================================================================"
echo "2단계: Slurm 사용자 및 디렉토리 생성"
echo "================================================================================"
echo ""

# 컨트롤러
echo "📌 컨트롤러 (localhost)"
sudo groupadd -g "$SLURM_GID" slurm 2>/dev/null || true
sudo useradd -r -u "$SLURM_UID" -g "$SLURM_GID" -s /bin/false slurm 2>/dev/null || echo "  ✅ slurm 사용자 이미 존재 (UID=$(id -u slurm 2>/dev/null || echo 'N/A'))"
sudo mkdir -p /var/spool/slurm/state /var/spool/slurm/d /var/log/slurm
sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm
sudo chmod 755 /var/spool/slurm /var/log/slurm
echo "  ✅ 완료"

# 계산 노드
for i in "${!NODE_IPS[@]}"; do
    node="${NODE_IPS[$i]}"
    node_name="${NODE_NAMES[$i]}"
    node_user="${NODE_USERS[$i]:-$USER_NAME}"

    echo "📌 $node_name ($node)"

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node \
            "sudo groupadd -g $SLURM_GID slurm 2>/dev/null || true && \
             sudo useradd -r -u $SLURM_UID -g $SLURM_GID -s /bin/false slurm 2>/dev/null || true && \
             sudo mkdir -p /var/spool/slurm/state /var/spool/slurm/d /var/log/slurm && \
             sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm && \
             sudo chmod 755 /var/spool/slurm /var/log/slurm" > /dev/null 2>&1
    else
        ssh $node_user@$node \
            "sudo groupadd -g $SLURM_GID slurm 2>/dev/null || true && \
             sudo useradd -r -u $SLURM_UID -g $SLURM_GID -s /bin/false slurm 2>/dev/null || true && \
             sudo mkdir -p /var/spool/slurm/state /var/spool/slurm/d /var/log/slurm && \
             sudo chown -R slurm:slurm /var/spool/slurm /var/log/slurm && \
             sudo chmod 755 /var/spool/slurm /var/log/slurm" > /dev/null 2>&1
    fi
    
    echo "  ✅ 완료"
done

echo ""
echo "================================================================================"
echo "3단계: 계산 노드에 Slurm 바이너리 복사"
echo "================================================================================"
echo ""

cd ~

for i in "${!NODE_IPS[@]}"; do
    node="${NODE_IPS[$i]}"
    node_name="${NODE_NAMES[$i]}"
    node_user="${NODE_USERS[$i]:-$USER_NAME}"

    echo "📌 $node_name ($node)"

    # 필수 패키지 설치
    echo "  [0/5] 필수 패키지 확인 및 설치..."

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node \
            "sudo apt-get update > /dev/null 2>&1 && \
             sudo apt-get install -y build-essential bzip2 libmunge-dev libpam0g-dev libreadline-dev libssl-dev > /dev/null 2>&1"
    else
        ssh $node_user@$node \
            "sudo apt-get update > /dev/null 2>&1 && \
             sudo apt-get install -y build-essential bzip2 libmunge-dev libpam0g-dev libreadline-dev libssl-dev > /dev/null 2>&1"
    fi

    echo "  [1/5] 소스 복사 중..."

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -q slurm-${SLURM_VERSION}.tar.bz2 $node_user@$node:~/ > /dev/null 2>&1
    else
        scp -q slurm-${SLURM_VERSION}.tar.bz2 $node_user@$node:~/ > /dev/null 2>&1
    fi

    echo "  [2/5] 압축 해제 및 컴파일 중..."

    COMPILE_CMD="cd ~ && tar -xjf slurm-${SLURM_VERSION}.tar.bz2 && cd slurm-${SLURM_VERSION} && \
        ./configure --prefix=${INSTALL_PREFIX} --sysconfdir=${CONFIG_DIR} --with-munge=/usr --enable-pam > /dev/null 2>&1 && \
        make -j\$(nproc) > /dev/null 2>&1"

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node "$COMPILE_CMD"
    else
        ssh $node_user@$node "$COMPILE_CMD"
    fi

    if [ $? -ne 0 ]; then
        echo "  ❌ 컴파일 실패 - $node_name"
        echo "     수동으로 확인하세요: ssh $node_user@$node"
        continue
    fi

    echo "  [3/5] 설치 및 ldconfig 중..."

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node \
            "cd slurm-${SLURM_VERSION} && sudo make install > /dev/null 2>&1 && \
             echo '/usr/local/slurm/lib' | sudo tee /etc/ld.so.conf.d/slurm.conf > /dev/null && \
             sudo ldconfig"
    else
        ssh $node_user@$node "cd slurm-${SLURM_VERSION} && sudo make install > /dev/null 2>&1 && \
             echo '/usr/local/slurm/lib' | sudo tee /etc/ld.so.conf.d/slurm.conf > /dev/null && \
             sudo ldconfig"
    fi

    echo "  [4/5] 정리 중..."

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node \
            "rm -rf ~/slurm-${SLURM_VERSION} ~/slurm-${SLURM_VERSION}.tar.bz2" > /dev/null 2>&1
    else
        ssh $node_user@$node "rm -rf ~/slurm-${SLURM_VERSION} ~/slurm-${SLURM_VERSION}.tar.bz2" > /dev/null 2>&1
    fi

    echo "  ✅ 완료"
done

echo ""
echo "================================================================================"
echo "4단계: systemd 서비스 파일 생성"
echo "================================================================================"
echo ""

# 컨트롤러 서비스 파일
echo "📌 컨트롤러 (slurmctld.service)"
sudo tee /etc/systemd/system/slurmctld.service > /dev/null <<'EOF'
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmctld
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=/usr/local/slurm/sbin/slurmctld -D $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmctld.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF

echo "  ✅ 생성 완료"

# 계산 노드 서비스 파일
for i in "${!NODE_IPS[@]}"; do
    node="${NODE_IPS[$i]}"
    node_name="${NODE_NAMES[$i]}"
    node_user="${NODE_USERS[$i]:-$USER_NAME}"

    echo "📌 $node_name (slurmd.service)"

    SERVICE_FILE='[Unit]
Description=Slurm node daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=simple
EnvironmentFile=-/etc/default/slurmd
ExecStartPre=/bin/mkdir -p /run/slurm
ExecStartPre=/bin/chown slurm:slurm /run/slurm
ExecStart=/usr/local/slurm/sbin/slurmd -D $SLURMD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/run/slurm/slurmd.pid
KillMode=process
LimitNOFILE=131072
LimitMEMLOCK=infinity
LimitSTACK=infinity
Delegate=yes

[Install]
WantedBy=multi-user.target'

    if [ -n "$PASSWORD" ]; then
        echo "$SERVICE_FILE" | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node \
            "sudo tee /etc/systemd/system/slurmd.service > /dev/null"
    else
        echo "$SERVICE_FILE" | ssh $node_user@$node "sudo tee /etc/systemd/system/slurmd.service > /dev/null"
    fi

    echo "  ✅ 생성 완료"
done

echo ""
echo "================================================================================"
echo "5단계: 서비스 활성화"
echo "================================================================================"
echo ""

# 컨트롤러
echo "📌 컨트롤러 (slurmctld)"
sudo systemctl daemon-reload
sudo systemctl enable slurmctld > /dev/null 2>&1
echo "  ✅ 활성화 완료"

# 계산 노드
for i in "${!NODE_IPS[@]}"; do
    node="${NODE_IPS[$i]}"
    node_name="${NODE_NAMES[$i]}"
    node_user="${NODE_USERS[$i]:-$USER_NAME}"

    echo "📌 $node_name (slurmd)"

    if [ -n "$PASSWORD" ]; then
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $node_user@$node \
            "sudo systemctl daemon-reload && sudo systemctl enable slurmd" > /dev/null 2>&1
    else
        ssh $node_user@$node "sudo systemctl daemon-reload && sudo systemctl enable slurmd" > /dev/null 2>&1
    fi

    echo "  ✅ 활성화 완료"
done

echo ""
echo "================================================================================"
echo "🎉 Slurm 설치 완료!"
echo "================================================================================"
echo ""
echo "다음 명령어로 서비스를 시작하세요:"
echo ""
echo "# 컨트롤러"
echo "sudo systemctl start slurmctld"
echo "sudo systemctl status slurmctld"
echo ""
echo "# 계산 노드 (각 노드에서)"
for i in "${!NODE_IPS[@]}"; do
    node="${NODE_IPS[$i]}"
    node_name="${NODE_NAMES[$i]}"
    node_user="${NODE_USERS[$i]:-$USER_NAME}"
    echo "ssh $node_user@$node 'sudo systemctl start slurmd'"
done
echo ""
echo "# 상태 확인"
echo "/usr/local/slurm/bin/sinfo"
echo "/usr/local/slurm/bin/sinfo -N"
echo ""
echo "📚 자세한 가이드: cat SLURM_INSTALL_GUIDE.md"
echo "================================================================================"
