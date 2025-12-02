#!/bin/bash
if [ -f ".prometheus.pid" ]; then
    kill $(cat .prometheus.pid) 2>/dev/null && rm -f .prometheus.pid
    echo "✅ Prometheus 종료"
else
    echo "⚠️  Prometheus가 실행 중이 아닙니다"
fi
