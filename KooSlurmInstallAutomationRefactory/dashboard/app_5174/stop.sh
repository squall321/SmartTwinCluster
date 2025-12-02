#!/bin/bash
################################################################################
# App Service (5174) 종료 스크립트
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🛑 Stopping App Service (5174)..."

# Kill by PID if exists
if [ -f "logs/dev.pid" ]; then
    PID=$(cat logs/dev.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo -e "${GREEN}✅ Stopped process (PID: $PID)${NC}"
    fi
    rm -f logs/dev.pid
fi

# Kill by process name
pkill -f "app_5174.*npm.*dev" 2>/dev/null && echo -e "${GREEN}✅ Stopped npm dev process${NC}"

# Kill by port
fuser -k 5174/tcp 2>/dev/null && echo -e "${GREEN}✅ Freed port 5174${NC}"

echo -e "${GREEN}✅ App Service stopped${NC}"
