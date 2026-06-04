#!/bin/bash
# ============================================================================
# VNC + VirtualGL (GPU) .sif 빌드 스크립트
# - vnc_desktop_gpu.def / _2404.def 로부터 .sif 생성
# - 결과: /opt/apptainers/vnc_desktop_gpu.sif (백엔드 VNC_IMAGES 가 찾는 경로)
# 예상 소요: 15-25분 (베이스 이미지 pull + apt + VirtualGL)
#
# 전제:
#   - 빌드 노드에 네트워크 필요 (nvidia/cuda 베이스 pull + apt + VirtualGL .deb).
#     완전 오프라인이면 미리 다른 곳에서 빌드해 .sif 를 복사해도 됨.
#   - GPU 드라이버(nvidia-smi)는 '실행' 노드 호스트에 있으면 됨(빌드엔 불필요).
#     런타임에 apptainer --nv 가 호스트 드라이버/EGL 을 주입함.
#   - /opt/apptainers 는 노드-로컬 → 빌드 후 모든 viz 노드로 배포 필요(아래 안내).
# ============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# OS 감지 — 24.04이면 _2404.def
PROJECT_ROOT_DETECT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "${PROJECT_ROOT_DETECT}/cluster/utils/detect_os.sh" ]; then
    source "${PROJECT_ROOT_DETECT}/cluster/utils/detect_os.sh"
    detect_os_version
fi
if [[ "$OS_VERSION" == "24.04" || "$OS_CODENAME" == "noble" ]]; then
    DEF_FILE="$SCRIPT_DIR/vnc_desktop_gpu_2404.def"
else
    DEF_FILE="$SCRIPT_DIR/vnc_desktop_gpu.def"
fi

IMAGES_DIR="${VNC_IMAGES_DIR:-/opt/apptainers}"
SIF_PATH="$IMAGES_DIR/vnc_desktop_gpu.sif"
LOG_FILE="$SCRIPT_DIR/build_gpu.log"

echo "=== VNC GPU(VirtualGL) Build ==="
echo "Definition : $DEF_FILE"
echo "Output sif : $SIF_PATH"
echo "Build log  : $LOG_FILE"
echo

[ -f "$DEF_FILE" ] || { echo "ERROR: def 없음: $DEF_FILE"; exit 1; }
sudo mkdir -p "$IMAGES_DIR"

# 기존 sif 백업
if [ -f "$SIF_PATH" ]; then
    BK="${SIF_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "기존 sif 백업: $BK"
    sudo mv "$SIF_PATH" "$BK"
fi

echo "빌드 시작 (15-25분)..."
# 권한 따라 fakeroot 또는 sudo. /opt/apptainers 쓰기권한 없으면 sudo 빌드.
if apptainer build "$SIF_PATH" "$DEF_FILE" 2>&1 | tee "$LOG_FILE"; then
    BUILD_RC=0
else
    echo "fakeroot 빌드 실패 → sudo 로 재시도..."
    sudo apptainer build "$SIF_PATH" "$DEF_FILE" 2>&1 | tee -a "$LOG_FILE"
    BUILD_RC=${PIPESTATUS[0]}
fi

echo
if [ "${BUILD_RC:-1}" -eq 0 ] && [ -f "$SIF_PATH" ]; then
    echo "✅ 빌드 성공: $SIF_PATH ($(du -sh "$SIF_PATH" | cut -f1))"
    echo
    echo "── 검증 (이 노드에 GPU+드라이버 있으면) ──"
    echo "  apptainer exec --nv $SIF_PATH nvidia-smi"
    echo "  apptainer exec --nv $SIF_PATH vglrun -d egl glxinfo | grep 'OpenGL renderer'"
    echo "    → 'NVIDIA ...' 면 GPU 렌더 성공 (llvmpipe 면 소프트웨어)"
    echo
    echo "── 배포 (★ /opt/apptainers 는 노드-로컬 → 모든 viz 노드로 복사 필요) ──"
    echo "  방법1) dashboard/setup_apptainer_registry.sh 로 일괄 배포"
    echo "  방법2) 수동: 각 viz 노드로"
    echo "         for n in <viz노드들>; do scp -O $SIF_PATH \$n:$IMAGES_DIR/; done"
    echo
    echo "── 백엔드 활성화 ──"
    echo "  vnc_api.py VNC_IMAGES 에 'xfce4_gpu' 항목이 이미 있음(이 PR). 배포 후"
    echo "  dashboard/start_production.sh 재기동하면 웹 이미지 목록에 'XFCE4 (GPU)' 노출."
    echo "  사용 시 GPU 개수>=1 로 세션 생성해야 --nv 가 붙어 GPU 사용."
    exit 0
else
    echo "❌ 빌드 실패 — 로그 확인: $LOG_FILE"
    exit 1
fi
