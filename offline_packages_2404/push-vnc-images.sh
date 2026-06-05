#!/usr/bin/env bash
# VNC/GPU (.sif) 이미지만 → Google Drive 업로드 (viz-node-images 전용)
#
# push-apptainers.sh 의 검증된 rclone 증분(copy --update) 로직을 그대로 재사용하되,
# 계산노드(compute-node-images ~17G)·data(~41G)는 건너뛰고 apptainer/viz-node-images
# 폴더(VNC 데스크톱 + GPU 변이들)만 올린다. → 대형 폴더 스캔 없이 VNC 만 빠르게 동기화.
#
# 올라가는 것: apptainer/viz-node-images/*.sif + *.json
#   vnc_desktop.sif, vnc_gnome*.sif (기존) +
#   vnc_desktop_gpu.sif(light), vnc_desktop_gpu_cuda_runtime/cuda_dev.sif, vnc_gnome_gpu.sif (GPU)
#
# 사용:
#   ./push-vnc-images.sh                    # viz-node-images 전부 (증분)
#   ./push-vnc-images.sh --note "+gpu변이"  # 매니페스트 메모
#
# 사내쪽: ./pull-apptainers.sh  (viz-node-images 기본 포함 — 같이 받아짐)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VIZ_DIR="$REPO_ROOT/apptainer/viz-node-images"

[[ -d "$VIZ_DIR" ]] || { echo "❌ $VIZ_DIR 없음"; exit 1; }
[[ -x "$SCRIPT_DIR/push-apptainers.sh" ]] || { echo "❌ push-apptainers.sh 없음/실행불가"; exit 1; }

echo "═══ VNC/GPU 이미지만 Drive 업로드 (viz-node-images) ═══"
exec "$SCRIPT_DIR/push-apptainers.sh" --dirs "$VIZ_DIR" "$@"
