#!/bin/bash
# Munge 오프라인 배포 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying Munge..."

# Munge 사용자 생성
if ! id munge &>/dev/null; then
    groupadd -g 1002 munge
    useradd -u 1002 -g 1002 -s /bin/false munge
fi

# 키 설치
mkdir -p /etc/munge
cp "${SCRIPT_DIR}/munge.key" /etc/munge/
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

# 서비스 시작
systemctl enable munge
systemctl restart munge

echo "✅ Munge deployed successfully"
