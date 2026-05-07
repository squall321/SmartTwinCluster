#!/bin/bash
################################################################################
# SSH 키 기반 인증 자동 설정 (멀티헤드 클러스터용)
# 비대화형 모드로 작동 - setup_cluster_full_multihead.sh에서 사용
################################################################################

set -euo pipefail

YAML_FILE="${1:-my_multihead_cluster.yaml}"

if [ ! -f "$YAML_FILE" ]; then
    echo "❌ $YAML_FILE not found!"
    exit 1
fi

echo "================================================================================"
echo "🔑 SSH 키 기반 인증 자동 설정 (멀티헤드)"
echo "================================================================================"
echo ""

# YAML에서 ssh_user 추출 (없으면 SUDO_USER → whoami 순서로 fallback)
YAML_SSH_USER=$(python3 -c "
import yaml, sys
with open('$YAML_FILE') as f:
    cfg = yaml.safe_load(f)
# controllers의 첫 번째 ssh_user 사용
ctrls = cfg.get('nodes', {}).get('controllers', [])
u = ctrls[0].get('ssh_user', '') if ctrls else ''
if not u:
    u = cfg.get('cluster_info', {}).get('ssh_user', '')
print(u)
" 2>/dev/null || echo "")

if [[ -n "$YAML_SSH_USER" ]] && id "$YAML_SSH_USER" &>/dev/null; then
    REAL_USER="$YAML_SSH_USER"
elif [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(whoami)"
fi
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

SSH_DIR="${REAL_HOME}/.ssh"
SSH_KEY="${SSH_DIR}/id_rsa"

echo "👤 SSH 키 사용자: $REAL_USER (홈: $REAL_HOME)"
echo "📁 SSH 디렉토리: $SSH_DIR"
echo ""

# SSH 디렉토리 생성
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$REAL_USER:$REAL_USER" "$SSH_DIR" 2>/dev/null || true

# SSH 키 생성 (없으면)
if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 SSH 키 생성 중..."
    sudo -u "$REAL_USER" ssh-keygen -t rsa -b 4096 -N "" -f "$SSH_KEY" -q
    echo "✅ SSH 키 생성 완료: $SSH_KEY"
else
    if [[ "$(stat -c '%U' "$SSH_KEY" 2>/dev/null)" != "$REAL_USER" ]]; then
        echo "⚠️  SSH 키 소유자 수정 중..."
        chown "$REAL_USER:$REAL_USER" "$SSH_KEY" "$SSH_KEY.pub" 2>/dev/null || true
        chmod 600 "$SSH_KEY" 2>/dev/null || true
    fi
    echo "✅ 기존 SSH 키 사용: $SSH_KEY"
fi

export SSH_KEY_FILE="$SSH_KEY"
export SSH_REAL_USER="$REAL_USER"

echo ""
echo "📤 공개키 복사 중..."
echo ""

# Python으로 모든 노드 추출 및 ssh-copy-id 실행
export YAML_CONFIG_FILE="$YAML_FILE"
python3 << 'EOFPY'
import yaml
import subprocess
import socket
import sys
import os

yaml_file = os.environ.get('YAML_CONFIG_FILE', 'my_multihead_cluster.yaml')

with open(yaml_file, 'r') as f:
    config = yaml.safe_load(f)

# Get SSH password from YAML
ssh_password = config.get('cluster_info', {}).get('ssh_password', '')

nodes = []

# Controllers
for ctrl in config.get('nodes', {}).get('controllers', []):
    if ctrl.get('enabled', True):
        nodes.append({
            'hostname': ctrl['hostname'],
            'ip': ctrl['ip_address'],
            'user': ctrl.get('ssh_user', 'koopark')
        })

# Compute nodes
for node in config.get('nodes', {}).get('compute_nodes', []):
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark')
    })

# Viz nodes
for node in config.get('nodes', {}).get('viz_nodes', []):
    nodes.append({
        'hostname': node['hostname'],
        'ip': node['ip_address'],
        'user': node.get('ssh_user', 'koopark')
    })

# Get current IP to skip
current_ip = None
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    current_ip = s.getsockname()[0]
    s.close()
except:
    pass

success = 0
failed = []

for node in nodes:
    target = f"{node['user']}@{node['ip']}"
    hostname = node['hostname']

    # Skip current node
    if node['ip'] == current_ip:
        print(f"  ⏭️  {hostname} (현재 노드)")
        continue

    print(f"  📤 {hostname} ({node['ip']})... ", end='', flush=True)

    ssh_key_file = os.environ.get('SSH_KEY_FILE', os.path.expanduser('~/.ssh/id_rsa'))
    real_user = os.environ.get('SSH_REAL_USER', '')

    # 이미 키 인증 가능한지 먼저 확인 → 되면 스킵
    check_cmd = ['sudo', '-u', real_user,
                 'ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=no',
                 '-o', 'ConnectTimeout=5', '-i', ssh_key_file,
                 target, 'true']
    check = subprocess.run(check_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode == 0:
        print("✅ (이미 키 인증 OK)")
        success += 1
        continue

    # ssh-copy-id 명령어 구성
    ssh_copy_cmd = ['sudo', '-u', real_user,
                    'ssh-copy-id', '-i', ssh_key_file,
                    '-o', 'StrictHostKeyChecking=no',
                    '-o', 'ConnectTimeout=5', target]

    if ssh_password:
        cmd = ['sshpass', '-p', ssh_password] + ssh_copy_cmd
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        if result.returncode == 0:
            print("✅")
            success += 1
        else:
            print("❌ (sshpass 실패)")
            failed.append(hostname)
    else:
        print("❌ (비밀번호 없음 — bootstrap_spc_oneshot.sh 먼저 실행 필요)")
        failed.append(hostname)

print(f"\n✅ 성공: {success}개 노드")
if failed:
    print(f"⚠️  스킵 (연결 불가 또는 인증 실패): {', '.join(failed)}")
    print("   → 해당 노드는 나중에 수동으로 키 등록 필요")
    print("   → 셋업은 계속 진행됩니다")

EOFPY

if [ $? -eq 0 ]; then
    echo ""
    echo "================================================================================"
    echo "✅ SSH 키 설정 완료!"
    echo "================================================================================"
    echo ""
    echo "이제 비밀번호 없이 모든 노드에 접속할 수 있습니다."
    echo ""
else
    echo ""
    echo "================================================================================"
    echo "⚠️  일부 노드 설정 실패"
    echo "================================================================================"
    echo ""
    echo "다음 명령으로 수동 설정하세요:"
    echo "  ./setup_ssh_passwordless_multihead.sh"
    echo ""
    exit 1
fi
