#!/bin/bash
# WebSocket 서비스(5011) 중지 스크립트
[ -f ".websocket.pid" ] && kill $(cat .websocket.pid) 2>/dev/null && rm -f .websocket.pid && echo "✅ WebSocket 종료"
