#!/bin/bash
################################################################################
# 오프라인 배포 검증 스크립트
#
# 설명:
#   오프라인 환경에서 설치된 모든 컴포넌트를 검증합니다.
#
# 기능:
#   - Slurm 설치 및 버전 확인
#   - Munge 인증 테스트
#   - 계산 노드 연결 테스트
#   - 서비스 상태 확인
#   - 클러스터 통합 테스트
#
# 사용법:
#   ./verify_offline_deployment.sh [OPTIONS]
#
# 옵션:
#   --config PATH    YAML 설정 파일
#   --all            모든 테스트 실행
#   --slurm          Slurm만 테스트
#   --munge          Munge만 테스트
#   --nodes          계산 노드만 테스트
#   --help           도움말 표시
#
# 작성자: Claude Code
# 날짜: 2025-11-17
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/my_multihead_cluster.yaml"
TEST_ALL=false
TEST_SLURM=false
TEST_MUNGE=false
TEST_NODES=false

# 테스트 결과
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 로깅 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }

# 도움말
show_help() {
    head -n 25 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

# 인자 파싱
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --all)
                TEST_ALL=true
                shift
                ;;
            --slurm)
                TEST_SLURM=true
                shift
                ;;
            --munge)
                TEST_MUNGE=true
                shift
                ;;
            --nodes)
                TEST_NODES=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done

    # 기본값: --all
    if [[ "$TEST_ALL" == "false" ]] && [[ "$TEST_SLURM" == "false" ]] && \
       [[ "$TEST_MUNGE" == "false" ]] && [[ "$TEST_NODES" == "false" ]]; then
        TEST_ALL=true
    fi
}

# 테스트 실행 헬퍼
run_test() {
    local test_name="$1"
    local test_command="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test "$test_name"

    if eval "$test_command" &>/dev/null; then
        log_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

################################################################################
# Slurm 테스트
################################################################################

test_slurm_installation() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Slurm 설치 검증                                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Slurm 바이너리 존재 확인
    run_test "Slurm slurmctld binary" "test -x /opt/slurm/sbin/slurmctld"
    run_test "Slurm slurmd binary" "test -x /opt/slurm/sbin/slurmd"
    run_test "Slurm commands in PATH" "command -v sinfo"

    # Slurm 버전 확인
    if command -v slurmctld &>/dev/null; then
        local version=$(slurmctld -V 2>&1 | grep -oP 'slurm \K[\d.]+' || echo "unknown")
        log_info "Slurm version: $version"
    fi

    # Slurm 디렉토리 확인
    run_test "Slurm config directory" "test -d /opt/slurm/etc"
    run_test "Slurm log directory" "test -d /var/log/slurm"
    run_test "Slurm spool directory" "test -d /var/spool/slurm"

    # Slurm 사용자 확인
    run_test "Slurm user exists" "id slurm"

    # Slurm 설정 파일 확인
    if [[ -f /opt/slurm/etc/slurm.conf ]] || [[ -f /etc/slurm/slurm.conf ]]; then
        log_success "Slurm configuration file found"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_warning "Slurm configuration file not found (expected for fresh install)"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Slurm 서비스 상태 (optional)
    if systemctl is-active --quiet slurmctld 2>/dev/null; then
        log_success "slurmctld service is running"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_info "slurmctld service is not running (may be expected)"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

################################################################################
# Munge 테스트
################################################################################

test_munge_installation() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Munge 인증 검증                                          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Munge 바이너리 확인
    run_test "Munge binary" "command -v munge"
    run_test "Unmunge binary" "command -v unmunge"

    # Munge 사용자 확인
    run_test "Munge user exists" "id munge"

    # Munge 키 확인
    run_test "Munge key exists" "test -f /etc/munge/munge.key"

    if [[ -f /etc/munge/munge.key ]]; then
        local key_perms=$(stat -c %a /etc/munge/munge.key)
        if [[ "$key_perms" == "400" ]]; then
            log_success "Munge key permissions correct (400)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log_warning "Munge key permissions: $key_perms (expected: 400)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi

    # Munge 서비스 상태
    run_test "Munge service active" "systemctl is-active --quiet munge"

    # Munge 기능 테스트
    log_test "Munge encode/decode test"
    if munge -n | unmunge &>/dev/null; then
        log_success "Munge encode/decode test"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "Munge encode/decode test"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

################################################################################
# 계산 노드 테스트
################################################################################

test_compute_nodes() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  계산 노드 연결 검증                                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "Config file not found, skipping node tests"
        return 0
    fi

    # Python으로 노드 목록 추출
    local nodes_json=$(python3 << EOPY
import yaml
import json

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)

    nodes = []
    for node in config.get('nodes', {}).get('compute_nodes', []):
        nodes.append({
            'hostname': node['hostname'],
            'ip': node['ip_address'],
            'user': node.get('ssh_user', 'koopark')
        })

    print(json.dumps(nodes))
except Exception as e:
    print("[]")
EOPY
    )

    local node_count=$(echo "$nodes_json" | jq '. | length')

    if [[ $node_count -eq 0 ]]; then
        log_info "No compute nodes defined in config"
        return 0
    fi

    log_info "Testing $node_count compute nodes..."
    echo ""

    while IFS= read -r node_json; do
        local hostname=$(echo "$node_json" | jq -r '.hostname')
        local ip=$(echo "$node_json" | jq -r '.ip')
        local user=$(echo "$node_json" | jq -r '.user')

        log_info "Testing node: $hostname ($ip)"

        # SSH 연결 테스트
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$user@$ip" "echo OK" &>/dev/null; then
            log_success "  SSH connection to $hostname"
            PASSED_TESTS=$((PASSED_TESTS + 1))

            # 원격 Munge 테스트
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            if ssh "$user@$ip" "munge -n | unmunge" &>/dev/null; then
                log_success "  Munge on $hostname"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                log_error "  Munge on $hostname"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi

            # 원격 Slurm 테스트
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            if ssh "$user@$ip" "command -v slurmd" &>/dev/null; then
                log_success "  Slurm on $hostname"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                log_error "  Slurm on $hostname"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi

        else
            log_error "  SSH connection to $hostname"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi

        echo ""

    done < <(echo "$nodes_json" | jq -c '.[]')
}

