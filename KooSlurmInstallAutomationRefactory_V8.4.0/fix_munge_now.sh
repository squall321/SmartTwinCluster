#!/bin/bash
################################################################################
# install_munge_auto.sh 즉시 교체 및 테스트
################################################################################

echo "================================================================================"
echo "🔄 install_munge_auto.sh 즉시 교체"
echo "================================================================================"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 백업
if [ -f "install_munge_auto.sh" ]; then
    BACKUP="install_munge_auto.sh.backup_$(date +%Y%m%d_%H%M%S)"
    cp install_munge_auto.sh "$BACKUP"
    echo "✅ 백업 생성: $BACKUP"
fi

# 교체
if [ -f "install_munge_auto_fixed.sh" ]; then
    cp install_munge_auto_fixed.sh install_munge_auto.sh
    chmod +x install_munge_auto.sh
    echo "✅ install_munge_auto.sh 교체 완료"
else
    echo "❌ install_munge_auto_fixed.sh를 찾을 수 없습니다!"
    exit 1
fi

echo ""
echo "================================================================================"
echo "✨ 개선 사항"
echo "================================================================================"
echo ""
echo "  ✅ USE_SSHPASS 변수로 SSH 키 vs sshpass 자동 선택"
echo "  ✅ ssh_cmd() 함수: SSH 명령 실행"
echo "  ✅ scp_cmd() 함수: 파일 복사"
echo "  ✅ Step 4/5에서 scp_cmd() 사용 → 비밀번호 자동 전달"
echo ""
echo "================================================================================"
echo "🧪 즉시 테스트"
echo "================================================================================"
echo ""

read -p "지금 바로 Munge 설치를 테스트하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🚀 Munge 설치 시작..."
    echo ""
    ./install_munge_auto.sh
else
    echo ""
    echo "⏭️  나중에 테스트하려면:"
    echo "   ./install_munge_auto.sh"
fi

echo ""
echo "================================================================================"
