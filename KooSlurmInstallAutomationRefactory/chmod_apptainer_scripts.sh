#!/bin/bash

################################################################################
# Apptainer 관련 모든 스크립트에 실행 권한 부여
################################################################################

echo "🔧 Apptainer 관련 스크립트 실행 권한 설정 중..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 실행 권한 부여할 스크립트 목록
scripts=(
    "sync_apptainers_to_nodes.sh"
    "setup_apptainer_features.sh"
    "test_apptainer_sync.sh"
    "debug_apptainer_sync.sh"
    "create_remote_apptainer_dirs.sh"
    "install_pyyaml.sh"
)

success=0
failed=0

for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
        chmod +x "$script"
        if [ $? -eq 0 ]; then
            echo "✅ $script"
            success=$((success + 1))
        else
            echo "❌ $script (권한 설정 실패)"
            failed=$((failed + 1))
        fi
    else
        echo "⚠️  $script (파일 없음)"
        failed=$((failed + 1))
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "성공: $success, 실패: $failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $failed -eq 0 ]; then
    echo "✨ 모든 스크립트 권한 설정 완료!"
    echo ""
    echo "다음 명령으로 설정을 확인하세요:"
    echo "  ./setup_apptainer_features.sh"
    exit 0
else
    echo "⚠️  일부 스크립트 권한 설정 실패"
    exit 1
fi
