#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PORT=8002

echo -e "${YELLOW}Starting VNC Service on port ${PORT}...${NC}"

# Check if port is in use
PID=$(lsof -ti:$PORT 2>/dev/null)
if [ ! -z "$PID" ]; then
    echo -e "${YELLOW}⚠️  Port ${PORT} in use (PID: $PID), killing...${NC}"
    kill -9 $PID 2>/dev/null
    sleep 1
fi

# Start Vite dev server
nohup npm run dev > /tmp/vnc_service_8002.log 2>&1 &
echo $! > .vnc_service.pid
sleep 3

# Check if started successfully
if ps -p $(cat .vnc_service.pid) > /dev/null 2>&1; then
    echo -e "${GREEN}✅ VNC Service started (PID: $(cat .vnc_service.pid))${NC}"
    echo -e "${GREEN}🔗 http://localhost:${PORT}${NC}"
else
    echo -e "${RED}❌ Failed to start VNC Service${NC}"
    tail -20 /tmp/vnc_service_8002.log
fi
