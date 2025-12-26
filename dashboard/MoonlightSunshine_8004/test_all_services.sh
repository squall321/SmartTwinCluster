#!/bin/bash

# ==============================================================================
# Moonlight/Sunshine 전체 시스템 테스트 스크립트
# ==============================================================================
# 목적: 기존 서비스 무결성 확인 + Moonlight 서비스 테스트
# 실행: ./test_all_services.sh
# ==============================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 동적 IP 감지
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_PATH="${SCRIPT_DIR}/../../my_multihead_cluster.yaml"
if [ -f "$YAML_PATH" ]; then
    EXTERNAL_IP=$(python3 -c "import yaml; config=yaml.safe_load(open('$YAML_PATH')); print(config.get('network', {}).get('vip', {}).get('address', '') or config.get('web', {}).get('public_url', 'localhost'))" 2>/dev/null)
fi
if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "localhost" ]; then
    EXTERNAL_IP=$(hostname -I | awk '{print $1}')
fi

# Test counter
PASS=0
FAIL=0

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    echo ""
    echo "=========================================================================="
    echo "$1"
    echo "=========================================================================="
}

test_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS++))
}

test_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAIL++))
}

test_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
}

# ==============================================================================
# Test 1: 기존 서비스 포트 확인
# ==============================================================================

print_header "Test 1: 기존 서비스 포트 확인"

ports=(4430 5000 5001 5010 5011 8001 8002 9090 9100)
port_names=("Auth Portal" "CAE Web" "CAE Automation" "Dashboard Backend" "WebSocket" "CAE Frontend" "VNC Frontend" "Prometheus" "Node Exporter")

for i in "${!ports[@]}"; do
    port="${ports[$i]}"
    name="${port_names[$i]}"

    if lsof -i ":$port" > /dev/null 2>&1; then
        test_pass "$name (Port $port) is running"
    else
        test_warn "$name (Port $port) is NOT running (may be normal)"
    fi
done

# ==============================================================================
# Test 2: Moonlight Backend 포트 확인
# ==============================================================================

print_header "Test 2: Moonlight Backend 포트 확인"

if lsof -i :8004 > /dev/null 2>&1; then
    test_pass "Moonlight Backend (Port 8004) is running"
else
    test_fail "Moonlight Backend (Port 8004) is NOT running"
fi

# ==============================================================================
# Test 3: 기존 API 엔드포인트 테스트
# ==============================================================================

print_header "Test 3: 기존 API 엔드포인트 테스트"

# Dashboard Backend Health
if curl -s -f -k https://${EXTERNAL_IP}/api/health > /dev/null; then
    test_pass "Dashboard Backend API (/api/health) is accessible"
else
    test_warn "Dashboard Backend API (/api/health) is NOT accessible"
fi

# VNC API
if curl -s -f -k https://${EXTERNAL_IP}/api/vnc/images > /dev/null; then
    test_pass "VNC API (/api/vnc/images) is accessible"
else
    test_warn "VNC API (/api/vnc/images) is NOT accessible"
fi

# CAE API
if curl -s -f -k https://${EXTERNAL_IP}/cae/api/standard-scenarios/health > /dev/null; then
    test_pass "CAE API (/cae/api/standard-scenarios/health) is accessible"
else
    test_warn "CAE API is NOT accessible"
fi

# ==============================================================================
# Test 4: Moonlight API 엔드포인트 테스트
# ==============================================================================

print_header "Test 4: Moonlight API 엔드포인트 테스트"

