#!/bin/bash
# GlusterFS 마운트 복구 스크립트
# 리부팅 후 /mnt/gluster가 마운트 해제되었을 때 실행
# Usage: sudo ./fix_gluster_mount.sh [--config CONFIG_FILE]

# root 권한 확인
if [[ "$EUID" -ne 0 ]]; then
    echo "❌ root 권한 필요: sudo $0 $*"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 설정 파일 파싱
CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# config 파일 자동 탐색
if [[ -z "$CONFIG_FILE" ]]; then
    for candidate in \
        "$SCRIPT_DIR/my_multihead_cluster_2.yaml" \
        "$SCRIPT_DIR/my_multihead_cluster.yaml" \
        "$SCRIPT_DIR/my_cluster.yaml" \
        "$SCRIPT_DIR/dev_cluster.yaml"; do
        if [[ -f "$candidate" ]]; then
            CONFIG_FILE="$candidate"
            break
        fi
    done
fi

if [[ -z "$CONFIG_FILE" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ config 파일을 찾을 수 없습니다."
    echo "   Usage: sudo $0 --config my_cluster.yaml"
    exit 1
fi

echo "  config: $CONFIG_FILE"

# YAML에서 GlusterFS 설정 읽기
GLUSTER_CONFIG=$(python3 << EOPY
import yaml, json, sys

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

gluster = config.get('shared_storage', {}).get('glusterfs', {})
volume_name = gluster.get('volume_name', 'shared_data')
brick_path  = gluster.get('brick_path', '/srv/glusterfs/brick')
mount_point = gluster.get('mount_point', '/mnt/gluster')

# 첫 번째 controller IP를 gluster 서버로 사용
controllers = config.get('nodes', {}).get('controllers', [])
gluster_server = controllers[0]['ip_address'] if controllers else 'localhost'

print(json.dumps({
    'volume_name':  volume_name,
    'brick_path':   brick_path,
    'mount_point':  mount_point,
    'gluster_server': gluster_server
}))
EOPY
)

if [[ -z "$GLUSTER_CONFIG" ]]; then
    echo "❌ YAML 파싱 실패"
    exit 1
fi

VOLUME_NAME=$(python3  -c "import json; print(json.loads('''$GLUSTER_CONFIG''')['volume_name'])")
BRICK_PATH=$(python3   -c "import json; print(json.loads('''$GLUSTER_CONFIG''')['brick_path'])")
MOUNT_POINT=$(python3  -c "import json; print(json.loads('''$GLUSTER_CONFIG''')['mount_point'])")
GLUSTER_SERVER=$(python3 -c "import json; print(json.loads('''$GLUSTER_CONFIG''')['gluster_server'])")

echo "=========================================="
echo "  GlusterFS 마운트 복구"
echo "=========================================="
echo ""
echo "  volume   : $VOLUME_NAME"
echo "  brick    : $BRICK_PATH"
echo "  mount    : $MOUNT_POINT"
echo "  server   : $GLUSTER_SERVER"
echo ""

# 1. glusterd 확인 및 시작
echo "1️⃣  glusterd 서비스 확인..."
if ! systemctl is-active --quiet glusterd; then
    echo "  → glusterd 시작 중..."
    systemctl start glusterd
    sleep 3
fi
echo "  ✓ glusterd 실행 중"

# 2. Brick 디렉토리 확인
echo ""
echo "2️⃣  Brick 디렉토리 확인..."
if [[ ! -d "$BRICK_PATH" ]]; then
    echo "  ❌ Brick 디렉토리 없음: $BRICK_PATH"
    exit 1
fi
echo "  ✓ Brick 존재: $BRICK_PATH"

# 3. 볼륨 상태 확인 및 시작
echo ""
echo "3️⃣  GlusterFS 볼륨 상태 확인..."
VOLUME_STATUS=$(gluster volume info "$VOLUME_NAME" 2>/dev/null | grep "Status:" | awk '{print $2}' || echo "unknown")
echo "  볼륨 상태: $VOLUME_STATUS"

if [[ "$VOLUME_STATUS" != "Started" ]]; then
    echo "  → 볼륨 시작 중..."
    echo "y" | gluster volume start "$VOLUME_NAME" 2>/dev/null || true
    sleep 3
    VOLUME_STATUS=$(gluster volume info "$VOLUME_NAME" 2>/dev/null | grep "Status:" | awk '{print $2}' || echo "unknown")
    echo "  볼륨 상태: $VOLUME_STATUS"
fi

# 4. Brick 온라인 확인 (오프라인이면 volume 재시작)
echo ""
echo "4️⃣  Brick 온라인 확인..."
BRICK_ONLINE=$(gluster volume status "$VOLUME_NAME" 2>/dev/null | grep "Brick\|Online" | grep -oP '(?<=Online\s{2})\S+' | head -1 || echo "")
# 대안 파싱
if [[ -z "$BRICK_ONLINE" ]]; then
    BRICK_ONLINE=$(gluster volume status "$VOLUME_NAME" 2>/dev/null | awk '/Online/{print $NF}' | head -1)
fi
echo "  Brick Online: ${BRICK_ONLINE:-N}"

if [[ "$BRICK_ONLINE" != "Y" ]]; then
    echo "  → Brick 재시작 시도 (volume stop/start)..."
    echo "y" | gluster volume stop "$VOLUME_NAME" force 2>/dev/null || true
    sleep 2
    echo "y" | gluster volume start "$VOLUME_NAME" 2>/dev/null || true
    sleep 5
fi

# 5. 마운트
echo ""
echo "5️⃣  $MOUNT_POINT 마운트 확인..."
mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
    echo "  ✓ 이미 마운트되어 있음"
else
    echo "  → 마운트 중 (localhost:/$VOLUME_NAME → $MOUNT_POINT)..."
    mount -t glusterfs "localhost:/$VOLUME_NAME" "$MOUNT_POINT" 2>/dev/null || \
    mount -t glusterfs "$GLUSTER_SERVER:/$VOLUME_NAME" "$MOUNT_POINT" || {
        echo "  ❌ 마운트 실패"
        exit 1
    }
    sleep 2

    if mountpoint -q "$MOUNT_POINT"; then
        echo "  ✓ 마운트 성공"
    else
        echo "  ❌ 마운트 실패"
        exit 1
    fi
fi

# 6. Slurm 필요 디렉토리 확인/생성 (YAML directories 기반)
echo ""
echo "6️⃣  Slurm 디렉토리 확인..."
DIRECTORIES=$(python3 << EOPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
dirs = config.get('shared_storage', {}).get('glusterfs', {}).get('directories', [
    'slurm/logs', 'slurm/state', 'slurm/spool', 'logs', 'jobs'
])
print('\n'.join(dirs))
EOPY
)

while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    if [[ ! -d "$MOUNT_POINT/$dir" ]]; then
        echo "  → 생성: $MOUNT_POINT/$dir"
        mkdir -p "$MOUNT_POINT/$dir"
        chown slurm:slurm "$MOUNT_POINT/$dir" 2>/dev/null || true
    fi
done <<< "$DIRECTORIES"
echo "  ✓ 디렉토리 확인 완료"

# 7. slurmctld 재시작
echo ""
echo "7️⃣  slurmctld 재시작..."
systemctl restart slurmctld
sleep 3

if systemctl is-active --quiet slurmctld; then
    echo "  ✓ slurmctld 실행 중"
else
    echo "  ❌ slurmctld 시작 실패"
    journalctl -u slurmctld -n 10 --no-pager
    exit 1
fi

# 8. 노드 상태 복구
echo ""
echo "8️⃣  노드 상태 복구 (down → resume)..."
sleep 2
SCONTROL_BIN=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")
$SCONTROL_BIN update NodeName=ALL State=RESUME 2>/dev/null || true
echo "  ✓ 완료"

echo ""
echo "=========================================="
echo "  ✅ 복구 완료"
echo "=========================================="
echo ""
SINFO_BIN=$(which sinfo 2>/dev/null || echo "/usr/local/slurm/bin/sinfo")
$SINFO_BIN -N -l 2>/dev/null || true
