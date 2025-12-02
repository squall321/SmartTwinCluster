#!/bin/bash

echo "=========================================="
echo "Check Templates API"
echo "=========================================="
echo ""

# Check MOCK_MODE environment variable
echo "1. Checking MOCK_MODE..."
if [ -z "$MOCK_MODE" ]; then
    echo "   MOCK_MODE not set (defaults to 'true')"
    echo "   ⚠️  This means API is in MOCK MODE"
else
    echo "   MOCK_MODE = $MOCK_MODE"
fi
echo ""

# Check backend process
echo "2. Checking backend process..."
if pgrep -f "python.*app.py" > /dev/null; then
    echo "   ✅ Backend is running"
    PID=$(pgrep -f "python.*app.py")
    echo "   PID: $PID"
    
    # Check environment variables of running process
    echo ""
    echo "   Environment variables:"
    cat /proc/$PID/environ | tr '\0' '\n' | grep MOCK_MODE || echo "   (MOCK_MODE not found in process env)"
else
    echo "   ❌ Backend is not running"
fi
echo ""

# Test API call
echo "3. Testing API endpoint..."
RESPONSE=$(curl -s http://localhost:5010/api/jobs/templates)
echo "   API Response:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

echo "=========================================="
echo "To fix: Set MOCK_MODE=false and restart"
echo "=========================================="
echo ""
echo "export MOCK_MODE=false"
echo "cd backend_5010"
echo "./restart_backend.sh"
