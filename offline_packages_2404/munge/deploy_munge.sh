#!/bin/bash
# Munge 오프라인 배포 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying Munge..."

# munge 패키지 설치
if ! dpkg -s munge &>/dev/null; then
    echo "  Installing munge package..."
    apt-get install -y munge libmunge2 libmunge-dev
else
    echo "  munge already installed"
fi

# Munge 사용자 생성
if ! id munge &>/dev/null; then
    groupadd -g 1002 munge 2>/dev/null || groupadd munge 2>/dev/null || true
    useradd -u 1002 -g munge -s /bin/false munge 2>/dev/null || useradd -g munge -s /bin/false munge 2>/dev/null || true
    echo "  Created munge user"
else
    echo "  Munge user already exists"
fi

# 키 설치
mkdir -p /etc/munge

# 기존 munge.key 제거 (강제 교체)
rm -f /etc/munge/munge.key 2>/dev/null || true

# munge.key 찾기 (전송된 키만 사용 - 기존 키 무시)
MUNGE_KEY=""
if [[ -f "${SCRIPT_DIR}/munge.key" ]]; then
    MUNGE_KEY="${SCRIPT_DIR}/munge.key"
fi

if [[ -n "$MUNGE_KEY" && -f "$MUNGE_KEY" ]]; then
    cp -f "$MUNGE_KEY" /etc/munge/munge.key
    echo "  Installed munge.key from $MUNGE_KEY"
    chown munge:munge /etc/munge/munge.key
    chmod 400 /etc/munge/munge.key
else
    echo "  ERROR: munge.key not found!"
    echo "  Expected at: ${SCRIPT_DIR}/munge.key"
    echo "  Make sure controller's munge.key was transferred"
    exit 1
fi

# 서비스 시작
systemctl enable munge
systemctl restart munge

echo "✅ Munge deployed successfully"
