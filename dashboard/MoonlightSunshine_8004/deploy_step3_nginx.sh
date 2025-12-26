#!/bin/bash
# ========================================================================
# Moonlight/Sunshine Nginx 설정 적용 스크립트 (Step 3)
# ========================================================================
# 목적: Nginx에 Moonlight 라우팅 추가
# 위치: Controller에서 실행
# 권한: sudo 필요
# 소요시간: 10분
# ========================================================================

set -e  # 에러 발생 시 즉시 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# ========================================================================
# 1. 환경 확인
# ========================================================================

log_info "Step 3: Nginx 설정 적용 시작"
log_info ""

# Nginx 설치 확인
log_info "Nginx 설치 확인 중..."
if ! command -v nginx &> /dev/null; then
    log_error "nginx를 찾을 수 없습니다"
    log_error "Nginx가 설치되어 있지 않습니다"
    exit 1
fi

NGINX_VERSION=$(nginx -v 2>&1 | cut -d'/' -f2)
log_info "✅ Nginx 버전: $NGINX_VERSION"

# sudo 권한 확인
log_info "sudo 권한 확인 중..."
if ! sudo -n nginx -t &>/dev/null; then
    log_warn "sudo 권한이 필요합니다"
    sudo -v
fi
log_info "✅ sudo 권한 확인 완료"

# Nginx 설정 파일 위치
NGINX_CONF="/etc/nginx/conf.d/auth-portal.conf"

if [ ! -f "$NGINX_CONF" ]; then
    log_error "Nginx 설정 파일을 찾을 수 없습니다: $NGINX_CONF"
    log_error "다른 설정 파일 경로를 확인해주세요"
    exit 1
fi

log_info "✅ Nginx 설정 파일: $NGINX_CONF"

# ========================================================================
# 2. 현재 Nginx 설정 백업
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Nginx 설정 백업"
log_info "=========================================="

BACKUP_FILE="${NGINX_CONF}.backup_$(date +%Y%m%d_%H%M%S)"

log_info "백업 파일: $BACKUP_FILE"
sudo cp "$NGINX_CONF" "$BACKUP_FILE"
log_info "✅ 백업 완료"

# 백업 파일 목록
log_info ""
log_info "백업 파일 목록:"
ls -lh "${NGINX_CONF}.backup_"* 2>/dev/null | tail -5

# ========================================================================
# 3. Moonlight 설정 파일 확인
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Moonlight Nginx 설정 파일 확인"
log_info "=========================================="

SOURCE_DIR="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004"
MOONLIGHT_CONF="$SOURCE_DIR/nginx_config_addition.conf"

if [ ! -f "$MOONLIGHT_CONF" ]; then
    log_error "Moonlight Nginx 설정 파일을 찾을 수 없습니다: $MOONLIGHT_CONF"
    exit 1
fi

log_info "✅ Moonlight 설정 파일: $MOONLIGHT_CONF"
log_info ""
log_info "설정 파일 내용 미리보기:"
log_info "=========================================="
head -50 "$MOONLIGHT_CONF"
log_info "=========================================="

# ========================================================================
# 4. 기존 설정에 Moonlight 설정 존재 여부 확인
# ========================================================================

log_info ""
log_info "기존 Nginx 설정에서 Moonlight 설정 검색 중..."

if sudo grep -q "moonlight_backend" "$NGINX_CONF"; then
    log_warn ""
    log_warn "⚠️  기존 Nginx 설정에 'moonlight_backend'가 이미 존재합니다"
    log_warn ""
    read -p "기존 Moonlight 설정을 덮어쓰시겠습니까? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "설정 추가를 건너뜁니다"
        log_info "수동으로 설정을 확인해주세요: $NGINX_CONF"
        exit 0
    fi

    log_warn "기존 Moonlight 설정을 제거하고 다시 추가합니다"
fi

# ========================================================================
# 5. Nginx 설정 파일 분석
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Nginx 설정 파일 구조 분석"
log_info "=========================================="

# upstream 블록 위치 찾기
UPSTREAM_LINE=$(sudo grep -n "^upstream" "$NGINX_CONF" | head -1 | cut -d':' -f1)
if [ -z "$UPSTREAM_LINE" ]; then
    UPSTREAM_LINE=1
    log_warn "upstream 블록을 찾을 수 없습니다. 파일 최상단에 추가합니다"
else
    log_info "✅ 첫 번째 upstream 블록 위치: Line $UPSTREAM_LINE"
fi

