#!/usr/bin/env bash
# VNC/GPU (.sif) 이미지만 → Google Drive 업로드 (viz-node-images 전용) + 옵션 메일 알림
#
# push-apptainers.sh 의 검증된 rclone 증분(copy --update) 로직을 재사용하되,
# 계산노드(~17G)·data(~41G)는 건너뛰고 apptainer/viz-node-images 폴더만 올린다.
#
# --mail : 업로드 후 GPU sif 들에 대해 메일 알림(SmartTwin Preprocessor 와 동일한
#          ~/.config/smartTwinMailer.env 설정/수신자 재사용 → squall321@gmail.com,
#          koo.park@samsung.com). notify_vnc_build.py 가 공유링크+크기+md5 를 메일로.
#
# 사용:
#   ./push-vnc-images.sh                      # 업로드만
#   ./push-vnc-images.sh --mail               # 업로드 + 메일 알림
#   ./push-vnc-images.sh --mail --note "+gpu" # 매니페스트 메모 포함
#
# 사내쪽: ./pull-apptainers.sh  (viz-node-images 기본 포함)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VIZ_DIR="$REPO_ROOT/apptainer/viz-node-images"

[[ -d "$VIZ_DIR" ]] || { echo "❌ $VIZ_DIR 없음"; exit 1; }
[[ -x "$SCRIPT_DIR/push-apptainers.sh" ]] || { echo "❌ push-apptainers.sh 없음/실행불가"; exit 1; }

# --mail 분리, 나머지 인자는 push-apptainers.sh 로 패스스루
DO_MAIL=0
PASS_ARGS=()
for a in "$@"; do
    if [[ "$a" == "--mail" ]]; then DO_MAIL=1; else PASS_ARGS+=("$a"); fi
done

echo "═══ VNC/GPU 이미지만 Drive 업로드 (viz-node-images) ═══"
"$SCRIPT_DIR/push-apptainers.sh" --dirs "$VIZ_DIR" "${PASS_ARGS[@]}"

if [[ "$DO_MAIL" == "1" ]]; then
    echo ""
    echo "═══ 메일 알림 (GPU sif) ═══"
    # 원격 경로: push-apptainers.sh 와 동일 규칙 (STC_DRIVE_REMOTE 의 상위 + apptainer-images)
    source "$SCRIPT_DIR/.drive-sync.env"
    REMOTE_BASE="${STC_DRIVE_REMOTE%/*}/apptainer-images/viz-node-images"
    # GPU sif 들 (vnc_*_gpu*.sif / vnc_desktop_gpu*.sif)
    mapfile -t GPU_SIFS < <(ls "$VIZ_DIR"/*_gpu*.sif 2>/dev/null)
    if [[ ${#GPU_SIFS[@]} -eq 0 ]]; then
        echo "  (GPU sif 없음 — 메일 스킵)"
    else
        python3 "$SCRIPT_DIR/notify_vnc_build.py" "$REMOTE_BASE" "${GPU_SIFS[@]}"
    fi
fi
