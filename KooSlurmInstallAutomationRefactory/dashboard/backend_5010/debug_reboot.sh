#!/bin/bash

echo "================================================================================"
echo "🔍 Reboot 실행 여부 상세 확인"
echo "================================================================================"
echo ""

# 1. Slurm 컨트롤러 로그 확인 (sudo 사용)
echo "📄 Step 1/4: Slurm 컨트롤러 로그 확인"
echo "--------------------------------------------------------------------------------"
if [ -f "/var/log/slurm/slurmctld.log" ]; then
    echo "최근 10줄의 reboot 관련 로그:"
    sudo tail -200 /var/log/slurm/slurmctld.log | grep -i "reboot" | tail -10
    echo ""
    echo "전체 최근 로그:"
    sudo tail -50 /var/log/slurm/slurmctld.log
elif [ -f "/var/log/slurmctld.log" ]; then
    echo "최근 10줄의 reboot 관련 로그:"
    sudo tail -200 /var/log/slurmctld.log | grep -i "reboot" | tail -10
else
    echo "❌ slurmctld 로그를 찾을 수 없습니다"
    echo ""
    echo "로그 위치 찾기:"
    sudo find /var/log /usr/local/slurm -name "*slurmctld*.log" 2>/dev/null
fi
echo ""

# 2. RebootProgram 스크립트 확인
echo "🔧 Step 2/4: RebootProgram 스크립트 확인"
echo "--------------------------------------------------------------------------------"
REBOOT_PROGRAM=$(grep "^RebootProgram" /usr/local/slurm/etc/slurm.conf | awk -F= '{print $2}' | tr -d ' ')
echo "RebootProgram: $REBOOT_PROGRAM"

if [ -f "$REBOOT_PROGRAM" ]; then
    echo "✅ 스크립트 존재"
    echo "권한: $(ls -l $REBOOT_PROGRAM)"
    echo ""
    echo "스크립트 내용:"
    cat $REBOOT_PROGRAM
else
    echo "❌ RebootProgram 스크립트가 존재하지 않습니다: $REBOOT_PROGRAM"
fi
echo ""

# 3. 노드와의 SSH 연결 확인
echo "🔗 Step 3/4: 노드와의 연결 확인"
echo "--------------------------------------------------------------------------------"
FIRST_NODE=$(sinfo -N -h -o "%N" | head -1)
echo "테스트 노드: $FIRST_NODE"
echo ""

echo "Ping 테스트:"
ping -c 2 $FIRST_NODE 2>&1 | grep -E "bytes from|100%"
echo ""

echo "SSH 연결 테스트:"
timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 $FIRST_NODE "echo 'SSH OK'" 2>&1
echo ""

# 4. scontrol show node로 상세 상태 확인
echo "📊 Step 4/4: 노드 상세 상태"
echo "--------------------------------------------------------------------------------"
scontrol show node $FIRST_NODE
echo ""

echo "================================================================================"
echo "🔍 진단 결과"
echo "================================================================================"
echo ""

# 진단 요약
echo "📝 요약:"
echo ""

# RebootProgram이 실제로 실행되었는지 확인
if sudo tail -100 /var/log/slurm/slurmctld.log 2>/dev/null | grep -q "reboot"; then
    echo "✅ Slurm 컨트롤러가 reboot 명령을 받았습니다"
else
    echo "⚠️  Slurm 컨트롤러 로그에 reboot 기록이 없습니다"
fi

if [ -f "$REBOOT_PROGRAM" ]; then
    echo "✅ RebootProgram 스크립트 존재"
else
    echo "❌ RebootProgram 스크립트 없음 → 실제 재부팅 안됨"
fi

if ping -c 1 $FIRST_NODE >/dev/null 2>&1; then
    echo "✅ 노드 Ping 응답"
else
    echo "❌ 노드 Ping 응답 없음"
fi

echo ""
echo "================================================================================"
echo "🎯 다음 단계"
echo "================================================================================"
echo ""
echo "문제 1: RebootProgram이 실제로 노드를 재부팅하지 않는 경우"
echo "  → RebootProgram을 SSH 기반 스크립트로 변경 필요"
echo ""
echo "문제 2: 노드가 VM이거나 컨테이너인 경우"
echo "  → /sbin/reboot가 작동하지 않을 수 있음"
echo ""
echo "문제 3: 권한 문제"
echo "  → RebootProgram 스크립트가 root 권한으로 실행되는지 확인"
echo ""
echo "해결 방법:"
echo "  1. 커스텀 RebootProgram 스크립트 생성"
echo "  2. SSH를 통한 원격 재부팅 구현"
echo "  3. 또는 Mock Mode에서 테스트"
echo ""
