#!/bin/bash
################################################################################
# 컴퓨트 노드 간 SSH 키 교차 배포 스크립트
# - mpirun 멀티노드 실행을 위해 모든 노드가 서로 SSH 접속 가능하도록 설정
# - 헤드노드에서 실행 (기존 헤드→컴퓨트 SSH 키 필요)
# - 접속 불가 노드는 스킵
#
# Usage:
#   sudo ./setup_ssh_compute_to_compute.sh [--config CONFIG_FILE]
#
# 다른 스크립트에서 함수로 호출:
#   source setup_ssh_compute_to_compute.sh
#   setup_cross_node_ssh "$CONFIG_FILE" "node001 node002 node003"
################################################################################

SSH_TIMEOUT=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

_log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
_log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
_log_fail() { echo -e "  ${RED}✗${NC} $1"; }
_log_info() { echo -e "  ${CYAN}→${NC} $1"; }

################################################################################
# 메인 함수: setup_cross_node_ssh
#   $1: CONFIG_FILE (YAML 경로)
#   $2: (선택) 대상 노드 목록 (공백 구분). 없으면 YAML에서 전체 추출
################################################################################
setup_cross_node_ssh() {
    local config_file="$1"
    local target_nodes_filter="$2"

    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        echo "❌ config 파일을 찾을 수 없습니다: $config_file"
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "🔑 컴퓨트 노드 간 SSH 키 교차 배포"
    echo "=========================================="
    echo "  config: $config_file"
    echo ""

    # ──────────────────────────────────────
    # 1. YAML에서 노드 목록 추출
    # ──────────────────────────────────────
    local NODES_INFO
    NODES_INFO=$(python3 << EOPY
import yaml, json, sys, socket

with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)

nodes_section = config.get('nodes', {})
ssh_password = config.get('cluster_info', {}).get('ssh_password', '')

nodes = []
seen = set()

# controllers
for n in nodes_section.get('controllers', []):
    if n.get('enabled', True) and n['hostname'] not in seen:
        seen.add(n['hostname'])
        nodes.append({
            'hostname': n['hostname'],
            'ip': n['ip_address'],
            'user': n.get('ssh_user', 'koopark')
        })

# compute_nodes
for n in nodes_section.get('compute_nodes', []):
    if n['hostname'] not in seen:
        seen.add(n['hostname'])
        nodes.append({
            'hostname': n['hostname'],
            'ip': n['ip_address'],
            'user': n.get('ssh_user', 'koopark')
        })

# viz_nodes
for n in nodes_section.get('viz_nodes', []):
    if n['hostname'] not in seen:
        seen.add(n['hostname'])
        nodes.append({
            'hostname': n['hostname'],
            'ip': n['ip_address'],
            'user': n.get('ssh_user', 'koopark')
        })

print(json.dumps({'ssh_password': ssh_password, 'nodes': nodes}))
EOPY
)

    if [[ -z "$NODES_INFO" ]]; then
        echo "❌ YAML 파싱 실패"
        return 1
    fi

    local SSH_PASSWORD
    SSH_PASSWORD=$(echo "$NODES_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['ssh_password'])" 2>/dev/null || echo "")
    local NODE_COUNT
    NODE_COUNT=$(echo "$NODES_INFO" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['nodes']))" 2>/dev/null || echo "0")
    local NODES_LIST
    NODES_LIST=$(echo "$NODES_INFO" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for n in d['nodes']:
    print(f\"{n['hostname']}|{n['ip']}|{n['user']}\")
" 2>/dev/null)

    echo "  대상 노드: ${NODE_COUNT}개"
    echo ""

    # SSH 명령 구성
    local SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes"
    local SCP_CMD="scp -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT"

    # 임시 디렉토리
    local TMP_DIR="/tmp/ssh_cross_deploy_$$"
    mkdir -p "$TMP_DIR"
    trap "rm -rf $TMP_DIR" EXIT

    # ──────────────────────────────────────
    # 2. 접속 가능한 노드 확인 + SSH 키 생성 + 공개키 수집
    # ──────────────────────────────────────
    echo "──────────────────────────────────────"
    echo "📡 Step 1: 각 노드 SSH 키 확인 및 공개키 수집"
    echo "──────────────────────────────────────"

    local REACHABLE_NODES=""
    local SKIPPED_NODES=""
    local ALL_PUBKEYS="$TMP_DIR/all_pubkeys.txt"
    > "$ALL_PUBKEYS"

    # 헤드노드 공개키도 포함
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        cat "$HOME/.ssh/id_rsa.pub" >> "$ALL_PUBKEYS"
        _log_ok "헤드노드 공개키 추가"
    fi

    while IFS='|' read -r hostname ip user; do
        [[ -z "$hostname" ]] && continue

        # 대상 노드 필터링
        if [[ -n "$target_nodes_filter" ]]; then
            if ! echo "$target_nodes_filter" | grep -qw "$hostname"; then
                continue
            fi
        fi

        echo ""
        echo "  📡 $hostname ($ip)"

        # SSH 접속 테스트
        if ! $SSH_CMD "$user@$ip" "echo ok" &>/dev/null; then
            _log_fail "접속 불가 — 스킵"
            SKIPPED_NODES="$SKIPPED_NODES $hostname"
            continue
        fi
        _log_ok "접속 성공"

        REACHABLE_NODES="$REACHABLE_NODES $hostname|$ip|$user"

        # SSH 키 존재 확인, 없으면 생성
        local HAS_KEY
        HAS_KEY=$($SSH_CMD "$user@$ip" "test -f ~/.ssh/id_rsa.pub && echo yes || echo no" 2>/dev/null)

        if [[ "$HAS_KEY" != "yes" ]]; then
            _log_info "SSH 키 생성 중..."
            $SSH_CMD "$user@$ip" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa -q" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                _log_ok "SSH 키 생성 완료"
            else
                _log_fail "SSH 키 생성 실패"
                continue
            fi
        else
            _log_ok "SSH 키 이미 존재"
        fi

        # 공개키 수집
        local PUBKEY
        PUBKEY=$($SSH_CMD "$user@$ip" "cat ~/.ssh/id_rsa.pub" 2>/dev/null)
        if [[ -n "$PUBKEY" ]]; then
            echo "$PUBKEY" >> "$ALL_PUBKEYS"
            _log_ok "공개키 수집 완료"
        else
            _log_fail "공개키 읽기 실패"
        fi

    done <<< "$NODES_LIST"

    # 중복 제거
    sort -u "$ALL_PUBKEYS" > "$TMP_DIR/all_pubkeys_unique.txt"
    mv "$TMP_DIR/all_pubkeys_unique.txt" "$ALL_PUBKEYS"

    local KEY_COUNT
    KEY_COUNT=$(wc -l < "$ALL_PUBKEYS")
    echo ""
    echo "  수집된 고유 공개키: ${KEY_COUNT}개"

    if [[ "$KEY_COUNT" -eq 0 ]]; then
        echo "❌ 수집된 공개키가 없습니다."
        return 1
    fi

    # ──────────────────────────────────────
    # 3. 모든 노드의 host key 수집 (known_hosts용)
    # ──────────────────────────────────────
    echo ""
    echo "──────────────────────────────────────"
    echo "🔍 Step 2: Host key 수집 (known_hosts)"
    echo "──────────────────────────────────────"

    local ALL_HOSTKEYS="$TMP_DIR/all_hostkeys.txt"
    > "$ALL_HOSTKEYS"

    while IFS='|' read -r hostname ip user; do
        [[ -z "$hostname" ]] && continue
        # hostname과 ip 모두 등록
        ssh-keyscan -H "$hostname" >> "$ALL_HOSTKEYS" 2>/dev/null || true
        ssh-keyscan -H "$ip" >> "$ALL_HOSTKEYS" 2>/dev/null || true
    done <<< "$NODES_LIST"

    # 중복 제거
    sort -u "$ALL_HOSTKEYS" > "$TMP_DIR/all_hostkeys_unique.txt"
    mv "$TMP_DIR/all_hostkeys_unique.txt" "$ALL_HOSTKEYS"

    local HOSTKEY_COUNT
    HOSTKEY_COUNT=$(wc -l < "$ALL_HOSTKEYS")
    _log_ok "Host key ${HOSTKEY_COUNT}개 수집 완료"

    # ──────────────────────────────────────
    # 4. 통합 authorized_keys + known_hosts 배포
    # ──────────────────────────────────────
    echo ""
    echo "──────────────────────────────────────"
    echo "📤 Step 3: 각 노드에 authorized_keys + known_hosts 배포"
    echo "──────────────────────────────────────"

    local DEPLOY_SUCCESS=0
    local DEPLOY_FAIL=0

    for node_entry in $REACHABLE_NODES; do
        IFS='|' read -r hostname ip user <<< "$node_entry"
        [[ -z "$hostname" ]] && continue

        echo ""
        echo "  📤 $hostname ($ip)"

        # authorized_keys 배포 (기존 키 보존 + 새 키 추가 + 중복 제거)
        local DEPLOY_OK=true

        # 기존 authorized_keys 가져오기
        local EXISTING_KEYS
        EXISTING_KEYS=$($SSH_CMD "$user@$ip" "cat ~/.ssh/authorized_keys 2>/dev/null" || echo "")

        # 기존 + 새 키 합쳐서 중복 제거 후 배포
        {
            echo "$EXISTING_KEYS"
            cat "$ALL_PUBKEYS"
        } | sort -u | grep -v '^$' > "$TMP_DIR/merged_authorized_keys.txt"

        # SCP로 전송 후 원격에서 설치
        $SCP_CMD "$TMP_DIR/merged_authorized_keys.txt" "$user@$ip:/tmp/new_authorized_keys_$$" &>/dev/null
        if [[ $? -eq 0 ]]; then
            $SSH_CMD "$user@$ip" "
                mkdir -p ~/.ssh && chmod 700 ~/.ssh
                mv /tmp/new_authorized_keys_$$ ~/.ssh/authorized_keys
                chmod 600 ~/.ssh/authorized_keys
            " 2>/dev/null
            if [[ $? -eq 0 ]]; then
                _log_ok "authorized_keys 배포 완료"
            else
                _log_fail "authorized_keys 설치 실패"
                DEPLOY_OK=false
            fi
        else
            _log_fail "authorized_keys 전송 실패"
            DEPLOY_OK=false
        fi

        # known_hosts 배포 (기존 + 새 host key 합쳐서 중복 제거)
        local EXISTING_HOSTKEYS
        EXISTING_HOSTKEYS=$($SSH_CMD "$user@$ip" "cat ~/.ssh/known_hosts 2>/dev/null" || echo "")

        {
            echo "$EXISTING_HOSTKEYS"
            cat "$ALL_HOSTKEYS"
        } | sort -u | grep -v '^$' > "$TMP_DIR/merged_known_hosts.txt"

        $SCP_CMD "$TMP_DIR/merged_known_hosts.txt" "$user@$ip:/tmp/new_known_hosts_$$" &>/dev/null
        if [[ $? -eq 0 ]]; then
            $SSH_CMD "$user@$ip" "
                mv /tmp/new_known_hosts_$$ ~/.ssh/known_hosts
                chmod 644 ~/.ssh/known_hosts
            " 2>/dev/null
            if [[ $? -eq 0 ]]; then
                _log_ok "known_hosts 배포 완료"
            else
                _log_fail "known_hosts 설치 실패"
                DEPLOY_OK=false
            fi
        else
            _log_fail "known_hosts 전송 실패"
            DEPLOY_OK=false
        fi

        if [[ "$DEPLOY_OK" == true ]]; then
            DEPLOY_SUCCESS=$((DEPLOY_SUCCESS + 1))
        else
            DEPLOY_FAIL=$((DEPLOY_FAIL + 1))
        fi
    done

    # ──────────────────────────────────────
    # 5. 접속 테스트 (샘플)
    # ──────────────────────────────────────
    echo ""
    echo "──────────────────────────────────────"
    echo "🧪 Step 4: 노드 간 접속 테스트"
    echo "──────────────────────────────────────"

    # 도달 가능한 노드 배열 생성
    local -a REACHABLE_ARRAY=()
    for node_entry in $REACHABLE_NODES; do
        REACHABLE_ARRAY+=("$node_entry")
    done

    local TEST_SUCCESS=0
    local TEST_FAIL=0
    local TOTAL_TESTS=0

    if [[ ${#REACHABLE_ARRAY[@]} -ge 2 ]]; then
        # 최대 5쌍 테스트 (첫 번째 → 나머지)
        local FIRST_ENTRY="${REACHABLE_ARRAY[0]}"
        IFS='|' read -r first_hostname first_ip first_user <<< "$FIRST_ENTRY"

        local TEST_COUNT=0
        for ((i=1; i<${#REACHABLE_ARRAY[@]} && TEST_COUNT<5; i++)); do
            local TARGET_ENTRY="${REACHABLE_ARRAY[$i]}"
            IFS='|' read -r target_hostname target_ip target_user <<< "$TARGET_ENTRY"

            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            echo -n "  $first_hostname → $target_hostname: "

            local TEST_RESULT
            TEST_RESULT=$($SSH_CMD "$first_user@$first_ip" "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $target_user@$target_ip 'hostname'" 2>/dev/null)

            if [[ -n "$TEST_RESULT" ]]; then
                echo -e "${GREEN}✓${NC} ($TEST_RESULT)"
                TEST_SUCCESS=$((TEST_SUCCESS + 1))
            else
                echo -e "${RED}✗${NC}"
                TEST_FAIL=$((TEST_FAIL + 1))
            fi
            TEST_COUNT=$((TEST_COUNT + 1))
        done

        # 역방향 테스트 (마지막 → 첫 번째)
        if [[ ${#REACHABLE_ARRAY[@]} -ge 2 ]]; then
            local LAST_ENTRY="${REACHABLE_ARRAY[-1]}"
            IFS='|' read -r last_hostname last_ip last_user <<< "$LAST_ENTRY"

            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            echo -n "  $last_hostname → $first_hostname: "

            local REVERSE_RESULT
            REVERSE_RESULT=$($SSH_CMD "$last_user@$last_ip" "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes $first_user@$first_ip 'hostname'" 2>/dev/null)

            if [[ -n "$REVERSE_RESULT" ]]; then
                echo -e "${GREEN}✓${NC} ($REVERSE_RESULT)"
                TEST_SUCCESS=$((TEST_SUCCESS + 1))
            else
                echo -e "${RED}✗${NC}"
                TEST_FAIL=$((TEST_FAIL + 1))
            fi
        fi
    else
        echo "  도달 가능한 노드가 2개 미만 — 테스트 생략"
    fi

    # ──────────────────────────────────────
    # 6. 결과 요약
    # ──────────────────────────────────────
    echo ""
    echo "=========================================="
    echo "  결과 요약"
    echo "=========================================="
    echo -e "  키 배포 성공: ${GREEN}${DEPLOY_SUCCESS}${NC}개 노드"
    [[ "$DEPLOY_FAIL" -gt 0 ]] && echo -e "  키 배포 실패: ${RED}${DEPLOY_FAIL}${NC}개 노드"
    [[ -n "$SKIPPED_NODES" ]] && echo -e "  스킵 (접속불가): ${YELLOW}${SKIPPED_NODES}${NC}"
    if [[ "$TOTAL_TESTS" -gt 0 ]]; then
        echo -e "  접속 테스트: ${GREEN}${TEST_SUCCESS}${NC}/${TOTAL_TESTS} 성공"
    fi
    echo ""

    if [[ "$DEPLOY_FAIL" -gt 0 ]] || [[ "$TEST_FAIL" -gt 0 ]]; then
        return 1
    fi
    return 0
}

################################################################################
# 독립 실행 모드 (source가 아닌 직접 실행 시)
################################################################################
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CONFIG_FILE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) CONFIG_FILE="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: $0 [--config CONFIG_FILE]"
                echo ""
                echo "컴퓨트 노드 간 SSH 키를 교차 배포합니다."
                echo "mpirun 멀티노드 실행을 위해 모든 노드가 서로 SSH 접속 가능하도록 설정합니다."
                echo ""
                echo "Options:"
                echo "  --config PATH    YAML 설정 파일 경로"
                echo "  --help, -h       도움말 표시"
                exit 0
                ;;
            *) shift ;;
        esac
    done

    # config 자동 탐색
    if [[ -z "$CONFIG_FILE" ]]; then
        for candidate in \
            "$SCRIPT_DIR/my_multihead_cluster_2.yaml" \
            "$SCRIPT_DIR/my_multihead_cluster.yaml" \
            "$SCRIPT_DIR/my_cluster.yaml" \
            "$SCRIPT_DIR/dev_cluster.yaml"; do
            if [[ -f "$candidate" ]]; then
                CONFIG_FILE="$candidate"
                break
            fi
        done
    fi

    if [[ -z "$CONFIG_FILE" ]]; then
        echo "❌ config 파일을 찾을 수 없습니다."
        echo "   Usage: $0 --config my_cluster.yaml"
        exit 1
    fi

    setup_cross_node_ssh "$CONFIG_FILE"
    exit $?
fi
