#!/bin/bash
# 노드 목록 디버깅 스크립트

CONFIG_FILE="${1:-my_cluster.yaml}"

echo "=== 디버그: YAML에서 노드 정보 추출 ==="
echo "Config file: $CONFIG_FILE"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 파일을 찾을 수 없습니다: $CONFIG_FILE"
    exit 1
fi

echo "1. Python으로 노드 목록 추출 (setup_ssh_passwordless.sh와 동일 방식):"
echo "---"

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

echo "$NODES"
echo ""
echo "추출된 노드 개수: $(echo "$NODES" | wc -l)"
echo ""

echo "2. 각 노드 상세 정보:"
echo "---"
echo "$NODES" | while IFS='#' read -r user_ip hostname; do
    echo "  Hostname: $hostname"
    echo "  User@IP: $user_ip"
    echo ""
done

echo "3. YAML 원본 controllers 섹션:"
echo "---"
python3 << EOFPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
nodes_config = config['nodes']

if 'controllers' in nodes_config:
    print("controllers (list):")
    for i, c in enumerate(nodes_config['controllers']):
        print(f"  [{i}] {c['hostname']} ({c['ssh_user']}@{c['ip_address']})")
elif 'controller' in nodes_config:
    c = nodes_config['controller']
    print(f"controller (single): {c['hostname']} ({c['ssh_user']}@{c['ip_address']})")
EOFPY

echo ""
echo "4. YAML 원본 compute_nodes 섹션:"
echo "---"
python3 << EOFPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
for i, node in enumerate(config['nodes']['compute_nodes']):
    print(f"  [{i}] {node['hostname']} ({node['ssh_user']}@{node['ip_address']})")
EOFPY

echo ""
echo "=== 디버그 완료 ==="