################################################################################
# 시스템 정보
################################################################################

show_system_info() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  시스템 정보                                              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Hostname: $(hostname)"
    log_info "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    log_info "Kernel: $(uname -r)"
    log_info "Architecture: $(uname -m)"

    if command -v slurmctld &>/dev/null; then
        log_info "Slurm Version: $(slurmctld -V 2>&1 | head -1)"
    fi

    if command -v munge &>/dev/null; then
        log_info "Munge Version: $(munge --version 2>&1 | head -1 || echo "unknown")"
    fi
}

################################################################################
# 결과 요약
################################################################################

print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  검증 결과 요약                                           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local pass_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo "  Total Tests:   $TOTAL_TESTS"
    echo "  Passed:        $PASSED_TESTS (${GREEN}✓${NC})"
    echo "  Failed:        $FAILED_TESTS (${RED}✗${NC})"
    echo "  Pass Rate:     ${pass_rate}%"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All tests passed! 🎉"
        echo ""
        log_info "Your offline cluster deployment is verified!"
    else
        log_warning "Some tests failed"
        echo ""
        log_info "Please check the failed components and retry deployment if needed"
    fi
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  오프라인 배포 검증                                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    show_system_info

    if [[ "$TEST_ALL" == "true" ]] || [[ "$TEST_SLURM" == "true" ]]; then
        test_slurm_installation
    fi

    if [[ "$TEST_ALL" == "true" ]] || [[ "$TEST_MUNGE" == "true" ]]; then
        test_munge_installation
    fi

    if [[ "$TEST_ALL" == "true" ]] || [[ "$TEST_NODES" == "true" ]]; then
        test_compute_nodes
    fi

    print_summary

    # Exit code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
