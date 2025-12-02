#!/bin/bash

LOG_DIR="$(dirname "$0")/logs"
PID_FILE="$LOG_DIR/idp.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Stopping SAML-IdP (PID: $PID)..."
        kill $PID
        rm "$PID_FILE"
        echo "✓ SAML-IdP stopped"
    else
        echo "SAML-IdP is not running (stale PID file)"
        rm "$PID_FILE"
    fi
else
    echo "SAML-IdP is not running (no PID file)"
fi
