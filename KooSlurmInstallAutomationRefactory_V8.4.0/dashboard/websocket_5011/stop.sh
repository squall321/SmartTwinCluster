#!/bin/bash
[ -f ".websocket.pid" ] && kill $(cat .websocket.pid) 2>/dev/null && rm -f .websocket.pid && echo "✅ WebSocket 종료"
