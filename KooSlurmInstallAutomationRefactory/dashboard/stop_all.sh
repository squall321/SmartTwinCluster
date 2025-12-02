#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "🛑 모든 서버 종료..."

# Stop auth services
echo "✅ Frontend 종료"
cd "${SCRIPT_DIR}/frontend_3010" && ./stop.sh && cd "${SCRIPT_DIR}"
cd "${SCRIPT_DIR}/websocket_5011" && ./stop.sh && cd "${SCRIPT_DIR}"
cd "${SCRIPT_DIR}/backend_5010" && ./stop.sh && cd "${SCRIPT_DIR}"
[ -f "prometheus_9090/stop.sh" ] && cd "${SCRIPT_DIR}/prometheus_9090" && ./stop.sh && cd "${SCRIPT_DIR}"
[ -f "node_exporter_9100/stop.sh" ] && cd "${SCRIPT_DIR}/node_exporter_9100" && ./stop.sh && cd "${SCRIPT_DIR}"

# Stop auth services (port 4430, 4431)
echo "✅ WebSocket 종료"
pkill -f "auth_portal_4430.*python" 2>/dev/null
pkill -f "auth_portal_4431.*vite" 2>/dev/null
pkill -f "auth_portal_4431.*node" 2>/dev/null

echo "✅ 모든 서버 종료 완료!"