# server 블록 찾기
SERVER_LINE=$(sudo grep -n "^server {" "$NGINX_CONF" | head -1 | cut -d':' -f1)
if [ -z "$SERVER_LINE" ]; then
    log_error "server 블록을 찾을 수 없습니다"
    exit 1
fi
log_info "✅ server 블록 위치: Line $SERVER_LINE"

# /api/ location 찾기
API_LOCATION_LINE=$(sudo grep -n "location /api/" "$NGINX_CONF" | head -1 | cut -d':' -f1)
if [ -z "$API_LOCATION_LINE" ]; then
    log_warn "/api/ location을 찾을 수 없습니다"
    API_LOCATION_LINE=$SERVER_LINE
else
    log_info "✅ /api/ location 위치: Line $API_LOCATION_LINE"
fi

# ========================================================================
# 6. Nginx 설정 자동 추가
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Nginx 설정 자동 추가 시작"
log_info "=========================================="

# 임시 파일 생성
TEMP_CONF="/tmp/nginx_moonlight_temp_$$.conf"
sudo cp "$NGINX_CONF" "$TEMP_CONF"

# 기존 moonlight 설정 제거 (있다면)
if sudo grep -q "moonlight_backend" "$TEMP_CONF"; then
    log_info "기존 Moonlight 설정 제거 중..."

    # upstream moonlight_backend 블록 제거
    sudo sed -i '/^upstream moonlight_backend/,/^}/d' "$TEMP_CONF"

    # upstream moonlight_signaling 블록 제거
    sudo sed -i '/^upstream moonlight_signaling/,/^}/d' "$TEMP_CONF"

    # location /api/moonlight/ 블록 제거
    sudo sed -i '/location \/api\/moonlight\//,/^    }/d' "$TEMP_CONF"

    # location /moonlight/signaling 블록 제거
    sudo sed -i '/location \/moonlight\/signaling/,/^    }/d' "$TEMP_CONF"

    # location /moonlight/ 블록 제거
    sudo sed -i '/location \/moonlight\//,/^    }/d' "$TEMP_CONF"

    log_info "✅ 기존 설정 제거 완료"
fi

# ========================================================================
# 7. Upstream 정의 추가
# ========================================================================

log_info ""
log_info "1. Upstream 정의 추가 중..."

# Upstream 블록 내용
UPSTREAM_BLOCK='
# ========================================================================
# Moonlight/Sunshine Upstream Definitions
# ========================================================================

upstream moonlight_backend {
    server 127.0.0.1:8004;
}

upstream moonlight_signaling {
    server 127.0.0.1:8005;
}
'

# server 블록 바로 위에 추가
sudo sed -i "${SERVER_LINE}i\\$UPSTREAM_BLOCK" "$TEMP_CONF"

log_info "✅ Upstream 정의 추가 완료"

# ========================================================================
# 8. API Location 추가
# ========================================================================

log_info ""
log_info "2. /api/moonlight/ location 추가 중..."

# API location 블록 내용
API_LOCATION_BLOCK='
    # Moonlight/Sunshine Backend API (Port 8004)
    # ⚠️ 주의: /api/ 위에 정의되어야 우선순위 확보
    location /api/moonlight/ {
        proxy_pass http://moonlight_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # CORS headers
        add_header '\''Access-Control-Allow-Origin'\'' '\''*'\'' always;
        add_header '\''Access-Control-Allow-Methods'\'' '\''GET, POST, PUT, DELETE, OPTIONS'\'' always;
        add_header '\''Access-Control-Allow-Headers'\'' '\''Authorization, Content-Type, X-Username'\'' always;

        if ($request_method = '\''OPTIONS'\'') {
            return 204;
        }
    }
'

# /api/ location 바로 위에 추가
NEW_API_LOCATION_LINE=$(sudo grep -n "location /api/" "$TEMP_CONF" | head -1 | cut -d':' -f1)
if [ -n "$NEW_API_LOCATION_LINE" ]; then
    sudo sed -i "${NEW_API_LOCATION_LINE}i\\$API_LOCATION_BLOCK" "$TEMP_CONF"
    log_info "✅ /api/moonlight/ location 추가 완료 (Line $NEW_API_LOCATION_LINE 위)"
else
    log_warn "⚠️  /api/ location을 찾을 수 없습니다. server 블록 안에 추가합니다"
    NEW_SERVER_LINE=$(sudo grep -n "^server {" "$TEMP_CONF" | head -1 | cut -d':' -f1)
    AFTER_SERVER_LINE=$((NEW_SERVER_LINE + 1))
    sudo sed -i "${AFTER_SERVER_LINE}i\\$API_LOCATION_BLOCK" "$TEMP_CONF"
