#!/bin/bash
################################################################################
# Job Template 배포 스크립트
#
# dashboard/templates/의 템플릿을 /shared/templates/로 배포합니다.
# 헤드노드에서 실행하면 GlusterFS를 통해 모든 노드에서 사용 가능합니다.
#
# 사용법:
#   sudo ./deploy_templates.sh
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "============================================"
echo "  Job Template 배포 스크립트"
echo "  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# Root 권한 확인
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

# 실제 사용자 확인
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")

log_info "Running as: $RUN_USER:$RUN_GROUP"
echo ""

# /shared 디렉토리 확인
if [[ ! -d "/shared" ]] && [[ ! -L "/shared" ]]; then
    log_error "/shared directory not found!"
    echo "  /shared must be mounted (GlusterFS or local) before deploying templates"
    echo "  Check: ls -la /shared"
    echo "  Check: mount | grep shared"
    exit 1
fi

log_success "/shared directory found"
echo ""

# 템플릿 디렉토리 생성
TEMPLATE_DIR="/shared/templates"

log_info "Creating template directory structure..."
mkdir -p "$TEMPLATE_DIR"/{official,community,private,archived}
mkdir -p "$TEMPLATE_DIR"/official/{ml,cfd,structural,molecular,data,rendering,simulation,custom}

log_success "Directory structure created"
echo ""

# 권한 설정
log_info "Setting permissions..."
chown -R "$RUN_USER:$RUN_GROUP" "$TEMPLATE_DIR"
chmod 755 "$TEMPLATE_DIR"

# Official: read-only for users, writable by admin
chmod 755 "$TEMPLATE_DIR"/official
find "$TEMPLATE_DIR"/official -type d -exec chmod 755 {} \;
find "$TEMPLATE_DIR"/official -type f -exec chmod 644 {} \; 2>/dev/null || true

# Community: writable by all authenticated users
chmod 777 "$TEMPLATE_DIR"/community

# Private: user-specific
chmod 777 "$TEMPLATE_DIR"/private

# Archived: read-only
chmod 755 "$TEMPLATE_DIR"/archived

log_success "Permissions set"
echo ""

# 프로젝트 템플릿 복사
SOURCE_TEMPLATES="$PROJECT_ROOT/dashboard/templates"

if [[ -d "$SOURCE_TEMPLATES" ]]; then
    log_info "Found project templates at: $SOURCE_TEMPLATES"
    echo ""

    # Official templates 복사
    if [[ -d "$SOURCE_TEMPLATES/official" ]]; then
        log_info "Copying official templates..."

        # 기존 템플릿 백업
        if [[ -d "$TEMPLATE_DIR/official" ]] && [[ "$(ls -A $TEMPLATE_DIR/official 2>/dev/null)" ]]; then
            BACKUP_DIR="$TEMPLATE_DIR/official.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "Backing up existing templates to: $BACKUP_DIR"
            cp -a "$TEMPLATE_DIR/official" "$BACKUP_DIR"
        fi

        # 새 템플릿 복사
        cp -rv "$SOURCE_TEMPLATES/official/"* "$TEMPLATE_DIR/official/" 2>/dev/null || true

        # 복사된 템플릿 수 확인
        local count=$(find "$TEMPLATE_DIR/official" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
        log_success "Copied $count official templates"

        # 템플릿 목록 출력
        echo ""
        log_info "Deployed templates:"
        find "$TEMPLATE_DIR/official" -name "*.yaml" -o -name "*.yml" 2>/dev/null | while read -r template; do
            local rel_path="${template#$TEMPLATE_DIR/official/}"
            echo "  ✓ $rel_path"
        done
    else
        log_warning "No official templates found in: $SOURCE_TEMPLATES/official"
    fi

    echo ""

    # Community templates 복사 (있으면)
    if [[ -d "$SOURCE_TEMPLATES/community" ]]; then
        log_info "Copying community templates..."
        cp -rv "$SOURCE_TEMPLATES/community/"* "$TEMPLATE_DIR/community/" 2>/dev/null || true
        local count=$(find "$TEMPLATE_DIR/community" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
        log_success "Copied $count community templates"
    fi
else
    log_error "Project templates directory not found: $SOURCE_TEMPLATES"
    echo "  Expected location: dashboard/templates/official/"
    exit 1
fi

echo ""
echo "============================================"
echo "  배포 완료!"
echo "============================================"
echo ""
log_success "Templates deployed to: $TEMPLATE_DIR"

# 최종 통계
OFFICIAL_COUNT=$(find "$TEMPLATE_DIR/official" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
COMMUNITY_COUNT=$(find "$TEMPLATE_DIR/community" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)

echo ""
echo "Summary:"
echo "  Official templates:  $OFFICIAL_COUNT"
echo "  Community templates: $COMMUNITY_COUNT"
echo ""
echo "Next steps:"
echo "  1. Restart backend service: sudo systemctl restart dashboard_backend"
echo "  2. Trigger template scan: curl -X POST http://localhost:5010/api/jobs/templates/scan"
echo "  3. Verify templates: curl http://localhost:5010/api/jobs/templates"
echo ""
