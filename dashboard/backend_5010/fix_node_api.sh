#!/bin/bash
# 노드 관리 API 수정 스크립트

echo "================================================================================"
echo "🔧 Node Management API 수정 스크립트"
echo "================================================================================"
echo ""
echo "이 스크립트는 다음 문제를 해결합니다:"
echo "  1️⃣ 중복 노드 Key 경고 (React Warning)"
echo "  2️⃣ Reboot API 500 에러"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 백업
echo "📦 Step 1/4: 백업 생성 중..."
if [ ! -f "node_management_api.py.backup" ]; then
    cp node_management_api.py node_management_api.py.backup
    echo "  ✅ 백업 생성: node_management_api.py.backup"
else
    echo "  ⚠️  백업 파일이 이미 존재합니다"
fi
echo ""

# 수정된 파일로 교체
echo "🔄 Step 2/4: 수정된 파일로 교체 중..."
if [ -f "node_management_api_fixed.py" ]; then
    cp node_management_api_fixed.py node_management_api.py
    echo "  ✅ node_management_api.py 교체 완료"
else
    echo "  ❌ node_management_api_fixed.py 파일을 찾을 수 없습니다"
    exit 1
fi
echo ""

# 수정 내용 확인
echo "📋 Step 3/4: 수정 내용 확인"
echo "--------------------------------------------------------------------------------"
echo "🔧 주요 수정 사항:"
echo ""
echo "1. 중복 노드 제거:"
echo "   - nodes_dict 딕셔너리 사용으로 같은 이름의 노드 자동 제거"
echo "   - sinfo 명령어가 중복 반환해도 프론트엔드는 unique한 노드만 받음"
echo ""
echo "2. Reboot 에러 해결:"
echo "   - 기존: SSH를 직접 사용 (복잡하고 에러 발생 가능)"
echo "   - 수정: 'scontrol reboot' 명령어 사용 (RebootProgram 자동 실행)"
echo "   - slurm.conf의 RebootProgram=/sbin/reboot가 자동으로 실행됨"
echo ""
echo "3. 에러 로깅 개선:"
echo "   - 더 자세한 에러 메시지 및 traceback"
echo ""
echo "--------------------------------------------------------------------------------"
echo ""

# 백엔드 재시작 안내
echo "🔄 Step 4/4: 백엔드 재시작 필요"
echo "--------------------------------------------------------------------------------"
echo "수정 사항을 적용하려면 백엔드를 재시작해야 합니다:"
echo ""
echo "방법 1) 수동 재시작:"
echo "  cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010"
echo "  # 기존 프로세스 종료"
echo "  pkill -f 'python.*app.py'"
echo "  # 새로 시작"
echo "  source venv/bin/activate"
echo "  python app.py"
echo ""
echo "방법 2) 자동 재시작 (이 스크립트 실행 후):"
echo "  ./restart_node_api.sh"
echo ""
echo "--------------------------------------------------------------------------------"
echo ""

# 테스트 명령어 안내
echo "🧪 테스트 방법:"
echo "--------------------------------------------------------------------------------"
echo "1. 노드 목록 조회 (중복 제거 확인):"
echo "   curl http://localhost:5010/api/nodes | jq '.nodes | length'"
echo ""
echo "2. Reboot 테스트:"
echo "   curl -X POST http://localhost:5010/api/nodes/reboot \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"node_name\": \"node001\", \"reason\": \"test\"}' | jq ."
echo ""
echo "3. 프론트엔드에서 확인:"
echo "   - http://localhost:3010 접속"
echo "   - Node Management 페이지로 이동"
echo "   - React 콘솔에서 중복 Key 경고가 사라졌는지 확인"
echo "   - Reboot 버튼 클릭 시 500 에러가 사라졌는지 확인"
echo "--------------------------------------------------------------------------------"
echo ""

echo "================================================================================"
echo "✅ 수정 완료!"
echo "================================================================================"
echo ""
echo "다음 단계: 백엔드를 재시작하세요"
echo "  ./restart_node_api.sh"
echo ""
