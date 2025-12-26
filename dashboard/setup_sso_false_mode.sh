#!/bin/bash
################################################################################
# SSO False 모드 설정 스크립트 (오프라인 서버용)
#
# 설명:
#   오프라인 서버에서 SSO 없이 대시보드를 사용하도록 설정합니다.
#
# 사용법:
#   sudo ./setup_sso_false_mode.sh
#
# 작성자: Claude Code
# 날짜: 2025-12-26
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          SSO False 모드 설정                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 1. my_multihead_cluster.yaml 파일 확인
log_info "Step 1: Checking my_multihead_cluster.yaml..."

YAML_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"

if [[ ! -f "$YAML_FILE" ]]; then
    log_warning "my_multihead_cluster.yaml not found, creating minimal config..."

    cat > "$YAML_FILE" << 'EOF'
# Minimal cluster configuration for SSO false mode
sso:
  enabled: false
  type: saml

dashboard:
  frontend:
    port: 3010
  backend:
    port: 5010
  auth_portal:
    port: 4431
EOF

    log_success "Created $YAML_FILE"
else
    # SSO 설정 확인
    if grep -q "enabled: false" "$YAML_FILE"; then
        log_success "SSO already disabled in $YAML_FILE"
    else
        log_warning "SSO might be enabled in $YAML_FILE"
        log_info "Please check: cat $YAML_FILE | grep -A 3 'sso:'"
    fi
fi

echo ""

# 2. 환경변수 방식 설정 (더 강건함)
log_info "Step 2: Setting up environment variables..."

# systemd 서비스 파일 찾기
BACKEND_SERVICE="/etc/systemd/system/backend_5010.service"

if [[ -f "$BACKEND_SERVICE" ]]; then
    log_info "Found systemd service: $BACKEND_SERVICE"

    # SSO_ENABLED 환경변수가 있는지 확인
    if grep -q "SSO_ENABLED" "$BACKEND_SERVICE"; then
        log_success "SSO_ENABLED already set in service file"
    else
        log_info "Adding SSO_ENABLED=false to service file..."

        # 백업
        sudo cp "$BACKEND_SERVICE" "${BACKEND_SERVICE}.backup_$(date +%Y%m%d_%H%M%S)"

        # Environment 섹션 추가
        if grep -q "\[Service\]" "$BACKEND_SERVICE"; then
            sudo sed -i '/\[Service\]/a Environment="SSO_ENABLED=false"' "$BACKEND_SERVICE"
            log_success "Added SSO_ENABLED=false to $BACKEND_SERVICE"

            # systemd reload
            sudo systemctl daemon-reload
            log_success "Reloaded systemd configuration"
        else
            log_error "Could not find [Service] section in $BACKEND_SERVICE"
        fi
    fi
else
    log_warning "systemd service file not found: $BACKEND_SERVICE"
    log_info "You can manually set environment variable: export SSO_ENABLED=false"
fi

echo ""

# 3. Backend 재시작
log_info "Step 3: Restarting backend service..."

if systemctl is-active --quiet backend_5010; then
    sudo systemctl restart backend_5010
    log_success "Backend service restarted"

    sleep 2

    # 상태 확인
    if systemctl is-active --quiet backend_5010; then
        log_success "Backend service is running"
    else
        log_error "Backend service failed to start"
        sudo systemctl status backend_5010
        exit 1
    fi
else
    log_warning "Backend service not running"
    log_info "Start it with: sudo systemctl start backend_5010"
fi

echo ""

# 4. API 테스트
log_info "Step 4: Testing API..."

sleep 1

if curl -s http://localhost:5010/api/auth/config > /dev/null 2>&1; then
    SSO_STATUS=$(curl -s http://localhost:5010/api/auth/config | grep -o '"sso_enabled":[^,}]*' || echo "unknown")

    if echo "$SSO_STATUS" | grep -q "false"; then
        log_success "✅ SSO is DISABLED (access without login)"
        echo "$SSO_STATUS"
    else
        log_warning "⚠ SSO might still be ENABLED"
        echo "$SSO_STATUS"
    fi
else
    log_error "Cannot connect to backend API on port 5010"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Setup Complete!                                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Access dashboard at: http://localhost:3010"
log_info "No login required - automatic admin access"
echo ""
log_info "Check logs:"
echo "  Backend:  journalctl -u backend_5010 -f"
echo "  Frontend: Check browser console (F12)"
echo ""
log_success "SSO False mode is ready!"
echo ""
