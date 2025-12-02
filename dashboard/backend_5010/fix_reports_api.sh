#!/bin/bash

##############################################################################
# Reports API Production 모드 수정
# 모든 엔드포인트에서 MOCK_MODE 조건 제거
##############################################################################

cd /home/koopark/claude/KooSlurmInstallAutomation/dashboard/backend

# 백업
cp reports_api.py reports_api.py.backup_$(date +%Y%m%d_%H%M%S)

# sed로 일괄 수정
# 1. "if MOCK_MODE:" 제거 및 들여쓰기 조정
# 2. "return jsonify({'error': 'Not implemented in production mode'}), 501" 제거

# Python 스크립트로 처리
python3 << 'PYTHON_SCRIPT'
import re

with open('reports_api.py', 'r', encoding='utf-8') as f:
    content = f.read()

# users_report 함수 수정
content = re.sub(
    r"(def users_report\(\):.*?start_date, end_date = get_date_range\(period\)\s*\n\s*)(if MOCK_MODE:\s*\n\s*print)",
    r"\1mode_label = \"[MOCK]\" if MOCK_MODE else \"[DEMO]\"\n    print",
    content,
    flags=re.DOTALL
)

# costs_report 함수 수정
content = re.sub(
    r"(def costs_report\(\):.*?start_date, end_date = get_date_range\(period\)\s*\n\s*)(if MOCK_MODE:\s*\n\s*print)",
    r"\1mode_label = \"[MOCK]\" if MOCK_MODE else \"[DEMO]\"\n    print",
    content,
    flags=re.DOTALL
)

# efficiency_report 함수 수정
content = re.sub(
    r"(def efficiency_report\(\):.*?start_date, end_date = get_date_range\(period\)\s*\n\s*)(if MOCK_MODE:\s*\n\s*print)",
    r"\1mode_label = \"[MOCK]\" if MOCK_MODE else \"[DEMO]\"\n    print",
    content,
    flags=re.DOTALL
)

# overview_report 함수 수정
content = re.sub(
    r"(def overview_report\(\):.*?\"\"\")\s*\n\s*(if MOCK_MODE:\s*\n\s*print)",
    r"\1\n    mode_label = \"[MOCK]\" if MOCK_MODE else \"[DEMO]\"\n    print",
    content,
    flags=re.DOTALL
)

# trends_analysis 함수 수정
content = re.sub(
    r"(def trends_analysis\(\):.*?start_date, end_date = get_date_range\(period\)\s*\n\s*)(if MOCK_MODE:\s*\n\s*print)",
    r"\1mode_label = \"[MOCK]\" if MOCK_MODE else \"[DEMO]\"\n    print",
    content,
    flags=re.DOTALL
)

# [MOCK]을 {mode_label}로 변경
content = content.replace('print(f"📊 [MOCK]', 'print(f"📊 {mode_label}')
content = content.replace('print(f"💾 [MOCK]', 'print(f"💾 {mode_label}')

# "return jsonify({'error': 'Not implemented in production mode'}), 501" 제거
content = re.sub(
    r"\s*return jsonify\(\{'error': 'Not implemented in production mode'\}\), 501",
    "",
    content
)

# 파일 저장
with open('reports_api.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ 수정 완료")
PYTHON_SCRIPT

echo "✅ Reports API 수정 완료"
echo ""
echo "다음 단계:"
echo "  cd .."
echo "  ./restart_backend.sh"
echo ""
