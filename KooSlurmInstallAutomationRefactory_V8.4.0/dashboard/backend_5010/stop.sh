#!/bin/bash
[ -f ".backend.pid" ] && kill $(cat .backend.pid) 2>/dev/null && rm -f .backend.pid && echo "✅ Backend 종료"
