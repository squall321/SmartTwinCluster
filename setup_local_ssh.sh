#!/bin/bash
################################################################################
# 로컬 SSH 키 설정 스크립트
# 자기 자신에게 SSH 키를 등록합니다
################################################################################

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   로컬 SSH 키 설정 도구                                    ║"
echo "║   (자기 자신에게 SSH 키 등록)                              ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

SSH_KEY_PATH="$HOME/.ssh/id_rsa"
SSH_PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"

echo -e "${BLUE}1단계: SSH 키 확인${NC}"
echo "─────────────────────────────────────────"

# SSH 키 확인
if [ -f "$SSH_KEY_PATH" ] && [ -f "$SSH_PUB_KEY_PATH" ]; then
    echo -e "${GREEN}✓${NC} SSH 키 존재: $SSH_KEY_PATH"
else
    echo -e "${RED}✗${NC} SSH 키가 없습니다!"
    echo ""
    read -p "새 SSH 키를 생성하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "SSH 키 생성 중..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
        echo -e "${GREEN}✓${NC} SSH 키 생성 완료"
    else
        echo "SSH 키가 필요합니다. 종료합니다."
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}2단계: 자기 자신에게 SSH 키 등록${NC}"
echo "─────────────────────────────────────────"

# 현재 상태 확인
echo -n "현재 상태 확인... "
if ssh -o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR localhost "exit" 2>/dev/null; then
    echo -e "${GREEN}✓ 이미 설정되어 있습니다!${NC}"
    echo ""
    echo "자기 자신에게 비밀번호 없이 SSH 접속이 가능합니다."
    echo ""
    echo "테스트:"
    echo "  ssh localhost \"hostname\""
    echo ""
    exit 0
fi

echo "설정 필요"
echo ""

# authorized_keys 파일 확인
if [ ! -f ~/.ssh/authorized_keys ]; then
    echo "authorized_keys 파일 생성 중..."
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo -e "${GREEN}✓${NC} 파일 생성 완료"
else
    echo -e "${GREEN}✓${NC} authorized_keys 파일 존재"
fi

# 권한 확인
AUTH_KEYS_PERM=$(stat -c %a ~/.ssh/authorized_keys)
if [ "$AUTH_KEYS_PERM" != "600" ]; then
    echo "authorized_keys 권한 수정 중..."
    chmod 600 ~/.ssh/authorized_keys
    echo -e "${GREEN}✓${NC} 권한 수정 완료 (600)"
fi

# 공개키 추가
echo ""
echo "공개키 추가 중..."

PUB_KEY_CONTENT=$(cat "$SSH_PUB_KEY_PATH")

if grep -q "$PUB_KEY_CONTENT" ~/.ssh/authorized_keys 2>/dev/null; then
    echo -e "${YELLOW}ℹ${NC} 공개키가 이미 존재합니다"
else
    cat "$SSH_PUB_KEY_PATH" >> ~/.ssh/authorized_keys
    echo -e "${GREEN}✓${NC} 공개키 추가 완료"
fi

echo ""
echo -e "${BLUE}3단계: 연결 테스트${NC}"
echo "─────────────────────────────────────────"

# 테스트
echo "SSH 연결 테스트 중..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR localhost "hostname" >/dev/null 2>&1; then
    HOSTNAME=$(ssh -o LogLevel=ERROR localhost "hostname" 2>/dev/null)
    echo -e "${GREEN}✓${NC} SSH 연결 성공!"
    echo "  호스트명: $HOSTNAME"
else
    echo -e "${RED}✗${NC} SSH 연결 실패"
    echo ""
    echo "문제 해결:"
    echo "  1. SSH 서비스 확인: systemctl status sshd"
    echo "  2. 방화벽 확인: sudo ufw status"
    echo "  3. SSH 설정 확인: cat /etc/ssh/sshd_config"
    exit 1
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║   ✅ 로컬 SSH 키 설정이 완료되었습니다!                    ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 이제 다음 작업이 가능합니다:${NC}"
echo ""
echo "1. 로컬 SSH 연결 (비밀번호 없이)"
echo -e "   ${YELLOW}ssh localhost \"hostname\"${NC}"
echo ""
echo "2. SSH 연결 테스트"
echo -e "   ${YELLOW}./test_connection.py my_cluster.yaml${NC}"
echo ""
echo "3. 다른 노드에 SSH 키 배포"
echo -e "   ${YELLOW}./setup_ssh_keys.sh${NC}"
echo ""

echo "Happy Computing! 🚀"
echo ""
