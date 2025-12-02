#!/bin/bash
# 모든 서비스 상태 확인 스크립트

echo "=========================================="
echo "서비스 상태 확인"
echo "=========================================="
echo ""

# Backend
echo "1. Backend API (5010):"
if curl -s http://localhost:5010/api/health > /dev/null 2>&1; then
    echo "   ✅ 실행 중"
else
    echo "   ❌ 실행 안됨"
fi

# Frontend
echo "2. Frontend (3010):"
if curl -s http://localhost:3010 > /dev/null 2>&1; then
    echo "   ✅ 실행 중"
else
    echo "   ❌ 실행 안됨"
fi

# WebSocket
echo "3. WebSocket (5011):"
if curl -s http://localhost:5011/health > /dev/null 2>&1; then
    echo "   ✅ 실행 중"
else
    echo "   ❌ 실행 안됨 - Health Check API가 없을 수 있음"
    if netstat -tlnp 2>/dev/null | grep -q ":5011"; then
        echo "   ℹ️  포트는 열려있음"
    else
        echo "   ❌ 포트도 열려있지 않음"
    fi
fi

# Prometheus
echo "4. Prometheus (9090):"
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo "   ✅ 실행 중"
else
    echo "   ❌ 실행 안됨"
fi

# Node Exporter
echo "5. Node Exporter (9100):"
if curl -s http://localhost:9100/metrics > /dev/null 2>&1; then
    echo "   ✅ 실행 중"
else
    echo "   ❌ 실행 안됨"
fi

echo ""
echo "=========================================="
echo "프로세스 확인:"
echo "=========================================="
ps aux | grep -E "app.py|websocket_server|prometheus|node_exporter" | grep -v grep

echo ""
echo "=========================================="
echo "포트 확인:"
echo "=========================================="
netstat -tlnp 2>/dev/null | grep -E "3010|5010|5011|9090|9100" || ss -tlnp | grep -E "3010|5010|5011|9090|9100"
