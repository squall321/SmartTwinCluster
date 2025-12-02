#!/bin/bash
# Job Template 강제 삭제 스크립트

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}         Job Template 강제 삭제 도구                        ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# DB 경로 확인
DB_SQLITE="/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010/database/dashboard.db"
DB_TYPE="unknown"

if [ -f "$DB_SQLITE" ]; then
    DB_TYPE="sqlite"
    echo -e "${GREEN}✓${NC} SQLite DB 발견: $DB_SQLITE"
else
    echo -e "${RED}✗${NC} 데이터베이스를 찾을 수 없습니다: $DB_SQLITE"
    exit 1
fi

echo ""

# 옵션 선택
echo "삭제 옵션:"
echo "  1) 모든 템플릿 목록 보기"
echo "  2) 특정 템플릿 삭제 (ID로)"
echo "  3) 모든 템플릿 삭제 (위험!)"
echo "  4) 특정 사용자의 템플릿 삭제"
echo ""
read -p "선택 (1-4): " choice

case $choice in
    1)
        echo ""
        echo -e "${YELLOW}현재 저장된 템플릿:${NC}"
        echo ""

        sqlite3 "$DB_SQLITE" << 'EOSQL'
.headers on
.mode column
SELECT id, name, created_by, shared, created_at
FROM templates
ORDER BY created_at DESC;
EOSQL
        ;;

    2)
        read -p "삭제할 템플릿 ID: " template_id

        if [ -z "$template_id" ]; then
            echo -e "${RED}✗${NC} 템플릿 ID를 입력해주세요"
            exit 1
        fi

        echo ""
        read -p "정말로 템플릿 '$template_id'를 삭제하시겠습니까? (yes/no): " confirm

        if [ "$confirm" != "yes" ]; then
            echo "취소되었습니다"
            exit 0
        fi

        sqlite3 "$DB_SQLITE" "DELETE FROM templates WHERE id = '$template_id';"
        affected=$(sqlite3 "$DB_SQLITE" "SELECT changes();")

        if [ "$affected" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} 템플릿이 삭제되었습니다"
        else
            echo -e "${YELLOW}⚠${NC} 템플릿을 찾을 수 없습니다"
        fi
        ;;

    3)
        echo ""
        echo -e "${RED}⚠ 경고: 모든 템플릿이 삭제됩니다!${NC}"
        read -p "정말로 모든 템플릿을 삭제하시겠습니까? (DELETE-ALL 입력): " confirm

        if [ "$confirm" != "DELETE-ALL" ]; then
            echo "취소되었습니다"
            exit 0
        fi

        count=$(sqlite3 "$DB_SQLITE" "SELECT COUNT(*) FROM templates;")
        sqlite3 "$DB_SQLITE" "DELETE FROM templates;"

        echo -e "${GREEN}✓${NC} $count개의 템플릿이 삭제되었습니다"
        ;;

    4)
        read -p "삭제할 사용자 이름 (created_by): " username

        if [ -z "$username" ]; then
            echo -e "${RED}✗${NC} 사용자 이름을 입력해주세요"
            exit 1
        fi

        echo ""
        echo -e "${YELLOW}해당 사용자의 템플릿:${NC}"

        sqlite3 "$DB_SQLITE" << EOSQL
.headers on
.mode column
SELECT id, name, created_at FROM templates WHERE created_by = '$username';
EOSQL

        count=$(sqlite3 "$DB_SQLITE" "SELECT COUNT(*) FROM templates WHERE created_by = '$username';")

        echo ""
        echo "총 $count개의 템플릿"
        read -p "모두 삭제하시겠습니까? (yes/no): " confirm

        if [ "$confirm" != "yes" ]; then
            echo "취소되었습니다"
            exit 0
        fi

        sqlite3 "$DB_SQLITE" "DELETE FROM templates WHERE created_by = '$username';"

        echo -e "${GREEN}✓${NC} $count개의 템플릿이 삭제되었습니다"
        ;;

    *)
        echo -e "${RED}✗${NC} 잘못된 선택입니다"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}완료!${NC}"
