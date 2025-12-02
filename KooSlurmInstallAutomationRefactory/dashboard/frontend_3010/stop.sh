#!/bin/bash
[ -f ".frontend.pid" ] && kill $(cat .frontend.pid) 2>/dev/null && rm -f .frontend.pid
pgrep -f "vite" | xargs kill -9 2>/dev/null || true
echo "✅ Frontend 종료"
