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

# SSH 키 생성 (없으면)
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "🔑 SSH 키 생성 중..."
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa -q
    echo "✅ SSH 키 생성 완료"
else
    echo "✅ 기존 SSH 키 사용: ~/.ssh/id_rsa"
fi

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

    # Check if already configured
    test_result = subprocess.run(
        ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3',
         '-o', 'StrictHostKeyChecking=no', target, 'echo', 'OK'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    if test_result.returncode == 0:
        print("✅ (이미 설정됨)")
        success += 1
        continue

    # Try to copy SSH key using sshpass if password is available
    if ssh_password:
        result = subprocess.run(
            ['sshpass', '-p', ssh_password, 'ssh-copy-id',
             '-o', 'StrictHostKeyChecking=no',
             '-o', 'ConnectTimeout=5', target],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        if result.returncode == 0:
            print("✅")
            success += 1
        else:
            print("❌ (sshpass 실패)")
            failed.append(hostname)
    else:
        # No password in YAML, use interactive mode
        print("비밀번호 입력: ", end='', flush=True)

        result = subprocess.run(
            ['ssh-copy-id', '-o', 'StrictHostKeyChecking=no',
             '-o', 'ConnectTimeout=5', target]
        )

        if result.returncode == 0:
            print(f"    ✅ {hostname} 완료")
            success += 1
        else:
            print(f"    ❌ {hostname} 실패")
            failed.append(hostname)

print(f"\n✅ 성공: {success}개 노드")
if failed:
    print(f"❌ 실패: {', '.join(failed)}")
    sys.exit(1)

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
