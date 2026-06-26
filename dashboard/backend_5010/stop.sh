#!/bin/bash
# 대시보드 백엔드(5010) 중지 스크립트
[ -f ".backend.pid" ] && kill $(cat .backend.pid) 2>/dev/null && rm -f .backend.pid && echo "✅ Backend 종료"
