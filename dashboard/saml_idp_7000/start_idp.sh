#!/bin/bash

PORT=7000
HOST="0.0.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
CERT_DIR="$SCRIPT_DIR/certs"
LOG_DIR="$SCRIPT_DIR/logs"

# ── SP(auth portal)와 반드시 일치해야 하는 값 — env 로 override 가능 ─────────────
#  ★audience 는 auth portal 의 SAML_SP_ENTITY_ID 와 동일해야 함★ (불일치 시 Audience
#   restriction 검증 실패로 모든 SAML 로그인 거부). 기본값을 SP 기본(hpc-dashboard)에 맞춤.
IDP_AUDIENCE="${IDP_AUDIENCE:-hpc-dashboard}"
IDP_ISSUER="${IDP_ISSUER:-http://localhost:$PORT/metadata}"
IDP_ACS_URL="${IDP_ACS_URL:-http://localhost:4430/auth/saml/acs}"
# config.js 는 user DB + ★metadata 속성 스키마★(email/userName/groups 등)를 포함 →
# users.json(스키마 없음)과 달리 groups 등 커스텀 속성을 SAML assertion 으로 정상 발급한다.
IDP_CONFIG="${IDP_CONFIG:-$SCRIPT_DIR/config.js}"

mkdir -p "$LOG_DIR"

# 기존 프로세스 확인
if pgrep -f "saml-idp.*port $PORT" > /dev/null; then
    echo "SAML-IdP가 이미 실행 중입니다."
    exit 1
fi

echo "Starting SAML-IdP on port $PORT (audience=$IDP_AUDIENCE, config=$(basename "$IDP_CONFIG"))..."

npx saml-idp \
  --port $PORT \
  --host $HOST \
  --issuer "$IDP_ISSUER" \
  --acsUrl "$IDP_ACS_URL" \
  --audience "$IDP_AUDIENCE" \
  --cert "$CERT_DIR/idp-cert.pem" \
  --key "$CERT_DIR/idp-key.pem" \
  --config "$IDP_CONFIG" \
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
