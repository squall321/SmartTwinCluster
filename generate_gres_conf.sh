#!/bin/bash
################################################################################
# gres.conf 자동 생성 스크립트
#
# 설명:
#   YAML 설정에서 GPU 정보를 읽어 각 노드의 gres.conf 파일 생성
#
# 사용법:
#   ./generate_gres_conf.sh [--config my_cluster.yaml]
#
# 작성자: Claude Code
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/my_multihead_cluster_2.yaml"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            head -n 15 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

log_info "Using config: $CONFIG_FILE"
echo ""

# Python으로 YAML에서 GPU 노드 정보 추출
log_info "Extracting GPU node information from YAML..."

GRES_INFO=$(python3 << EOPY
import yaml
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to read YAML: {e}", file=sys.stderr)
    sys.exit(1)

nodes = config.get('nodes', {})
gres_nodes = []

# compute_nodes 확인
for node in nodes.get('compute_nodes', []):
    hostname = node.get('hostname', '')
    gpus = node.get('gpus', 0)
    gpu_type = node.get('gpu_type', 'nvidia')  # 기본값: nvidia

    if gpus > 0:
        gres_nodes.append({
            'hostname': hostname,
            'gpu_count': gpus,
            'gpu_type': gpu_type
        })

# viz_nodes 확인
for node in nodes.get('viz_nodes', []):
    hostname = node.get('hostname', '')
    gpus = node.get('gpus', 0)
    gpu_type = node.get('gpu_type', 'nvidia')  # 기본값: nvidia

    if gpus > 0:
        gres_nodes.append({
            'hostname': hostname,
            'gpu_count': gpus,
            'gpu_type': gpu_type
        })

# 결과 출력
for node_info in gres_nodes:
    print(f"{node_info['hostname']}|{node_info['gpu_count']}|{node_info['gpu_type']}")

EOPY
)

if [[ -z "$GRES_INFO" ]]; then
    log_warning "No GPU nodes found in YAML"
    log_warning "Make sure your YAML has nodes with 'gpus' field > 0"
    exit 0
fi

# gres.conf 파일 생성
GRES_CONF_PATH="/tmp/gres.conf"
> "$GRES_CONF_PATH"

log_success "Found GPU nodes:"
echo ""

while IFS='|' read -r hostname gpu_count gpu_type; do
    [[ -z "$hostname" ]] && continue

    log_info "  $hostname: $gpu_count x $gpu_type GPU(s)"

    # gres.conf에 추가
    for ((i=0; i<gpu_count; i++)); do
        # GPU 디바이스 파일 경로 생성
        case "$gpu_type" in
            nvidia)
                device_file="/dev/nvidia$i"
                ;;
            amd)
                device_file="/dev/dri/renderD$((128+i))"
                ;;
            *)
                device_file="/dev/gpu$i"
                ;;
        esac

        echo "NodeName=$hostname Name=gpu Type=$gpu_type File=$device_file" >> "$GRES_CONF_PATH"
    done
done <<< "$GRES_INFO"

echo ""
log_success "Generated gres.conf:"
echo ""
cat "$GRES_CONF_PATH"
echo ""

# 헤드노드에 복사
log_info "Installing gres.conf to /etc/slurm/gres.conf..."
sudo cp "$GRES_CONF_PATH" /etc/slurm/gres.conf
sudo chown slurm:slurm /etc/slurm/gres.conf
sudo chmod 644 /etc/slurm/gres.conf
log_success "Installed to /etc/slurm/gres.conf"
echo ""

# 각 GPU 노드에 gres.conf 배포 안내
log_warning "다음 단계: 각 GPU 노드에 gres.conf 배포"
echo ""
echo "방법 1: 수동 배포"
echo ""

while IFS='|' read -r hostname gpu_count gpu_type; do
    [[ -z "$hostname" ]] && continue

    # YAML에서 IP 가져오기
    node_ip=$(python3 -c "
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
nodes = config.get('nodes', {})
for node in nodes.get('compute_nodes', []) + nodes.get('viz_nodes', []):
    if node.get('hostname') == '$hostname':
        print(node.get('ip_address', ''))
        break
")

    if [[ -n "$node_ip" ]]; then
        echo "  scp /etc/slurm/gres.conf $hostname:/tmp/"
        echo "  ssh $hostname 'sudo mv /tmp/gres.conf /etc/slurm/ && sudo chown slurm:slurm /etc/slurm/gres.conf'"
    fi
done <<< "$GRES_INFO"

echo ""
echo "방법 2: 자동 배포 (추천)"
echo ""
echo "  # compute/viz 노드 재배포 시 자동으로 gres.conf 복사됨"
echo "  ./offline_deploy/deploy_to_compute_node.sh --all"
echo ""

log_info "slurmctld 재시작 필요:"
echo "  sudo systemctl restart slurmctld"
echo ""

log_success "완료!"
