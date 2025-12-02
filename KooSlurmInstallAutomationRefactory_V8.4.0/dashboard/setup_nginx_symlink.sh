#!/bin/bash
################################################################################
# Nginx 설정 심볼릭 링크 설정 스크립트
# dashboard/nginx/hpc-portal.conf를 /etc/nginx/sites-* 에 연결
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🔧 Nginx 설정 심볼릭 링크 설정"
echo "=========================================="
echo ""

# 설정 파일 경로
CONFIG_SOURCE="$SCRIPT_DIR/nginx/hpc-portal.conf"
SITES_AVAILABLE="/etc/nginx/sites-available/hpc-portal.conf"
SITES_ENABLED="/etc/nginx/sites-enabled/hpc-portal.conf"

# 1. 소스 파일 확인
echo -e "${BLUE}[1/5] 설정 파일 확인...${NC}"
if [ ! -f "$CONFIG_SOURCE" ]; then
    echo -e "${RED}❌ 설정 파일이 없습니다: $CONFIG_SOURCE${NC}"
    exit 1
fi
echo -e "${GREEN}✅ 설정 파일 존재: $(basename $CONFIG_SOURCE)${NC}"
echo ""

# 2. 기존 sites-available 처리
echo -e "${BLUE}[2/5] sites-available 심볼릭 링크 생성...${NC}"
if [ -L "$SITES_AVAILABLE" ]; then
    # 이미 심볼릭 링크인 경우
    CURRENT_TARGET=$(readlink -f "$SITES_AVAILABLE")
    if [ "$CURRENT_TARGET" = "$CONFIG_SOURCE" ]; then
        echo -e "${GREEN}✅ 이미 올바른 심볼릭 링크가 존재합니다${NC}"
    else
        echo -e "${YELLOW}⚠  다른 파일을 가리키는 심볼릭 링크 존재: $CURRENT_TARGET${NC}"
        echo "  → 기존 링크 제거 후 재생성..."
        sudo rm "$SITES_AVAILABLE"
        sudo ln -s "$CONFIG_SOURCE" "$SITES_AVAILABLE"
        echo -e "${GREEN}✅ 심볼릭 링크 재생성 완료${NC}"
    fi
elif [ -f "$SITES_AVAILABLE" ]; then
    # 일반 파일인 경우 백업 후 심볼릭 링크 생성
    BACKUP="$SITES_AVAILABLE.backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}⚠  일반 파일 존재. 백업 후 심볼릭 링크로 변경...${NC}"
    sudo mv "$SITES_AVAILABLE" "$BACKUP"
    echo "  → 백업: $(basename $BACKUP)"
    sudo ln -s "$CONFIG_SOURCE" "$SITES_AVAILABLE"
    echo -e "${GREEN}✅ 심볼릭 링크 생성 완료${NC}"
else
    # 파일이 없는 경우 새로 생성
    echo "  → 새 심볼릭 링크 생성..."
    sudo ln -s "$CONFIG_SOURCE" "$SITES_AVAILABLE"
    echo -e "${GREEN}✅ 심볼릭 링크 생성 완료${NC}"
fi
echo ""

# 3. 기존 sites-enabled 처리
echo -e "${BLUE}[3/5] sites-enabled 심볼릭 링크 생성...${NC}"
if [ -L "$SITES_ENABLED" ]; then
    # 이미 심볼릭 링크인 경우
    CURRENT_TARGET=$(readlink -f "$SITES_ENABLED")
    if [ "$CURRENT_TARGET" = "$SITES_AVAILABLE" ] || [ "$CURRENT_TARGET" = "$CONFIG_SOURCE" ]; then
        echo -e "${GREEN}✅ 이미 올바른 심볼릭 링크가 존재합니다${NC}"
    else
        echo -e "${YELLOW}⚠  다른 파일을 가리키는 심볼릭 링크 존재: $CURRENT_TARGET${NC}"
        echo "  → 기존 링크 제거 후 재생성..."
        sudo rm "$SITES_ENABLED"
        sudo ln -s "$SITES_AVAILABLE" "$SITES_ENABLED"
        echo -e "${GREEN}✅ 심볼릭 링크 재생성 완료${NC}"
    fi
elif [ -f "$SITES_ENABLED" ]; then
    # 일반 파일인 경우 백업 후 심볼릭 링크 생성
    BACKUP="$SITES_ENABLED.backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}⚠  일반 파일 존재. 백업 후 심볼릭 링크로 변경...${NC}"
    sudo mv "$SITES_ENABLED" "$BACKUP"
    echo "  → 백업: $(basename $BACKUP)"
    sudo ln -s "$SITES_AVAILABLE" "$SITES_ENABLED"
    echo -e "${GREEN}✅ 심볼릭 링크 생성 완료${NC}"
else
    # 파일이 없는 경우 새로 생성
    echo "  → 새 심볼릭 링크 생성..."
    sudo ln -s "$SITES_AVAILABLE" "$SITES_ENABLED"
    echo -e "${GREEN}✅ 심볼릭 링크 생성 완료${NC}"
fi
echo ""

# 4. 심볼릭 링크 체인 확인
echo -e "${BLUE}[4/5] 심볼릭 링크 체인 확인...${NC}"
echo "  소스 파일:       $CONFIG_SOURCE"
echo "  sites-available: $SITES_AVAILABLE → $(readlink $SITES_AVAILABLE)"
echo "  sites-enabled:   $SITES_ENABLED → $(readlink $SITES_ENABLED)"
echo ""

# 5. Nginx 설정 테스트
echo -e "${BLUE}[5/5] Nginx 설정 테스트...${NC}"
if sudo nginx -t 2>&1 | grep -q "syntax is ok"; then
    echo -e "${GREEN}✅ Nginx 설정 문법 검사 통과${NC}"
else
    echo -e "${RED}❌ Nginx 설정 오류${NC}"
    sudo nginx -t
    exit 1
fi
echo ""

# 완료 메시지
echo "=========================================="
echo -e "${GREEN}✅ Nginx 심볼릭 링크 설정 완료!${NC}"
echo "=========================================="
echo ""
echo "📝 설정 체인:"
echo "   소스: dashboard/nginx/hpc-portal.conf"
echo "   ↓"
echo "   /etc/nginx/sites-available/hpc-portal.conf (symlink)"
echo "   ↓"
echo "   /etc/nginx/sites-enabled/hpc-portal.conf (symlink)"
echo ""
echo "💡 팁:"
echo "   - 설정 수정: dashboard/nginx/hpc-portal.conf 편집"
echo "   - 적용: sudo systemctl reload nginx"
echo "   - 테스트: sudo nginx -t"
echo ""
echo "🔄 Nginx 재시작 여부 (y/N)?"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    sudo systemctl reload nginx
    echo -e "${GREEN}✅ Nginx 재시작 완료${NC}"
else
    echo -e "${YELLOW}⚠  나중에 수동으로 재시작하세요: sudo systemctl reload nginx${NC}"
fi
