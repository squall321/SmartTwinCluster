#!/bin/bash
################################################################################
# Phase 0 - 현재 상태 자동 수집
################################################################################

OUTPUT_FILE="CURRENT_STATE.md"

cat > "$OUTPUT_FILE" << HEADER
# 현재 시스템 상태 (Phase 0)

생성 일시: $(date '+%Y-%m-%d %H:%M:%S')
수집 스크립트: collect_current_state.sh

---

HEADER

echo "📊 현재 시스템 상태 수집 중..."
echo ""

# ==========================================
# 1. 포트 사용 현황
# ==========================================
echo "1️⃣ 포트 사용 현황 수집..."

cat >> "$OUTPUT_FILE" << 'EOF'
## 1. 포트 사용 현황

| 포트 | 상태 | PID | 프로세스 | 서비스 |
|------|------|-----|---------|--------|
EOF

for PORT in 3010 4430 4431 5000 5001 5010 5011 5173 8002 9090 9100; do
    if lsof -ti:$PORT &>/dev/null; then
        PID=$(lsof -ti:$PORT)
        PROCESS=$(ps -p $PID -o comm= 2>/dev/null || echo "unknown")
        SERVICE=$(ps -p $PID -o args= 2>/dev/null | awk '{print $NF}' | xargs basename)
        echo "| $PORT | 🟢 사용 중 | $PID | $PROCESS | $SERVICE |" >> "$OUTPUT_FILE"
    else
        echo "| $PORT | ⚪ 미사용 | - | - | - |" >> "$OUTPUT_FILE"
    fi
done

# ==========================================
# 2. 디렉토리 구조
# ==========================================
echo "2️⃣ 디렉토리 구조 수집..."

cat >> "$OUTPUT_FILE" << 'EOF'

## 2. Dashboard 디렉토리 구조

```
EOF

tree -L 2 dashboard/ -I 'node_modules|venv|__pycache__|*.pyc|logs' >> "$OUTPUT_FILE" 2>/dev/null || \
    find dashboard/ -maxdepth 2 -type d | sort >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
```

EOF

# ==========================================
# 3. 서비스별 의존성
# ==========================================
echo "3️⃣ 서비스별 의존성 수집..."

cat >> "$OUTPUT_FILE" << 'EOF'
## 3. 서비스별 의존성

| 서비스 | Python venv | Node.js | requirements.txt | package.json |
|--------|-------------|---------|------------------|--------------|
EOF

for SERVICE_DIR in dashboard/auth_portal_4430 \
                   dashboard/auth_portal_4431 \
                   dashboard/backend_5010 \
                   dashboard/frontend_3010 \
                   dashboard/websocket_5011 \
                   dashboard/vnc_service_8002 \
                   dashboard/kooCAEWeb_5173; do
    if [ -d "$SERVICE_DIR" ]; then
        SERVICE_NAME=$(basename "$SERVICE_DIR")
        HAS_VENV="❌"
        HAS_NODE="❌"
        HAS_REQ="❌"
        HAS_PKG="❌"

        [ -d "$SERVICE_DIR/venv" ] && HAS_VENV="✅"
        [ -d "$SERVICE_DIR/node_modules" ] && HAS_NODE="✅"
        [ -f "$SERVICE_DIR/requirements.txt" ] && HAS_REQ="✅"
        [ -f "$SERVICE_DIR/package.json" ] && HAS_PKG="✅"

        echo "| $SERVICE_NAME | $HAS_VENV | $HAS_NODE | $HAS_REQ | $HAS_PKG |" >> "$OUTPUT_FILE"
    fi
done

# ==========================================
# 4. 환경 변수 사용 현황
# ==========================================
echo "4️⃣ 환경 변수 사용 현황 수집..."

cat >> "$OUTPUT_FILE" << 'EOF'

## 4. 환경 변수 사용 현황

### Python (os.getenv)
```python
EOF

grep -rh "os.getenv" dashboard/auth_portal_4430 dashboard/backend_5010 \
    --include="*.py" 2>/dev/null | grep -v "^#" | sort -u >> "$OUTPUT_FILE" || echo "없음" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
```

### TypeScript/JavaScript (process.env)
```typescript
EOF

grep -rh "process.env\|import.meta.env" dashboard/auth_portal_4431 dashboard/frontend_3010 \
    --include="*.tsx" --include="*.ts" 2>/dev/null | grep -v "^[[:space:]]*//\|^[[:space:]]*\*" | sort -u >> "$OUTPUT_FILE" || echo "없음" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
```

EOF

# ==========================================
# 5. Nginx 상태
# ==========================================
echo "5️⃣ Nginx 상태 수집..."

cat >> "$OUTPUT_FILE" << 'EOF'
## 5. Nginx 상태

EOF

if command -v nginx &>/dev/null; then
    echo "- 설치됨: $(nginx -v 2>&1 | awk '{print $3}')" >> "$OUTPUT_FILE"

    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "- 상태: 🟢 실행 중" >> "$OUTPUT_FILE"
    else
        echo "- 상태: 🔴 중지됨" >> "$OUTPUT_FILE"
    fi

    echo "" >> "$OUTPUT_FILE"
    echo "### 현재 Nginx 설정 파일" >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
    ls -la /etc/nginx/sites-enabled/ 2>/dev/null >> "$OUTPUT_FILE" || echo "설정 파일 없음" >> "$OUTPUT_FILE"
    echo '```' >> "$OUTPUT_FILE"
else
    echo "- 설치 안됨" >> "$OUTPUT_FILE"
fi

# ==========================================
# 6. 하드코딩된 URL 검색
# ==========================================
echo "6️⃣ 하드코딩된 URL 검색..."

cat >> "$OUTPUT_FILE" << 'EOF'

## 6. 하드코딩된 localhost URL

### Python 파일
```python
EOF

grep -rn "localhost:[0-9]" dashboard/auth_portal_4430 \
    --include="*.py" 2>/dev/null | grep -v "venv\|__pycache__" >> "$OUTPUT_FILE" || echo "없음" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
```

### TypeScript 파일
```typescript
EOF

grep -rn "localhost:[0-9]\|127\.0\.0\.1" dashboard/auth_portal_4431/src dashboard/vnc_service_8002/src \
    --include="*.tsx" --include="*.ts" 2>/dev/null >> "$OUTPUT_FILE" || echo "없음" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
```

EOF

# ==========================================
# 7. 시스템 정보
# ==========================================
echo "7️⃣ 시스템 정보 수집..."

cat >> "$OUTPUT_FILE" << EOF

## 7. 시스템 정보

- OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
- Kernel: $(uname -r)
- Python: $(python3 --version 2>/dev/null || echo "없음")
- Node.js: $(node --version 2>/dev/null || echo "없음")
- npm: $(npm --version 2>/dev/null || echo "없음")
- Nginx: $(nginx -v 2>&1 | awk '{print $3}' || echo "없음")

EOF

echo ""
echo "✅ 현재 상태 수집 완료: $OUTPUT_FILE"
echo "   파일 크기: $(wc -l < "$OUTPUT_FILE") 줄"