fi

# ========================================================================
# 9. 설정 파일 적용
# ========================================================================

log_info ""
log_info "=========================================="
log_info "설정 파일 적용"
log_info "=========================================="

# 임시 파일을 실제 설정 파일로 복사
sudo cp "$TEMP_CONF" "$NGINX_CONF"
log_info "✅ 설정 파일 업데이트 완료"

# 임시 파일 삭제
rm -f "$TEMP_CONF"

# ========================================================================
# 10. Nginx 설정 문법 검사
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Nginx 설정 문법 검사"
log_info "=========================================="

if sudo nginx -t; then
    log_info ""
    log_info "✅ Nginx 설정 문법 검사 통과"
else
    log_error ""
    log_error "❌ Nginx 설정 문법 오류 발생"
    log_error ""
    log_error "백업 파일로 복원 중..."
    sudo cp "$BACKUP_FILE" "$NGINX_CONF"
    log_error "✅ 백업 파일 복원 완료: $BACKUP_FILE"
    log_error ""
    log_error "수동으로 설정을 확인해주세요"
    exit 1
fi

# ========================================================================
# 11. Nginx 재시작
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Nginx 재시작"
log_info "=========================================="

read -p "Nginx를 재시작하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Nginx 재시작 중..."

    if sudo systemctl reload nginx; then
        log_info "✅ Nginx 재시작 성공"
    else
        log_error "❌ Nginx 재시작 실패"
        log_error "수동으로 재시작해주세요: sudo systemctl reload nginx"
        exit 1
    fi
else
    log_warn "Nginx 재시작을 건너뜁니다"
    log_warn "수동으로 재시작해주세요: sudo systemctl reload nginx"
fi

# ========================================================================
# 12. 설정 테스트
# ========================================================================

log_info ""
log_info "=========================================="
log_info "Moonlight API 테스트"
log_info "=========================================="

# Backend가 실행 중인지 확인
if ! lsof -i :8004 &>/dev/null; then
    log_warn "⚠️  Moonlight Backend가 실행되지 않았습니다 (Port 8004)"
    log_warn "Backend를 먼저 시작해주세요"
else
    log_info "✅ Moonlight Backend 실행 중 (Port 8004)"

    # 로컬 테스트
    log_info ""
    log_info "로컬 테스트 (http://localhost:8004/health):"
    curl -s http://localhost:8004/health | jq . || curl -s http://localhost:8004/health

    # Nginx를 통한 테스트
    log_info ""
    log_info "Nginx를 통한 테스트 (https://localhost/api/moonlight/images):"
    curl -s -k https://localhost/api/moonlight/images | jq . || curl -s -k https://localhost/api/moonlight/images
fi

# ========================================================================
# 13. 완료
# ========================================================================

log_info ""
log_info "=========================================="
log_info "🎉 Step 3: Nginx 설정 적용 완료!"
log_info "=========================================="
log_info ""
log_info "설정 파일: $NGINX_CONF"
log_info "백업 파일: $BACKUP_FILE"
log_info ""
log_info "추가된 라우팅:"
log_info "  - /api/moonlight/ → http://127.0.0.1:8004"
log_info "  - /moonlight/signaling → http://127.0.0.1:8005 (향후)"
log_info ""
log_info "테스트 명령어:"
log_info "  curl -k https://${EXTERNAL_IP}/api/moonlight/images"
log_info ""
log_info "다음 단계:"
log_info "  - Frontend 개발 시작"
log_info "  - WebRTC Signaling Server 구현 (Port 8005)"
log_info ""

# ========================================================================
# 참고 명령어
# ========================================================================

log_info "=========================================="
log_info "참고 명령어"
log_info "=========================================="
echo ""
echo "# Nginx 설정 문법 검사"
echo "sudo nginx -t"
echo ""
echo "# Nginx 재시작"
echo "sudo systemctl reload nginx"
echo ""
echo "# Nginx 상태 확인"
echo "sudo systemctl status nginx"
echo ""
echo "# Nginx 에러 로그"
echo "sudo tail -f /var/log/nginx/auth-portal-error.log"
echo ""
echo "# 백업 파일로 복원"
echo "sudo cp $BACKUP_FILE $NGINX_CONF"
echo "sudo nginx -t && sudo systemctl reload nginx"
echo ""
