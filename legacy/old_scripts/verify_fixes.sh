#!/bin/bash
# 전체 기능 점검 및 수정 검증 스크립트

echo "=================================================="
echo "KooSlurmInstallAutomation 수정사항 검증"
echo "=================================================="
echo ""

PROJECT_DIR="/home/koopark/claude/KooSlurmInstallAutomation"
cd "$PROJECT_DIR" || exit 1

# 색상 정의
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0
warn_count=0

# 테스트 함수
test_file_exists() {
    local file="$1"
    local desc="$2"
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $desc"
        ((pass_count++))
        return 0
    else
        echo -e "${RED}✗${NC} $desc"
        ((fail_count++))
        return 1
    fi
}

test_content_exists() {
    local file="$1"
    local pattern="$2"
    local desc="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $desc"
        ((pass_count++))
        return 0
    else
        echo -e "${RED}✗${NC} $desc"
        ((fail_count++))
        return 1
    fi
}

echo "1. 수정된 파일 존재 확인"
echo "-----------------------------------"
test_file_exists "src/config_parser.py" "config_parser.py 존재"
test_file_exists "examples/2node_example.yaml" "2node_example.yaml 존재"
test_file_exists "examples/4node_research_cluster.yaml" "4node_research_cluster.yaml 존재"
echo ""

echo "2. 신규 파일 존재 확인"
echo "-----------------------------------"
test_file_exists "examples/2node_example_fixed.yaml" "2node_example_fixed.yaml 생성"
test_file_exists "update_configs.sh" "update_configs.sh 생성"
test_file_exists "FIXES_REPORT.md" "FIXES_REPORT.md 생성"
test_file_exists "COMPREHENSIVE_FIXES_REPORT.md" "COMPREHENSIVE_FIXES_REPORT.md 생성"
test_file_exists "FINAL_FIXES_SUMMARY.md" "FINAL_FIXES_SUMMARY.md 생성"
echo ""

echo "3. config_parser.py 검증 로직 확인"
echo "-----------------------------------"
test_content_exists "src/config_parser.py" "_validate_installation" "installation 검증 메서드"
test_content_exists "src/config_parser.py" "_validate_time_sync" "time_sync 검증 메서드"
test_content_exists "src/config_parser.py" "recommended_sections" "권장 섹션 구분"
echo ""

echo "4. 2node_example.yaml 섹션 확인"
echo "-----------------------------------"
test_content_exists "examples/2node_example.yaml" "^installation:" "installation 섹션"
test_content_exists "examples/2node_example.yaml" "^time_synchronization:" "time_synchronization 섹션"
test_content_exists "examples/2node_example.yaml" "node_type:" "node_type 필드"
test_content_exists "examples/2node_example.yaml" "munge_user:" "munge_user 필드"
test_content_exists "examples/2node_example.yaml" "scheduler:" "scheduler 섹션"
echo ""

echo "5. 4node_research_cluster.yaml 섹션 확인"
echo "-----------------------------------"
test_content_exists "examples/4node_research_cluster.yaml" "^installation:" "installation 섹션"
test_content_exists "examples/4node_research_cluster.yaml" "^time_synchronization:" "time_synchronization 섹션"
test_content_exists "examples/4node_research_cluster.yaml" "node_type:" "node_type 필드"
test_content_exists "examples/4node_research_cluster.yaml" "munge_user:" "munge_user 필드"
echo ""

echo "6. 설정 파일 검증 테스트"
echo "-----------------------------------"

if [ -f "validate_config.py" ]; then
    # 2node_example.yaml 검증
    if python3 validate_config.py examples/2node_example.yaml --quiet 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 2node_example.yaml 검증 통과"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} 2node_example.yaml 검증 실패"
        ((fail_count++))
    fi
    
    # 4node_research_cluster.yaml 검증
    if python3 validate_config.py examples/4node_research_cluster.yaml --quiet 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 4node_research_cluster.yaml 검증 통과"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} 4node_research_cluster.yaml 검증 실패"
        ((fail_count++))
    fi
    
    # 2node_example_fixed.yaml 검증
    if python3 validate_config.py examples/2node_example_fixed.yaml --quiet 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 2node_example_fixed.yaml 검증 통과"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} 2node_example_fixed.yaml 검증 실패"
        ((fail_count++))
    fi
else
    echo -e "${YELLOW}⚠${NC} validate_config.py 없음 - 검증 건너뛰기"
    ((warn_count++))
fi
echo ""

echo "7. 스크립트 실행 권한 확인"
echo "-----------------------------------"
if [ -x "update_configs.sh" ]; then
    echo -e "${GREEN}✓${NC} update_configs.sh 실행 가능"
    ((pass_count++))
else
    echo -e "${YELLOW}⚠${NC} update_configs.sh 실행 권한 없음 (chmod +x 필요)"
    ((warn_count++))
fi
echo ""

echo "=================================================="
echo "검증 결과 요약"
echo "=================================================="
echo -e "${GREEN}통과:${NC} $pass_count"
echo -e "${RED}실패:${NC} $fail_count"
echo -e "${YELLOW}경고:${NC} $warn_count"
echo ""

total=$((pass_count + fail_count + warn_count))
if [ $total -gt 0 ]; then
    pass_rate=$((pass_count * 100 / total))
    echo "성공률: ${pass_rate}%"
fi
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✅ 모든 수정사항이 정상적으로 적용되었습니다!${NC}"
    echo ""
    echo "다음 단계:"
    echo "  1. 실행 권한 부여: chmod +x update_configs.sh"
    echo "  2. 문서 확인: cat FINAL_FIXES_SUMMARY.md"
    echo "  3. 설정 파일 사용: cp examples/2node_example.yaml my_cluster.yaml"
    exit 0
else
    echo -e "${RED}❌ 일부 항목이 실패했습니다. 위의 오류를 확인하세요.${NC}"
    exit 1
fi
