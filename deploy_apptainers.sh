#!/bin/bash
# Apptainer 이미지 배포 스크립트
# my_cluster.yaml 설정에 따라 각 노드에 로컬 복사

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/my_multihead_cluster_2.yaml"

# 옵션 플래그
UPDATE_ONLY=false  # --update: 이미지만 업데이트 (Apptainer 설치 스킵)
SKIP_APPTAINER_INSTALL=false
TARGET_IMAGE=""    # --image: 특정 이미지만 배포

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --update)
            UPDATE_ONLY=true
            SKIP_APPTAINER_INSTALL=true
            shift
            ;;
        --skip-install)
            SKIP_APPTAINER_INSTALL=true
            shift
            ;;
        --image)
            TARGET_IMAGE="$2"
            SKIP_APPTAINER_INSTALL=true
            shift 2
            ;;
        --help|-h)
            echo "사용법: $0 [옵션]"
            echo ""
            echo "옵션:"
            echo "  --config FILE   YAML 설정 파일 지정 (기본: my_multihead_cluster_2.yaml)"
            echo "  --update        이미지만 업데이트 (Apptainer 설치 스킵)"
            echo "  --skip-install  Apptainer 설치 스킵"
            echo "  --image FILE    특정 SIF 이미지만 모든 노드에 배포"
            echo "  --help, -h      이 도움말 표시"
            echo ""
            echo "예시:"
            echo "  $0                                    # 전체 배포 (기본 YAML)"
            echo "  $0 --config my_cluster.yaml           # 다른 YAML 파일 사용"
            echo "  $0 --update                           # 이미지만 업데이트"
            echo "  $0 --image vnc_gnome_lsprepost.sif    # 특정 이미지만 배포"
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            echo "$0 --help 로 사용법 확인"
            exit 1
            ;;
    esac
done

# YAML 파일 확인
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
if [ "$UPDATE_ONLY" = true ]; then
    echo "Apptainer 이미지 업데이트"
else
    echo "Apptainer 바이너리 및 이미지 배포"
fi
echo "=========================================="

# 새로운 경로 구조
# 원본: 프로젝트 내 apptainer 디렉토리
PROJECT_APPTAINER_DIR="$SCRIPT_DIR/apptainer"
COMPUTE_IMAGES_SOURCE="$PROJECT_APPTAINER_DIR/compute-node-images"
VIZ_IMAGES_SOURCE="$PROJECT_APPTAINER_DIR/viz-node-images"

# 배포 대상: 각 노드의 /opt/apptainers (읽기 전용 이미지)
NODE_IMAGE_PATH="/opt/apptainers"

# 작업 디렉토리: /scratch (쓰기 가능)
NODE_SCRATCH_PATH="/scratch"

# 노드 목록 (YAML에서 자동으로 읽기)
declare -A NODE_IPS
declare -A NODE_TYPES

echo "YAML 설정 파일에서 노드 정보 로딩: $CONFIG_FILE"

# Python으로 YAML 파싱하여 노드 정보 추출
read -r -d '' PYTHON_SCRIPT << 'EOPY' || true
import yaml
import sys

try:
    with open(sys.argv[1], 'r') as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to read YAML: {e}", file=sys.stderr)
    sys.exit(1)

nodes = config.get('nodes', {})

# compute_nodes
for node in nodes.get('compute_nodes', []):
    hostname = node.get('hostname', '')
    ip = node.get('ip_address', '')
    if hostname and ip:
        print(f"{hostname}|{ip}|compute")

# viz_nodes
for node in nodes.get('viz_nodes', []):
    hostname = node.get('hostname', '')
    ip = node.get('ip_address', '')
    if hostname and ip:
        print(f"{hostname}|{ip}|viz")
EOPY

# YAML에서 노드 정보 읽기
NODE_COUNT=0
while IFS='|' read -r hostname ip node_type; do
    if [[ -z "$hostname" ]]; then
        continue
    fi
    NODE_IPS[$hostname]="$ip"
    NODE_TYPES[$hostname]="$node_type"
    NODE_COUNT=$((NODE_COUNT + 1))
