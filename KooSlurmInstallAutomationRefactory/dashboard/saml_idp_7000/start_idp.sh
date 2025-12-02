#!/bin/bash

PORT=7000
HOST="0.0.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
CERT_DIR="$SCRIPT_DIR/certs"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"

# 기존 프로세스 확인
if pgrep -f "saml-idp.*port $PORT" > /dev/null; then
    echo "SAML-IdP가 이미 실행 중입니다."
    exit 1
fi

echo "Starting SAML-IdP on port $PORT..."

npx saml-idp \
  --port $PORT \
  --host $HOST \
  --issuer "http://localhost:$PORT/metadata" \
  --acsUrl "http://localhost:4430/auth/saml/acs" \
  --audience "auth-portal" \
  --cert "$CERT_DIR/idp-cert.pem" \
  --key "$CERT_DIR/idp-key.pem" \
  --config "$CONFIG_DIR/users.json" \
  > "$LOG_DIR/idp.log" 2>&1 &

PID=$!
echo $PID > "$LOG_DIR/idp.pid"

sleep 2

if ps -p $PID > /dev/null; then
    echo "✓ SAML-IdP started successfully (PID: $PID)"
    echo "  Metadata URL: http://localhost:$PORT/metadata"
    echo "  SSO URL: http://localhost:$PORT/saml/sso"
    echo "  Log file: $LOG_DIR/idp.log"
else
    echo "✗ Failed to start SAML-IdP"
    cat "$LOG_DIR/idp.log"
    exit 1
fi
