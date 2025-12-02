#!/bin/bash

echo "================================================================================"
echo "🔧 올바른 scontrol reboot 문법으로 수정"
echo "================================================================================"
echo ""

# 1. scontrol 경로 확인
SCONTROL_PATH=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")
echo "📍 scontrol 경로: $SCONTROL_PATH"
echo ""

# 2. 명령어 테스트
echo "🧪 명령어 문법 테스트"
echo "--------------------------------------------------------------------------------"
echo ""
echo "❌ 잘못된 문법:"
echo "   scontrol reboot node001 node002 reason='test'"
echo "   → 여러 노드를 한 번에 지정하면 에러"
echo ""
echo "✅ 올바른 문법 1: 개별 노드"
echo "   scontrol reboot node001 reason='test'"
echo "   scontrol reboot node002 reason='test'"
echo ""
echo "✅ 올바른 문법 2: 노드리스트 형식"
echo "   scontrol reboot node[001-002] reason='test'"
echo ""
echo "✅ 올바른 문법 3: ASAP 옵션"
echo "   scontrol reboot ASAP reason='test' node001"
echo ""

# 3. 실제 테스트
FIRST_NODE=$(sinfo -N -h -o "%N" | head -1)
echo "테스트 대상 노드: $FIRST_NODE"
echo ""

read -p "명령어 테스트를 하시겠습니까? (실제 재부팅 안됨, 문법만 확인) (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "테스트 1: 직접 실행 (sudo 없이)"
    echo "명령어: $SCONTROL_PATH reboot $FIRST_NODE reason='syntax_test'"
    $SCONTROL_PATH reboot $FIRST_NODE reason='syntax_test'
    RESULT=$?
    
    if [ $RESULT -eq 0 ]; then
        echo "✅ 명령어 실행 성공 (Exit Code: 0)"
    else
        echo "⚠️  Exit Code: $RESULT"
    fi
    
    echo ""
    echo "테스트 2: sudo로 실행 (전체 경로)"
    echo "명령어: sudo $SCONTROL_PATH reboot $FIRST_NODE reason='syntax_test'"
    sudo $SCONTROL_PATH reboot $FIRST_NODE reason='syntax_test'
    RESULT=$?
    
    if [ $RESULT -eq 0 ]; then
        echo "✅ sudo 명령어 실행 성공 (Exit Code: 0)"
    else
        echo "⚠️  Exit Code: $RESULT"
    fi
fi
echo ""

echo "================================================================================"
echo "✅ 테스트 완료"
echo "================================================================================"
echo ""
echo "📝 정리:"
echo ""
echo "1. scontrol reboot 명령어는 한 번에 하나의 노드만 재부팅"
echo "2. 여러 노드를 재부팅하려면:"
echo "   - 반복문 사용: for node in node001 node002; do scontrol reboot \$node reason='test'; done"
echo "   - 노드리스트: scontrol reboot node[001-002] reason='test'"
echo ""
echo "3. sudo 사용 시 전체 경로 필요:"
echo "   sudo $SCONTROL_PATH reboot node001 reason='test'"
echo ""