done < <(python3 -c "$PYTHON_SCRIPT" "$CONFIG_FILE")

if [[ $NODE_COUNT -eq 0 ]]; then
    echo "ERROR: No compute_nodes or viz_nodes found in YAML"
    exit 1
fi

echo "총 $NODE_COUNT 개 노드 발견 (compute + viz)"

# SSH 사용자 (YAML에서 읽기, 기본값: koopark)
SSH_USER=$(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)
    # compute_nodes의 첫 번째 노드에서 ssh_user 읽기
    nodes = config.get('nodes', {}).get('compute_nodes', [])
    if nodes:
        print(nodes[0].get('ssh_user', 'koopark'))
    else:
        print('koopark')
except:
    print('koopark')
" 2>/dev/null || echo "koopark")

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SSH_TIMEOUT="-o ConnectTimeout=10"

echo "SSH 사용자: $SSH_USER"

# 이미지 변경 비교 함수
# 로컬 vs 원격: 파일 크기 + 수정 시각(mtime) 비교
# 크기가 다르면 → 전송
# 크기 같아도 로컬이 더 최신이면 → 전송 (재빌드 감지)
# 크기 같고 로컬이 더 오래되었으면 → 스킵
image_needs_update() {
    local img_path="$1"
    local remote_ip="$2"
    local remote_path="$3"
    local img_name
    img_name=$(basename "$img_path")

    # 로컬 크기 + mtime (epoch seconds)
    local local_size
    local_size=$(stat -c%s "$img_path" 2>/dev/null || echo 0)
    local local_mtime
    local_mtime=$(stat -c%Y "$img_path" 2>/dev/null || echo 0)

    # 원격 크기 + mtime (한 번의 SSH로 둘 다 가져옴)
    local remote_info
    remote_info=$(ssh $SSH_OPTS $SSH_TIMEOUT ${SSH_USER}@${remote_ip} \
        "sudo stat -c'%s %Y' '${remote_path}/${img_name}' 2>/dev/null || echo '0 0'" 2>/dev/null || echo "0 0")
    local remote_size
    remote_size=$(echo "$remote_info" | awk '{print $1}')
    local remote_mtime
    remote_mtime=$(echo "$remote_info" | awk '{print $2}')

    # 원격에 파일 없음 → 전송 필요
    if [[ "$remote_size" -eq 0 ]]; then
        return 0
    fi

    # 크기 다름 → 전송 필요
    if [[ "$local_size" -ne "$remote_size" ]]; then
        return 0
    fi

    # 크기 같지만 로컬이 더 최신 → 전송 필요 (재빌드)
    if [[ "$local_mtime" -gt "$remote_mtime" ]]; then
        return 0
    fi

    # 크기 동일 + 로컬이 같거나 오래됨 → 스킵
    return 1
}
echo ""

# gres.conf 확인 (GPU 노드가 있으면 경고)
if [[ $NODE_COUNT -gt 0 ]]; then
    GRES_CONF_PATH="/etc/slurm/gres.conf"
    if [[ ! -f "$GRES_CONF_PATH" ]]; then
        # YAML에서 GPU 노드가 있는지 확인
        GPU_NODE_COUNT=$(python3 <<EOPY
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
nodes = config.get('nodes', {})
gpu_count = 0
for node in nodes.get('compute_nodes', []) + nodes.get('viz_nodes', []):
    if node.get('gpus', 0) > 0:
        gpu_count += 1
print(gpu_count)
EOPY
)
        if [[ "$GPU_NODE_COUNT" -gt 0 ]]; then
            echo -e "${YELLOW}WARNING:${NC} GPU nodes detected in YAML but gres.conf not found!"
            echo -e "${YELLOW}         ${NC} Run this to generate gres.conf:"
            echo -e "${YELLOW}         ${NC}   cd cluster/setup && sudo ./phase3_slurm.sh --config ../../$CONFIG_FILE"
            echo -e "${YELLOW}         ${NC} Or deploy compute nodes first:"
            echo -e "${YELLOW}         ${NC}   ./offline_deploy/deploy_to_compute_node.sh --all"
            echo ""
        fi
    fi
fi

