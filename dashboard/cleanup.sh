#!/bin/bash

echo "🧹 Cleaning up all processes..."

# Kill all node/npm processes
pkill -9 -f "npm run dev" 2>/dev/null
pkill -9 -f "vite" 2>/dev/null
pkill -9 -f "node.*5174" 2>/dev/null

# Kill all Python processes
pkill -9 -f "kooCAEWebServer_5000" 2>/dev/null
pkill -9 -f "app.py" 2>/dev/null

# Kill processes on specific ports
for port in 5174 5000 4430 4431; do
    lsof -ti:$port 2>/dev/null | xargs kill -9 2>/dev/null
done

sleep 2

echo "✅ Cleanup complete!"
echo ""
echo "Now starting services..."
echo ""

# Start backend
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/kooCAEWebServer_5000
./venv/bin/python app.py > /tmp/backend_5000.log 2>&1 &
BACKEND_PID=$!
echo "✅ Backend started (PID: $BACKEND_PID)"

# Wait for backend
sleep 3

# Start frontend
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174
PORT=5174 npm run dev > /tmp/frontend_5174.log 2>&1 &
FRONTEND_PID=$!
echo "✅ Frontend started (PID: $FRONTEND_PID)"

# Wait for frontend
sleep 5

echo ""
echo "🎉 Services started successfully!"
echo ""
echo "📊 Status:"
echo "  Backend:  http://localhost:5000 (PID: $BACKEND_PID)"
echo "  Frontend: http://localhost:5174 (PID: $FRONTEND_PID)"
echo ""
echo "📝 Logs:"
echo "  Backend:  tail -f /tmp/backend_5000.log"
echo "  Frontend: tail -f /tmp/frontend_5174.log"
