#!/bin/bash
# 공통 SSH 헬퍼: node ssh_user의 키 자동 탐색 + sshpass fallback
# 사용:
#   source cluster/utils/ssh_helpers.sh
#   setup_node_ssh_opts "$ssh_user" "$ip"      # SSH_OPTS/SCP_OPTS 전역 오버라이드
#
# 전제 환경변수:
#   CONFIG_FILE     — YAML 경로 (sshpass용 비밀번호 추출)
#   SSH_KEY_FILE    — 기본 키 (선택, ORIGINAL_HOME의 id_rsa)
#   _SSH_BASE_OPTS  — 공통 ssh 옵션 (없으면 자동 설정)

[[ -z "${_SSH_BASE_OPTS:-}" ]] && _SSH_BASE_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3"

setup_node_ssh_opts() {
    local user="$1" ip="$2"
    local user_home
    user_home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || echo "")
    local _k
    for _k in "${user_home}/.ssh/id_ed25519" "${user_home}/.ssh/id_rsa" "${SSH_KEY_FILE:-}" "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa"; do
        [[ -z "$_k" || ! -f "$_k" ]] && continue
        if ssh -n -i "$_k" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
               "$user@$ip" "exit" &>/dev/null; then
            SSH_OPTS="-n -i $_k -o BatchMode=yes $_SSH_BASE_OPTS"
            SCP_OPTS="-i $_k -o BatchMode=yes $_SSH_BASE_OPTS"
            return 0
        fi
    done
    # sshpass fallback
    local _pass=""
    if [[ -n "${CONFIG_FILE:-}" && -f "$CONFIG_FILE" ]]; then
        _pass=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('cluster_info',{}).get('ssh_password',''))" 2>/dev/null || echo "")
    fi
    if [[ -n "$_pass" ]] && command -v sshpass &>/dev/null; then
        if SSHPASS="$_pass" sshpass -e ssh -n -o BatchMode=no -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no "$user@$ip" "exit" &>/dev/null; then
            export SSHPASS="$_pass"
            SSH_OPTS="-n -o BatchMode=no $_SSH_BASE_OPTS"
            SCP_OPTS="-o BatchMode=no $_SSH_BASE_OPTS"
            # 호출부에서 sshpass -e ssh / sshpass -e scp 로 감싸 사용
            return 0
        fi
    fi
    return 1
}