# 배포 함수
deploy_to_node() {
    local node=$1
    local ip=$2
    local node_type=$3

    echo ""
    echo -e "${YELLOW}[${node}]${NC} 배포 시작 (Type: ${node_type}, IP: ${ip})"

    # 노드 접속 확인
    if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "exit" 2>/dev/null; then
        echo -e "${RED}[${node}]${NC} ❌ SSH 접속 실패 - 스킵"
        return 1
    fi

    # Apptainer 설치 확인 및 설치
    if [ "$SKIP_APPTAINER_INSTALL" = false ]; then
        echo -e "${YELLOW}[${node}]${NC} Apptainer 확인 중..."
        if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "command -v apptainer" &>/dev/null; then
            echo -e "${YELLOW}[${node}]${NC} Apptainer 설치 중 (로컬 바이너리 복사)..."

            # 로컬 바이너리 tar 파일 복사
            scp $SSH_OPTS ${SCRIPT_DIR}/apptainer/apptainer-binary-1.3.3.tar.gz ${SSH_USER}@${ip}:/tmp/ || {
                echo -e "${RED}[${node}]${NC} ❌ Apptainer 바이너리 복사 실패"
                return 1
            }

            # 원격에서 압축 해제 및 설치 (바이너리 + squashfuse_ll + libfuse + etc + libexec + var)
            ssh $SSH_OPTS ${SSH_USER}@${ip} "cd /tmp && tar -xzf apptainer-binary-1.3.3.tar.gz && \
                sudo install -m 755 apptainer /usr/local/bin/ && \
                sudo install -m 755 squashfuse_ll /usr/local/bin/ && \
                sudo cp -a lib/libfuse.so* /lib/x86_64-linux-gnu/ 2>/dev/null; \
                sudo ldconfig && \
                sudo mkdir -p /usr/local/etc && \
                sudo cp -r etc/apptainer /usr/local/etc/ && \
                sudo mkdir -p /usr/local/libexec && \
                sudo cp -r libexec/apptainer /usr/local/libexec/ && \
                sudo chmod 755 /usr/local/libexec/apptainer/bin/starter && \
                sudo mkdir -p /usr/local/var && \
                sudo cp -r var/apptainer /usr/local/var/ && \
                rm -rf apptainer squashfuse_ll lib etc libexec var apptainer-binary-1.3.3.tar.gz && \
                apptainer --version" || {
                echo -e "${RED}[${node}]${NC} ⚠️  Apptainer 설치 실패 - 계속 진행"
            }

            echo -e "${GREEN}[${node}]${NC} ✅ Apptainer installed"
        else
            echo -e "${GREEN}[${node}]${NC} ✅ Apptainer already installed"
            # apptainer.conf 또는 libexec가 없으면 배포 (기존에 바이너리만 설치된 경우)
            local needs_fix=false
            if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "test -f /usr/local/etc/apptainer/apptainer.conf" &>/dev/null; then
                echo -e "${YELLOW}[${node}]${NC} apptainer.conf 누락 감지"
                needs_fix=true
            fi
            if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "test -f /usr/local/libexec/apptainer/bin/starter" &>/dev/null; then
                echo -e "${YELLOW}[${node}]${NC} libexec/apptainer/bin/starter 누락 감지"
                needs_fix=true
            fi
            # capability.json 누락도 체크
            if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "test -f /usr/local/etc/apptainer/capability.json" &>/dev/null; then
                echo -e "${YELLOW}[${node}]${NC} capability.json 누락 감지"
                needs_fix=true
            fi
            # var/apptainer 누락도 체크
            if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "test -d /usr/local/var/apptainer/mnt/session" &>/dev/null; then
                echo -e "${YELLOW}[${node}]${NC} var/apptainer/mnt/session 누락 감지"
                needs_fix=true
            fi
            # squashfuse_ll 누락 체크
            if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "command -v squashfuse_ll" &>/dev/null; then
                echo -e "${YELLOW}[${node}]${NC} squashfuse_ll 누락 감지"
                needs_fix=true
            fi
            # libfuse.so.2 누락 체크
            if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "test -f /lib/x86_64-linux-gnu/libfuse.so.2" &>/dev/null; then
                echo -e "${YELLOW}[${node}]${NC} libfuse.so.2 누락 감지"
                needs_fix=true
            fi
            if [[ "$needs_fix" == "true" ]]; then
                echo -e "${YELLOW}[${node}]${NC} 누락 파일 배포 중..."
                scp $SSH_OPTS ${SCRIPT_DIR}/apptainer/apptainer-binary-1.3.3.tar.gz ${SSH_USER}@${ip}:/tmp/ && \
                ssh $SSH_OPTS ${SSH_USER}@${ip} "cd /tmp && tar -xzf apptainer-binary-1.3.3.tar.gz && \
                    sudo install -m 755 squashfuse_ll /usr/local/bin/ && \
                    sudo cp -a lib/libfuse.so* /lib/x86_64-linux-gnu/ 2>/dev/null; \
                    sudo ldconfig && \
                    sudo mkdir -p /usr/local/etc && \
                    sudo cp -r etc/apptainer /usr/local/etc/ && \
                    sudo mkdir -p /usr/local/libexec && \
                    sudo cp -r libexec/apptainer /usr/local/libexec/ && \
                    sudo chmod 755 /usr/local/libexec/apptainer/bin/starter && \
                    sudo mkdir -p /usr/local/var && \
                    sudo cp -r var/apptainer /usr/local/var/ && \
                    rm -rf apptainer squashfuse_ll lib etc libexec var apptainer-binary-1.3.3.tar.gz" && \
                echo -e "${GREEN}[${node}]${NC} ✅ 누락 파일 배포 완료" || \
                echo -e "${RED}[${node}]${NC} ⚠️  누락 파일 배포 실패"
            fi
        fi
    else
        echo -e "${YELLOW}[${node}]${NC} ⏭️  Apptainer 설치 스킵 (--update 모드)"
    fi

    # 디렉토리 구조 생성
    echo -e "${YELLOW}[${node}]${NC} 디렉토리 구조 생성 중..."

    # /opt/apptainers (이미지 저장, root 소유)
    ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mkdir -p ${NODE_IMAGE_PATH} && sudo chown root:root ${NODE_IMAGE_PATH}" || {
        echo -e "${RED}[${node}]${NC} ❌ /opt/apptainers 생성 실패"
        return 1
    }

    # /scratch 작업 디렉토리들 (모든 사용자 읽기/쓰기 가능)
    # Slurm 잡은 다양한 사용자로 실행되므로 1777 (sticky bit) 적용
    ssh $SSH_OPTS ${SSH_USER}@${ip} "
        sudo mkdir -p ${NODE_SCRATCH_PATH}/{vnc_sandboxes,vnc_sessions,vnc_logs} && \
        sudo chmod 1777 ${NODE_SCRATCH_PATH} && \
        sudo chmod 1777 ${NODE_SCRATCH_PATH}/vnc_sandboxes && \
        sudo chmod 1777 ${NODE_SCRATCH_PATH}/vnc_sessions && \
        sudo chmod 1777 ${NODE_SCRATCH_PATH}/vnc_logs
    " || {
        echo -e "${RED}[${node}]${NC} ❌ /scratch 디렉토리 생성 실패"
        return 1
    }

    echo -e "${GREEN}[${node}]${NC} ✅ 디렉토리 구조 생성 완료"

    # 노드 타입별 이미지 배포
    case $node_type in
        compute)
            echo -e "${YELLOW}[${node}]${NC} Compute 이미지 배포 중..."

            if [ -d "${COMPUTE_IMAGES_SOURCE}" ]; then
                local image_count=$(ls -1 ${COMPUTE_IMAGES_SOURCE}/*.sif 2>/dev/null | wc -l)

                if [ $image_count -gt 0 ]; then
                    echo -e "${YELLOW}[${node}]${NC} ${image_count}개 이미지 전송 중..."

                    # /opt/apptainers로 전송 (변경된 이미지만)
                    local transferred=0
                    local skipped=0
                    for img in ${COMPUTE_IMAGES_SOURCE}/*.sif; do
                        local img_name=$(basename "$img")
                        local img_size=$(du -h "$img" | cut -f1)

                        # 변경 비교: 크기 동일하면 스킵
                        if ! image_needs_update "$img" "$ip" "${NODE_IMAGE_PATH}"; then
                            echo -e "${GREEN}[${node}]${NC}   = $img_name ($img_size) — 동일, 스킵"
                            skipped=$((skipped + 1))
                            continue
                        fi

                        echo -e "${YELLOW}[${node}]${NC}   → $img_name ($img_size) — 전송 중..."

                        scp $SSH_OPTS "$img" ${SSH_USER}@${ip}:/tmp/ || {
                            echo -e "${RED}[${node}]${NC} ❌ $img_name 전송 실패"
                            continue
                        }

                        ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mv /tmp/$img_name ${NODE_IMAGE_PATH}/ && sudo chown root:root ${NODE_IMAGE_PATH}/$img_name && sudo chmod 755 ${NODE_IMAGE_PATH}/$img_name" || {
                            echo -e "${RED}[${node}]${NC} ❌ $img_name 설치 실패"
                            continue
                        }
                        transferred=$((transferred + 1))
                    done

                    echo -e "${GREEN}[${node}]${NC} ✅ Compute 이미지 완료 (전송: ${transferred}, 스킵: ${skipped})"
                else
                    echo -e "${YELLOW}[${node}]${NC} ⚠️  Compute 이미지 없음 - 스킵"
                fi
            else
                echo -e "${YELLOW}[${node}]${NC} ⚠️  ${COMPUTE_IMAGES_SOURCE} 디렉토리 없음"
            fi
            ;;

        viz)
            echo -e "${YELLOW}[${node}]${NC} VNC 이미지 배포 중..."

            if [ ! -d "${VIZ_IMAGES_SOURCE}" ]; then
                echo -e "${RED}[${node}]${NC} ❌ ${VIZ_IMAGES_SOURCE} 디렉토리 없음"
                return 1
            fi

            local image_count=$(ls -1 ${VIZ_IMAGES_SOURCE}/*.sif 2>/dev/null | wc -l)

            if [ $image_count -eq 0 ]; then
                echo -e "${RED}[${node}]${NC} ❌ VNC 이미지 없음"
                echo -e "${YELLOW}[${node}]${NC} 💡 이미지를 ${VIZ_IMAGES_SOURCE}/ 에 배치하세요"
                return 1
            fi

            echo -e "${YELLOW}[${node}]${NC} ${image_count}개 VNC 이미지 전송 중..."

            # 모든 .sif 파일 전송 (변경된 이미지만)
            local transferred=0
            local skipped=0
            for img in ${VIZ_IMAGES_SOURCE}/*.sif; do
                local img_name=$(basename "$img")
                local img_size=$(du -h "$img" | cut -f1)

                # 변경 비교: 크기+날짜 동일하면 스킵
                if ! image_needs_update "$img" "$ip" "${NODE_IMAGE_PATH}"; then
                    echo -e "${GREEN}[${node}]${NC}   = $img_name ($img_size) — 동일, 스킵"
                    skipped=$((skipped + 1))
                    continue
                fi

                echo -e "${YELLOW}[${node}]${NC}   → $img_name ($img_size) — 전송 중..."

                scp $SSH_OPTS "$img" ${SSH_USER}@${ip}:/tmp/ || {
                    echo -e "${RED}[${node}]${NC} ❌ $img_name 전송 실패"
                    continue
                }

                ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mv /tmp/$img_name ${NODE_IMAGE_PATH}/ && sudo chown root:root ${NODE_IMAGE_PATH}/$img_name && sudo chmod 755 ${NODE_IMAGE_PATH}/$img_name" || {
                    echo -e "${RED}[${node}]${NC} ❌ $img_name 설치 실패"
                    continue
                }
                transferred=$((transferred + 1))
            done

            echo -e "${GREEN}[${node}]${NC} ✅ VNC 이미지 완료 (전송: ${transferred}, 스킵: ${skipped})"
            echo -e "${YELLOW}[${node}]${NC} 📁 구조:"
            echo -e "${YELLOW}[${node}]${NC}    ${NODE_IMAGE_PATH}/ (VNC 이미지)"
            echo -e "${YELLOW}[${node}]${NC}    ${NODE_SCRATCH_PATH}/vnc_sandboxes/ (샌드박스)"
            echo -e "${YELLOW}[${node}]${NC}    ${NODE_SCRATCH_PATH}/vnc_sessions/ (세션)"
            echo -e "${YELLOW}[${node}]${NC}    ${NODE_SCRATCH_PATH}/vnc_logs/ (로그)"
            ;;

        controller)
            echo -e "${YELLOW}[${node}]${NC} Controller - 로컬 배포"

            # Controller에도 동일한 디렉토리 구조 생성
            sudo mkdir -p ${NODE_IMAGE_PATH}
            sudo chown root:root ${NODE_IMAGE_PATH}
            mkdir -p ${NODE_SCRATCH_PATH}/{vnc_sandboxes,vnc_sessions,vnc_logs}

            # VNC 이미지 복사 (controller도 VNC 기능 가능)
            if [ -d "${VIZ_IMAGES_SOURCE}" ]; then
                for img in ${VIZ_IMAGES_SOURCE}/*.sif; do
                    local img_name=$(basename "$img")
                    echo -e "${YELLOW}[${node}]${NC}   → $img_name"
                    sudo cp "$img" ${NODE_IMAGE_PATH}/
                    sudo chown root:root ${NODE_IMAGE_PATH}/$img_name
                    sudo chmod 755 ${NODE_IMAGE_PATH}/$img_name
                done
                echo -e "${GREEN}[${node}]${NC} ✅ Controller 배포 완료"
            fi
            ;;

        *)
            echo -e "${RED}[${node}]${NC} ❌ Unknown node type: $node_type"
            return 1
            ;;
    esac

    # 배포 결과 확인
    echo -e "${YELLOW}[${node}]${NC} 배포된 이미지 확인:"
    ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo ls -lh ${NODE_IMAGE_PATH}/ 2>/dev/null || echo '  (없음)'"
    echo -e "${YELLOW}[${node}]${NC} 작업 디렉토리:"
    ssh $SSH_OPTS ${SSH_USER}@${ip} "ls -ld ${NODE_SCRATCH_PATH}/vnc_* 2>/dev/null || echo '  (없음)'"

    echo -e "${GREEN}[${node}]${NC} ✅ 배포 완료"
}

# 프로젝트 이미지 확인
echo ""
echo "프로젝트 이미지 확인: ${PROJECT_APPTAINER_DIR}"
if [ ! -d "${PROJECT_APPTAINER_DIR}" ]; then
    echo -e "${RED}❌ 프로젝트 apptainer 디렉토리 없음: ${PROJECT_APPTAINER_DIR}${NC}"
    echo "먼저 apptainer 디렉토리를 생성하고 이미지를 배치하세요."
    exit 1
fi

echo ""
echo "=== Compute Node Images ==="
ls -lh ${COMPUTE_IMAGES_SOURCE}/ 2>/dev/null || echo "(없음)"
echo ""
echo "=== VNC/Viz Node Images ==="
ls -lh ${VIZ_IMAGES_SOURCE}/ 2>/dev/null || echo "(없음)"
echo ""

# --image 모드: 특정 이미지만 모든 노드에 배포
if [[ -n "$TARGET_IMAGE" ]]; then
    # 이미지 파일 찾기 (compute/viz 소스 디렉토리 양쪽 검색)
    IMAGE_FILE=""
    for search_dir in "${COMPUTE_IMAGES_SOURCE}" "${VIZ_IMAGES_SOURCE}"; do
        if [[ -f "${search_dir}/${TARGET_IMAGE}" ]]; then
            IMAGE_FILE="${search_dir}/${TARGET_IMAGE}"
            break
        fi
    done

    if [[ -z "$IMAGE_FILE" ]]; then
        echo -e "${RED}❌ 이미지 파일을 찾을 수 없음: ${TARGET_IMAGE}${NC}"
        echo "검색 경로:"
        echo "  - ${COMPUTE_IMAGES_SOURCE}/"
        echo "  - ${VIZ_IMAGES_SOURCE}/"
        exit 1
    fi

    IMG_SIZE=$(du -h "$IMAGE_FILE" | cut -f1)
    echo ""
    echo "=========================================="
    echo -e "${YELLOW}특정 이미지 배포 모드${NC}"
    echo "  이미지: ${TARGET_IMAGE} (${IMG_SIZE})"
    echo "  소스:   ${IMAGE_FILE}"
    echo "=========================================="
    echo ""

    IMG_DEPLOY_SUCCESS=0
    IMG_DEPLOY_FAIL=0
    IMG_FAILED_NODES=()

    # Controller 로컬 배포
    echo -e "${YELLOW}[controller]${NC} ${TARGET_IMAGE} 배포 중..."
    if sudo cp "$IMAGE_FILE" ${NODE_IMAGE_PATH}/ && \
       sudo chown root:root ${NODE_IMAGE_PATH}/${TARGET_IMAGE} && \
       sudo chmod 755 ${NODE_IMAGE_PATH}/${TARGET_IMAGE}; then
        echo -e "${GREEN}[controller]${NC} ✅ 배포 완료"
        IMG_DEPLOY_SUCCESS=$((IMG_DEPLOY_SUCCESS + 1))
    else
        echo -e "${RED}[controller]${NC} ❌ 배포 실패"
        IMG_DEPLOY_FAIL=$((IMG_DEPLOY_FAIL + 1))
        IMG_FAILED_NODES+=("controller (localhost)")
    fi

    # 모든 노드에 배포
    for node in "${!NODE_IPS[@]}"; do
        local_ip=$(hostname -I | awk '{print $1}')
        ip="${NODE_IPS[$node]}"

        # 자기 자신은 스킵 (이미 로컬 배포함)
        if [[ "$ip" == "$local_ip" ]]; then
            echo -e "${YELLOW}[${node}]${NC} ⏭️  현재 노드 - 스킵"
            continue
        fi

        echo -e "${YELLOW}[${node}]${NC} ${TARGET_IMAGE} 확인 중 (${ip})..."

        # SSH 접속 확인
        if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "exit" 2>/dev/null; then
            echo -e "${RED}[${node}]${NC} ❌ SSH 접속 실패 - 스킵"
            IMG_DEPLOY_FAIL=$((IMG_DEPLOY_FAIL + 1))
            IMG_FAILED_NODES+=("${node} (${ip})")
            continue
        fi

        # 원격 디렉토리 생성
        ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mkdir -p ${NODE_IMAGE_PATH}" 2>/dev/null

        # 변경 비교: 크기+날짜 동일하면 스킵
        if ! image_needs_update "$IMAGE_FILE" "$ip" "${NODE_IMAGE_PATH}"; then
            echo -e "${GREEN}[${node}]${NC} = ${TARGET_IMAGE} — 동일, 스킵"
            IMG_DEPLOY_SUCCESS=$((IMG_DEPLOY_SUCCESS + 1))
            continue
        fi

        echo -e "${YELLOW}[${node}]${NC}   → ${TARGET_IMAGE} 전송 중..."

        # SIF 전송
        if ! scp $SSH_OPTS "$IMAGE_FILE" ${SSH_USER}@${ip}:/tmp/; then
            echo -e "${RED}[${node}]${NC} ❌ 전송 실패"
            IMG_DEPLOY_FAIL=$((IMG_DEPLOY_FAIL + 1))
            IMG_FAILED_NODES+=("${node} (${ip})")
            continue
        fi

        if ! ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mv /tmp/${TARGET_IMAGE} ${NODE_IMAGE_PATH}/ && sudo chown root:root ${NODE_IMAGE_PATH}/${TARGET_IMAGE} && sudo chmod 755 ${NODE_IMAGE_PATH}/${TARGET_IMAGE}"; then
            echo -e "${RED}[${node}]${NC} ❌ 설치 실패"
            IMG_DEPLOY_FAIL=$((IMG_DEPLOY_FAIL + 1))
            IMG_FAILED_NODES+=("${node} (${ip})")
            continue
        fi

        echo -e "${GREEN}[${node}]${NC} ✅ 배포 완료"
        IMG_DEPLOY_SUCCESS=$((IMG_DEPLOY_SUCCESS + 1))
    done

    IMG_TOTAL=$((IMG_DEPLOY_SUCCESS + IMG_DEPLOY_FAIL))
    echo ""
    echo "=========================================="
    echo "배포 결과 요약 (${TARGET_IMAGE})"
    echo "=========================================="
    echo -e "  전체:  ${IMG_TOTAL} 대"
    echo -e "  ${GREEN}성공:  ${IMG_DEPLOY_SUCCESS} 대${NC}"
    if [[ $IMG_DEPLOY_FAIL -gt 0 ]]; then
        echo -e "  ${RED}실패:  ${IMG_DEPLOY_FAIL} 대${NC}"
        echo ""
        echo -e "${RED}실패한 노드:${NC}"
        for failed in "${IMG_FAILED_NODES[@]}"; do
            echo -e "  ${RED}  ✗ ${failed}${NC}"
        done
    else
        echo -e "  ${GREEN}실패:  0 대${NC}"
    fi
    echo "=========================================="
    exit 0
fi

# 배포 통계 변수
DEPLOY_SUCCESS=0
DEPLOY_FAIL=0
FAILED_NODES=()

# Controller 먼저 배포
echo ""
echo "=========================================="
echo "Controller 로컬 배포"
echo "=========================================="
if deploy_to_node "controller" "localhost" "controller"; then
    DEPLOY_SUCCESS=$((DEPLOY_SUCCESS + 1))
else
    DEPLOY_FAIL=$((DEPLOY_FAIL + 1))
    FAILED_NODES+=("controller (localhost)")
fi

# 모든 노드에 배포 (실패해도 다음 노드로 진행)
for node in "${!NODE_IPS[@]}"; do
    if deploy_to_node "$node" "${NODE_IPS[$node]}" "${NODE_TYPES[$node]}"; then
        DEPLOY_SUCCESS=$((DEPLOY_SUCCESS + 1))
    else
        DEPLOY_FAIL=$((DEPLOY_FAIL + 1))
        FAILED_NODES+=("${node} (${NODE_IPS[$node]})")
    fi
done

DEPLOY_TOTAL=$((DEPLOY_SUCCESS + DEPLOY_FAIL))

echo ""
echo "=========================================="
echo "배포 결과 요약"
echo "=========================================="
echo ""
echo -e "  전체:  ${DEPLOY_TOTAL} 대"
echo -e "  ${GREEN}성공:  ${DEPLOY_SUCCESS} 대${NC}"
if [[ $DEPLOY_FAIL -gt 0 ]]; then
    echo -e "  ${RED}실패:  ${DEPLOY_FAIL} 대${NC}"
    echo ""
    echo -e "${RED}실패한 노드:${NC}"
    for failed in "${FAILED_NODES[@]}"; do
        echo -e "  ${RED}  ✗ ${failed}${NC}"
    done
    echo ""
    echo "실패 노드 재배포:"
    for failed in "${FAILED_NODES[@]}"; do
        local_node=$(echo "$failed" | cut -d' ' -f1)
        echo "  $0 --config $CONFIG_FILE  # ${local_node} 포함 전체 재시도"
    done
else
    echo -e "  ${GREEN}실패:  0 대${NC}"
fi

echo ""
echo "=========================================="
if [[ $DEPLOY_FAIL -eq 0 ]]; then
    echo -e "${GREEN}✅ Apptainer 이미지 배포 완료! (${DEPLOY_SUCCESS}/${DEPLOY_TOTAL} 성공)${NC}"
else
    echo -e "${YELLOW}⚠️  Apptainer 이미지 배포 부분 완료 (${DEPLOY_SUCCESS}/${DEPLOY_TOTAL} 성공, ${DEPLOY_FAIL} 실패)${NC}"
fi
echo "=========================================="
echo ""
echo "📁 배포 구조:"
echo "  이미지:     /opt/apptainers/*.sif"
echo "  샌드박스:   /scratch/vnc_sandboxes/"
echo "  세션:       /scratch/vnc_sessions/"
echo "  로그:       /scratch/vnc_logs/"
echo ""
