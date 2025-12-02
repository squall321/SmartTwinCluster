#!/bin/bash
if [ -f ".node_exporter.pid" ]; then
    kill $(cat .node_exporter.pid) 2>/dev/null && rm -f .node_exporter.pid
    echo "✅ Node Exporter 종료"
else
    echo "⚠️  Node Exporter가 실행 중이 아닙니다"
fi
