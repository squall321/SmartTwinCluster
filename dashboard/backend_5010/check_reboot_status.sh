#!/bin/bash
# 노드 reboot 명령 실행 여부 확인 디버그 스크립트

echo "================================================================================"
echo "🔍 Reboot 명령어 실행 확인"
echo "================================================================================"
echo ""

# 1. 백엔드 로그 확인
echo "📋 Step 1/5: 최근 Reboot 로그 확인"
echo "--------------------------------------------------------------------------------"
tail -50 /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010/logs/backend.log | grep -A 5 -B 2 -i "reboot"
echo ""

# 2. Slurm 노드 상태 확인
echo "📊 Step 2/5: 현재 노드 상태"
echo "--------------------------------------------------------------------------------"
sinfo -N -o "%.10N %.10T %.15B %.15C %.6t %.8f"
echo ""

# 3. RebootProgram 설정 확인
echo "🔧 Step 3/5: slurm.conf의 RebootProgram 확인"
echo "--------------------------------------------------------------------------------"
if grep -q "^RebootProgram" /usr/local/slurm/etc/slurm.conf; then
    grep "^RebootProgram" /usr/local/slurm/etc/slurm.conf
    echo "✅ RebootProgram이 설정되어 있습니다"
else
    echo "❌ RebootProgram이 설정되어 있지 않습니다!"
    echo ""
    echo "slurm.conf에 다음 줄을 추가해야 합니다:"
    echo "RebootProgram=/sbin/reboot"
fi
echo ""

# 4. scontrol reboot 명령어 직접 테스트
echo "🧪 Step 4/5: scontrol reboot 명령어 테스트 (DRY RUN)"
echo "--------------------------------------------------------------------------------"
SCONTROL_PATH=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")
echo "scontrol 경로: $SCONTROL_PATH"
echo ""

# 노드 목록 가져오기
FIRST_NODE=$(sinfo -N -h -o "%N" | head -1)
if [ -n "$FIRST_NODE" ]; then
    echo "테스트 대상 노드: $FIRST_NODE"
    echo ""
    echo "실행할 명령어:"
    echo "  sudo -n $SCONTROL_PATH reboot $FIRST_NODE reason='test'"
    echo ""
    
    read -p "실제로 $FIRST_NODE를 재부팅하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "재부팅 명령 실행 중..."
        sudo -n $SCONTROL_PATH reboot $FIRST_NODE reason='test'
        RESULT=$?
        
        if [ $RESULT -eq 0 ]; then
            echo "✅ 명령어 실행 성공 (Exit Code: 0)"
            echo ""
            echo "노드 상태 확인 (10초 후)..."
            sleep 10
            scontrol show node $FIRST_NODE | grep -E "State|Reason"
        else
            echo "❌ 명령어 실행 실패 (Exit Code: $RESULT)"
        fi
    else
        echo "⚠️  테스트를 건너뜁니다"
    fi
else
    echo "❌ 노드를 찾을 수 없습니다"
fi
echo ""

# 5. Slurm 로그 확인
echo "📄 Step 5/5: Slurm 컨트롤러 로그 확인"
echo "--------------------------------------------------------------------------------"
if [ -f "/var/log/slurm/slurmctld.log" ]; then
    echo "최근 reboot 관련 로그:"
    tail -100 /var/log/slurm/slurmctld.log | grep -i "reboot"
elif [ -f "/var/log/slurmctld.log" ]; then
    echo "최근 reboot 관련 로그:"
    tail -100 /var/log/slurmctld.log | grep -i "reboot"
else
    echo "⚠️  slurmctld 로그 파일을 찾을 수 없습니다"
    echo ""
    echo "일반적인 위치:"
    echo "  - /var/log/slurm/slurmctld.log"
    echo "  - /var/log/slurmctld.log"
    echo "  - /usr/local/slurm/log/slurmctld.log"
fi
echo ""

echo "================================================================================"
echo "🔍 진단 완료"
echo "================================================================================"
echo ""
echo "📝 문제 해결 방법:"
echo ""
echo "1️⃣ RebootProgram이 없는 경우:"
echo "   - slurm.conf에 'RebootProgram=/sbin/reboot' 추가"
echo "   - sudo systemctl restart slurmctld"
echo ""
echo "2️⃣ sudo 권한 문제:"
echo "   - sudo -n $SCONTROL_PATH show config  # 테스트"
echo "   - /etc/sudoers.d/slurm-dashboard 확인"
echo ""
echo "3️⃣ 노드가 재부팅되지 않는 경우:"
echo "   - RebootProgram 스크립트 권한 확인"
echo "   - 노드와의 SSH 연결 확인"
echo "   - slurm.conf의 RebootProgram 경로 확인"
echo ""
