#!/bin/bash
# 간단한 테스트 스크립트

echo "=== 테스트 1: Python 스크립트 임포트 테스트 ==="
python3 -c "
import sys
sys.path.insert(0, 'offline_packages')
import precheck_packages
print('✅ 임포트 성공')
"

echo ""
echo "=== 테스트 2: 필수 인자 없이 실행 (에러 처리 테스트) ==="
python3 offline_packages/precheck_packages.py 2>&1 | head -5

echo ""
echo "=== 테스트 3: Help 출력 테스트 ==="
python3 offline_packages/precheck_packages.py --help | head -10

echo ""
echo "=== 테스트 4: Bash 스크립트 dry-run 테스트 ==="
if [ -d "offline_packages/apt_packages" ]; then
    bash install_offline_packages_smart.sh \
        --deb-dir offline_packages/apt_packages \
        --dry-run 2>&1 | tail -10
else
    echo "⚠️  offline_packages/apt_packages 디렉토리 없음 (실제 환경에서 테스트 필요)"
fi