# Local API test
if curl -s -f http://localhost:8004/health > /dev/null; then
    test_pass "Moonlight Backend Health (localhost:8004/health) is accessible"

    # Get health response
    health_response=$(curl -s http://localhost:8004/health)
    if echo "$health_response" | grep -q "moonlight_backend"; then
        test_pass "Moonlight Backend Health response is correct"
    else
        test_fail "Moonlight Backend Health response is incorrect"
    fi
else
    test_fail "Moonlight Backend Health is NOT accessible"
fi

# Images endpoint
if curl -s -f http://localhost:8004/api/moonlight/images > /dev/null; then
    test_pass "Moonlight Images API (localhost:8004/api/moonlight/images) is accessible"

    # Check images response
    images_response=$(curl -s http://localhost:8004/api/moonlight/images)
    if echo "$images_response" | grep -q "xfce4"; then
        test_pass "Moonlight Images response contains 'xfce4'"
    else
        test_fail "Moonlight Images response is incorrect"
    fi
else
    test_fail "Moonlight Images API is NOT accessible"
fi

# ==============================================================================
# Test 5: Redis 연결 테스트
# ==============================================================================

print_header "Test 5: Redis 연결 테스트"

if redis-cli ping > /dev/null 2>&1; then
    test_pass "Redis is running and accessible"

    # Check VNC keys (should exist)
    vnc_keys=$(redis-cli KEYS "vnc:session:*" | wc -l)
    echo "   VNC session keys: $vnc_keys"

    # Check Moonlight keys (should be 0 initially)
    moonlight_keys=$(redis-cli KEYS "moonlight:session:*" | wc -l)
    echo "   Moonlight session keys: $moonlight_keys"

    if [ "$moonlight_keys" -eq 0 ]; then
        test_pass "No Moonlight sessions yet (expected for new service)"
    fi
else
    test_fail "Redis is NOT accessible"
fi

# ==============================================================================
# Test 6: Apptainer 이미지 확인
# ==============================================================================

print_header "Test 6: Apptainer 이미지 확인"

# Check VNC images (기존)
if [ -f "/opt/apptainers/vnc_desktop.sif" ]; then
    test_pass "VNC Desktop image exists"
else
    test_warn "VNC Desktop image NOT found"
fi

if [ -f "/opt/apptainers/vnc_gnome.sif" ]; then
    test_pass "VNC GNOME image exists"
else
    test_warn "VNC GNOME image NOT found"
fi

# Check Sunshine images (신규)
if [ -f "/opt/apptainers/sunshine_xfce4.sif" ]; then
    test_pass "Sunshine XFCE4 image exists"
else
    test_warn "Sunshine XFCE4 image NOT found (빌드 필요)"
fi

# ==============================================================================
# Test 7: Slurm QoS 확인
# ==============================================================================

print_header "Test 7: Slurm QoS 확인"

if sacctmgr show qos moonlight -n > /dev/null 2>&1; then
    test_pass "Moonlight QoS exists"

    # Show QoS details
    echo "   Moonlight QoS details:"
    sacctmgr show qos moonlight format=Name,Priority,MaxWall,MaxTRESPerUser,GraceTime -p
else
    test_warn "Moonlight QoS NOT found (생성 필요)"
fi

# ==============================================================================
# Test 8: Nginx 설정 확인
# ==============================================================================

print_header "Test 8: Nginx 설정 확인"

if sudo nginx -t > /dev/null 2>&1; then
    test_pass "Nginx configuration syntax is valid"
else
    test_fail "Nginx configuration has syntax errors"
fi

# Check if Moonlight locations exist
if sudo nginx -T 2>/dev/null | grep -q "location /api/moonlight/"; then
    test_pass "Nginx has /api/moonlight/ location"
else
    test_warn "Nginx does NOT have /api/moonlight/ location (설정 필요)"
fi

if sudo nginx -T 2>/dev/null | grep -q "location /moonlight/"; then
    test_pass "Nginx has /moonlight/ location"
else
    test_warn "Nginx does NOT have /moonlight/ location (설정 필요)"
fi

# ==============================================================================
# Test 9: 디렉토리 구조 확인
# ==============================================================================

print_header "Test 9: 디렉토리 구조 확인"

# Backend directories
backends=("auth_portal_4430" "backend_5010" "kooCAEWebServer_5000" "kooCAEWebAutomationServer_5001" "backend_moonlight_8004")
backend_names=("Auth Portal" "Dashboard Backend" "CAE Web Server" "CAE Automation" "Moonlight Backend")

for i in "${!backends[@]}"; do
    backend="${backends[$i]}"
    name="${backend_names[$i]}"
    path="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/$backend"

    if [ -d "$path" ]; then
        test_pass "$name directory exists"

        # Check venv
        if [ -d "$path/venv" ]; then
            echo "   ├─ venv: ✓"
        else
            echo "   ├─ venv: ✗"
        fi

        # Check requirements.txt
        if [ -f "$path/requirements.txt" ]; then
            echo "   ├─ requirements.txt: ✓"
        fi

        # Check app.py or gunicorn_config.py
        if [ -f "$path/app.py" ] || [ -f "$path/gunicorn_config.py" ]; then
            echo "   └─ app/config: ✓"
        fi
    else
        test_fail "$name directory does NOT exist"
    fi
done

# ==============================================================================
# Test 10: 프로세스 확인
# ==============================================================================

print_header "Test 10: 프로세스 확인"

# Check Gunicorn processes
gunicorn_count=$(ps aux | grep -c "[g]unicorn" || echo "0")
echo "   Gunicorn processes: $gunicorn_count"

if [ "$gunicorn_count" -gt 0 ]; then
    test_pass "Gunicorn processes are running"

    # Show gunicorn processes
    ps aux | grep "[g]unicorn" | awk '{print "   " $11, $12, $13, $14, $15}'
else
    test_warn "No Gunicorn processes found"
fi

# ==============================================================================
# 최종 결과
# ==============================================================================

print_header "테스트 결과 요약"

total=$((PASS + FAIL))
pass_rate=$(awk "BEGIN {printf \"%.1f\", ($PASS/$total)*100}")

echo ""
echo "   Total Tests: $total"
echo -e "   ${GREEN}Passed: $PASS${NC}"
echo -e "   ${RED}Failed: $FAIL${NC}"
echo "   Pass Rate: $pass_rate%"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}=========================================================================="
    echo "   ✅ 모든 테스트 통과!"
    echo "==========================================================================${NC}"
    exit 0
else
    echo -e "${YELLOW}=========================================================================="
    echo "   ⚠️  $FAIL 개의 테스트 실패"
    echo "   실패한 항목을 확인하고 수정하세요."
    echo "==========================================================================${NC}"
    exit 1
fi
