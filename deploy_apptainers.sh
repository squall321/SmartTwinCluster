#!/bin/bash
# Apptainer 이미지 배포 스크립트
# my_cluster.yaml 설정에 따라 각 노드에 로컬 복사

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/my_cluster.yaml"

# 옵션 플래그
UPDATE_ONLY=false  # --update: 이미지만 업데이트 (Apptainer 설치 스킵)
SKIP_APPTAINER_INSTALL=false

# 인자 파싱
for arg in "$@"; do
    case $arg in
        --update)
            UPDATE_ONLY=true
            SKIP_APPTAINER_INSTALL=true
            shift
            ;;
        --skip-install)
            SKIP_APPTAINER_INSTALL=true
            shift
            ;;
        --help|-h)
            echo "사용법: $0 [옵션]"
            echo ""
            echo "옵션:"
            echo "  --update        이미지만 업데이트 (Apptainer 설치 스킵)"
            echo "  --skip-install  Apptainer 설치 스킵"
            echo "  --help, -h      이 도움말 표시"
            echo ""
            echo "예시:"
            echo "  $0              # 전체 배포 (Apptainer + 이미지)"
            echo "  $0 --update     # 이미지만 업데이트"
            exit 0
            ;;
    esac
done

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

# 노드 목록 (my_cluster.yaml에서 읽기)
declare -A NODE_IPS
declare -A NODE_TYPES

# compute 노드
NODE_IPS[node001]="192.168.122.90"
NODE_TYPES[node001]="compute"

NODE_IPS[node002]="192.168.122.103"
NODE_TYPES[node002]="compute"

# viz 노드
NODE_IPS[viz-node001]="192.168.122.252"
NODE_TYPES[viz-node001]="viz"

# SSH 사용자
SSH_USER="koopark"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

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

            # 원격에서 압축 해제 및 설치
            ssh $SSH_OPTS ${SSH_USER}@${ip} "cd /tmp && tar -xzf apptainer-binary-1.3.3.tar.gz && sudo install -m 755 apptainer /usr/local/bin/ && sudo install -m 644 apptainer.conf /usr/local/etc/ && rm -f apptainer apptainer.conf apptainer-binary-1.3.3.tar.gz && apptainer --version" || {
                echo -e "${RED}[${node}]${NC} ⚠️  Apptainer 설치 실패 - 계속 진행"
            }

            echo -e "${GREEN}[${node}]${NC} ✅ Apptainer installed"
        else
            echo -e "${GREEN}[${node}]${NC} ✅ Apptainer already installed"
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

    # /scratch 작업 디렉토리들 (사용자 쓰기 가능)
    ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mkdir -p ${NODE_SCRATCH_PATH}/{vnc_sandboxes,vnc_sessions,vnc_logs} && sudo chown ${SSH_USER}:${SSH_USER} ${NODE_SCRATCH_PATH}/{vnc_sandboxes,vnc_sessions,vnc_logs}" || {
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

                    # /opt/apptainers로 전송 (sudo 필요)
                    for img in ${COMPUTE_IMAGES_SOURCE}/*.sif; do
                        local img_name=$(basename "$img")
                        local img_size=$(du -h "$img" | cut -f1)
                        echo -e "${YELLOW}[${node}]${NC}   → $img_name ($img_size)"

                        # 임시로 홈에 복사 후 sudo로 /opt로 이동
                        scp $SSH_OPTS "$img" ${SSH_USER}@${ip}:/tmp/ || {
                            echo -e "${RED}[${node}]${NC} ❌ $img_name 전송 실패"
                            continue
                        }

                        ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mv /tmp/$img_name ${NODE_IMAGE_PATH}/ && sudo chown root:root ${NODE_IMAGE_PATH}/$img_name && sudo chmod 755 ${NODE_IMAGE_PATH}/$img_name" || {
                            echo -e "${RED}[${node}]${NC} ❌ $img_name 설치 실패"
                            continue
                        }
                    done

                    echo -e "${GREEN}[${node}]${NC} ✅ Compute 이미지 배포 완료"
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

            # 모든 .sif 파일 전송
            for img in ${VIZ_IMAGES_SOURCE}/*.sif; do
                local img_name=$(basename "$img")
                local img_size=$(du -h "$img" | cut -f1)
                echo -e "${YELLOW}[${node}]${NC}   → $img_name ($img_size)"

                # 임시로 /tmp에 복사 후 sudo로 /opt로 이동
                scp $SSH_OPTS "$img" ${SSH_USER}@${ip}:/tmp/ || {
                    echo -e "${RED}[${node}]${NC} ❌ $img_name 전송 실패"
                    continue
                }

                ssh $SSH_OPTS ${SSH_USER}@${ip} "sudo mv /tmp/$img_name ${NODE_IMAGE_PATH}/ && sudo chown root:root ${NODE_IMAGE_PATH}/$img_name && sudo chmod 755 ${NODE_IMAGE_PATH}/$img_name" || {
                    echo -e "${RED}[${node}]${NC} ❌ $img_name 설치 실패"
                    continue
                }
            done

            echo -e "${GREEN}[${node}]${NC} ✅ VNC 이미지 배포 완료"
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

# Controller 먼저 배포
echo ""
echo "=========================================="
echo "Controller 로컬 배포"
echo "=========================================="
deploy_to_node "controller" "localhost" "controller"

# 모든 노드에 배포
for node in "${!NODE_IPS[@]}"; do
    deploy_to_node "$node" "${NODE_IPS[$node]}" "${NODE_TYPES[$node]}"
done

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Apptainer 이미지 배포 완료!${NC}"
echo "=========================================="
echo ""
echo "📁 배포 구조:"
echo "  이미지:     /opt/apptainers/*.sif"
echo "  샌드박스:   /scratch/vnc_sandboxes/"
echo "  세션:       /scratch/vnc_sessions/"
echo "  로그:       /scratch/vnc_logs/"
echo ""
echo "확인 명령어:"
echo "  sudo ls -lh /opt/apptainers/                                    # 로컬"
echo "  ssh ${SSH_USER}@192.168.122.90 'sudo ls -lh /opt/apptainers/'   # node001"
echo "  ssh ${SSH_USER}@192.168.122.103 'sudo ls -lh /opt/apptainers/'  # node002"
echo "  ssh ${SSH_USER}@192.168.122.252 'sudo ls -lh /opt/apptainers/'  # viz-node001"
echo ""
