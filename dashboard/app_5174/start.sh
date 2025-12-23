#!/bin/bash
################################################################################
# App Service (5174) 시작 스크립트
# Production: Nginx를 통해 static files 제공
# Development: npm run dev로 직접 실행
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load public URL from YAML
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
YAML_FILE="$PROJECT_ROOT/my_multihead_cluster.yaml"
if [[ -f "$YAML_FILE" ]]; then
    PUBLIC_URL=$(python3 -c "import yaml; c=yaml.safe_load(open('$YAML_FILE')); print(c.get('web', {}).get('public_url', 'localhost'))" 2>/dev/null || echo "localhost")
    SSO_ENABLED=$(python3 -c "import yaml; c=yaml.safe_load(open('$YAML_FILE')); print(str(c.get('sso', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")
    PROTOCOL=$([[ "$SSO_ENABLED" == "true" ]] && echo "https" || echo "http")
else
    PUBLIC_URL="localhost"
    PROTOCOL="http"
fi

MODE="${1:-production}"  # production or development

if [ "$MODE" = "development" ]; then
    echo -e "${YELLOW}🚀 Starting App Service in DEVELOPMENT mode${NC}"
    echo "  → Running on: http://localhost:5174"

    # Kill existing process
    pkill -f "app_5174.*npm.*dev" 2>/dev/null
    fuser -k 5174/tcp 2>/dev/null
    sleep 1

    # Start dev server
    mkdir -p logs
    nohup npm run dev > logs/dev.log 2>&1 &
    APP_PID=$!
    echo $APP_PID > logs/dev.pid

    echo -e "${GREEN}✅ App Service started (PID: $APP_PID)${NC}"
    echo "  → Logs: logs/dev.log"

elif [ "$MODE" = "production" ]; then
    echo -e "${GREEN}🚀 App Service in PRODUCTION mode${NC}"
    echo "  → Served by Nginx at: ${PROTOCOL}://${PUBLIC_URL}/app/"
    echo "  → Static files from: dist/"

    # Check if dist/ exists
    if [ ! -d "dist" ]; then
        echo -e "${RED}❌ dist/ directory not found${NC}"
        echo "  → Run: npm run build"
        exit 1
    fi

    echo -e "${GREEN}✅ App Service ready (Production - Nginx)${NC}"
else
    echo -e "${RED}❌ Invalid mode: $MODE${NC}"
    echo "Usage: $0 [production|development]"
    exit 1
fi
