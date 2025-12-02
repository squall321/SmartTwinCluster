#!/bin/bash
# Phase 0: Redis 설치 및 설정 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Phase 0: Redis 설치 및 설정 ==="
echo

# Ubuntu 버전 확인
if ! grep -q "Ubuntu 22.04" /etc/os-release 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC} 이 스크립트는 Ubuntu 22.04용으로 작성되었습니다."
fi

# Redis 설치 확인
if ! command -v redis-server &> /dev/null; then
    echo "Redis 설치 중..."
    sudo apt update
    sudo apt install -y redis-server
    echo -e "${GREEN}✓${NC} Redis 설치 완료"
else
    REDIS_VERSION=$(redis-server --version | awk '{print $3}' | cut -d= -f2)
    echo -e "${GREEN}✓${NC} Redis가 이미 설치되어 있습니다: $REDIS_VERSION"

    if [[ "$REDIS_VERSION" < "7.0" ]]; then
        echo -e "${YELLOW}⚠${NC} Redis 버전이 7.0 미만입니다. 업그레이드를 권장합니다."
    fi
fi

# Redis 설정 파일 확인
REDIS_CONF="/etc/redis/redis.conf"

if ! sudo test -f "$REDIS_CONF"; then
    echo -e "${RED}✗${NC} Redis 설정 파일을 찾을 수 없습니다: $REDIS_CONF"
    exit 1
fi

echo
echo "Redis 설정 업데이트 중..."

# 설정 백업
sudo cp $REDIS_CONF ${REDIS_CONF}.backup_$(date +%Y%m%d_%H%M%S)

# 임시 파일에서 작업
TEMP_CONF=$(mktemp)
sudo cat $REDIS_CONF > $TEMP_CONF

# 1. bind 설정
if ! grep -q "^bind 127.0.0.1" $TEMP_CONF; then
    echo "  - bind 127.0.0.1 설정..."
    sed -i 's/^bind .*/bind 127.0.0.1 -::1/' $TEMP_CONF
else
    echo "  - bind 설정 이미 완료"
fi

# 2. maxmemory 설정
if ! grep -q "^maxmemory 512mb" $TEMP_CONF; then
    echo "  - maxmemory 512mb 설정..."
    # 기존 maxmemory 설정 제거
    sed -i '/^maxmemory /d' $TEMP_CONF
    # 주석처리된 줄 찾아서 그 다음에 추가
    if grep -q "^# maxmemory <bytes>" $TEMP_CONF; then
        sed -i '/^# maxmemory <bytes>/a maxmemory 512mb' $TEMP_CONF
    else
        echo "maxmemory 512mb" >> $TEMP_CONF
    fi
else
    echo "  - maxmemory 설정 이미 완료"
fi

# 3. maxmemory-policy 설정
if ! grep -q "^maxmemory-policy allkeys-lru" $TEMP_CONF; then
    echo "  - maxmemory-policy allkeys-lru 설정..."
    # 기존 maxmemory-policy 설정 제거
    sed -i '/^maxmemory-policy /d' $TEMP_CONF
    # 주석처리된 줄 찾아서 그 다음에 추가
    if grep -q "^# maxmemory-policy noeviction" $TEMP_CONF; then
        sed -i '/^# maxmemory-policy noeviction/a maxmemory-policy allkeys-lru' $TEMP_CONF
    else
        echo "maxmemory-policy allkeys-lru" >> $TEMP_CONF
    fi
else
    echo "  - maxmemory-policy 설정 이미 완료"
fi

# 임시 파일을 실제 설정 파일로 복사
sudo cp $TEMP_CONF $REDIS_CONF
rm $TEMP_CONF

echo -e "${GREEN}✓${NC} Redis 설정 업데이트 완료"

# Redis 서비스 시작 및 활성화
echo
echo "Redis 서비스 시작 중..."

sudo systemctl enable redis-server
sudo systemctl restart redis-server

# 서비스 시작 대기
sleep 2

# 서비스 상태 확인
if sudo systemctl is-active --quiet redis-server; then
    echo -e "${GREEN}✓${NC} Redis 서비스 실행 중"
else
    echo -e "${RED}✗${NC} Redis 서비스 시작 실패"
    echo "상태 확인: sudo systemctl status redis-server"
    exit 1
fi

# Redis 연결 테스트
echo
echo "Redis 연결 테스트 중..."

if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo -e "${GREEN}✓${NC} Redis 응답 정상 (PING → PONG)"
else
    echo -e "${RED}✗${NC} Redis 연결 실패"
    echo "로그 확인: sudo journalctl -xeu redis-server.service"
    exit 1
fi

# 설정 확인
echo
echo "Redis 설정 확인..."
echo "  Bind address: $(sudo grep '^bind' $REDIS_CONF)"
echo "  Max memory: $(sudo grep '^maxmemory 512mb' $REDIS_CONF)"
echo "  Memory policy: $(sudo grep '^maxmemory-policy' $REDIS_CONF)"

echo
echo -e "${GREEN}✓✓✓ Phase 0: Redis 설치 및 설정 완료! ✓✓✓${NC}"
echo
echo "Redis 포트: 6379 (localhost only)"
echo "Redis 상태: sudo systemctl status redis-server"
echo "Redis 로그: sudo journalctl -u redis-server"
echo "설정 파일: $REDIS_CONF"
echo
echo "다음 단계: ./setup_phase0_saml_idp.sh"
