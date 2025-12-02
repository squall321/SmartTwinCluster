#!/bin/bash
# 모든 새 스크립트에 실행 권한 부여

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "$SCRIPT_DIR"/*.py 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/job_templates/*.sh 2>/dev/null || true

echo "✅ 모든 스크립트에 실행 권한이 부여되었습니다!"
