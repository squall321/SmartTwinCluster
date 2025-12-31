#!/bin/bash
#
# Slurm sudoers 설정 스크립트
# 웹 서버 사용자가 scontrol 명령을 비밀번호 없이 실행할 수 있도록 설정
#
# 사용법: sudo ./setup_slurm_sudoers.sh [username]
# 기본값: 현재 사용자
#

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 기본 사용자 설정
WEB_USER="${1:-$(whoami)}"

# scontrol 경로 찾기
SCONTROL_PATH=""
for path in /usr/bin/scontrol /usr/local/bin/scontrol /usr/local/slurm/bin/scontrol; do
    if [ -x "$path" ]; then
        SCONTROL_PATH="$path"
        break
    fi
done

if [ -z "$SCONTROL_PATH" ]; then
    echo -e "${RED}Error: scontrol not found${NC}"
    echo "Please ensure Slurm is installed"
    exit 1
fi

echo -e "${GREEN}=== Slurm Sudoers Setup ===${NC}"
echo "Web user: $WEB_USER"
echo "scontrol path: $SCONTROL_PATH"
echo ""

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0 [username]"
    exit 1
fi

# sudoers 파일 내용
SUDOERS_FILE="/etc/sudoers.d/slurm-web"
SUDOERS_CONTENT="# Allow web server user to manage Slurm partitions without password
# Created by setup_slurm_sudoers.sh

# scontrol commands for partition management
$WEB_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH create *
$WEB_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH update *
$WEB_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH delete *
"

# 기존 파일 백업
if [ -f "$SUDOERS_FILE" ]; then
    echo -e "${YELLOW}Backing up existing sudoers file...${NC}"
    cp "$SUDOERS_FILE" "${SUDOERS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
fi

# sudoers 파일 생성
echo -e "${GREEN}Creating sudoers file: $SUDOERS_FILE${NC}"
echo "$SUDOERS_CONTENT" > "$SUDOERS_FILE"

# 권한 설정 (sudoers 파일은 반드시 440)
chmod 440 "$SUDOERS_FILE"

# 문법 검증
echo -e "${GREEN}Validating sudoers syntax...${NC}"
if visudo -c -f "$SUDOERS_FILE"; then
    echo -e "${GREEN}✅ Sudoers file is valid${NC}"
else
    echo -e "${RED}❌ Sudoers file has syntax errors!${NC}"
    rm -f "$SUDOERS_FILE"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo "User '$WEB_USER' can now run the following commands without password:"
echo "  - sudo $SCONTROL_PATH create ..."
echo "  - sudo $SCONTROL_PATH update ..."
echo "  - sudo $SCONTROL_PATH delete ..."
echo ""
echo "To test, run as $WEB_USER:"
echo "  sudo -n $SCONTROL_PATH show partition"
echo ""
