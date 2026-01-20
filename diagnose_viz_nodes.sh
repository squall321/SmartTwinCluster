#!/bin/bash
# viz 노드 연결 및 slurmd 상태 진단 스크립트

echo "=========================================="
echo "viz 노드 연결 및 slurmd 상태 진단"
echo "=========================================="
echo ""

# 1. viz 파티션 노드 목록
echo "=== 1. viz 파티션 설정 ==="
VIZ_PARTITION=$(grep "^PartitionName=viz" /etc/slurm/slurm.conf 2>/dev/null)
if [[ -n "$VIZ_PARTITION" ]]; then
    echo "$VIZ_PARTITION"

    VIZ_NODES=$(echo "$VIZ_PARTITION" | grep -o "Nodes=[^ ]*" | sed 's/Nodes=//')
    echo ""
    echo "viz 노드: $VIZ_NODES"
else
    echo "  ✗ viz 파티션 설정이 없습니다!"
    exit 1
fi
echo ""

# 2. 노드 범위 확장
echo "=== 2. viz 노드 목록 확장 ==="
if [[ "$VIZ_NODES" =~ \[ ]]; then
    EXPANDED_NODES=$(scontrol show hostnames "$VIZ_NODES" 2>/dev/null || /usr/local/slurm/bin/scontrol show hostnames "$VIZ_NODES" 2>/dev/null)
else
    EXPANDED_NODES="$VIZ_NODES"
fi

if [[ -z "$EXPANDED_NODES" ]]; then
    echo "  ✗ 노드 목록 확장 실패"
    exit 1
fi

echo "확장된 노드 목록:"
for node in $EXPANDED_NODES; do
    echo "  - $node"
done
echo ""

# 3. 각 viz 노드 상태 확인
echo "=== 3. 각 viz 노드 상태 ==="
for node in $EXPANDED_NODES; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Node: $node"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Slurm 노드 상태
    echo "[Slurm 상태]"
    NODE_INFO=$(scontrol show node "$node" 2>/dev/null | head -3 || /usr/local/slurm/bin/scontrol show node "$node" 2>/dev/null | head -3)
    if [[ -n "$NODE_INFO" ]]; then
        echo "$NODE_INFO" | grep "State="
    else
        echo "  ✗ scontrol로 노드 정보를 가져올 수 없습니다"
    fi
    echo ""

    # Ping 테스트
    echo "[네트워크]"
    if timeout 3 ping -c 1 -W 2 "$node" &>/dev/null; then
        echo "  ✓ Ping 성공"
        PING_OK=1
    else
        echo "  ✗ Ping 실패 - 네트워크 연결 없음"
        PING_OK=0
    fi
    echo ""

    if [[ $PING_OK -eq 1 ]]; then
        # SSH 접속 테스트
        echo "[SSH 접속]"
        if timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" "echo SSH OK" &>/dev/null; then
            echo "  ✓ SSH 접속 가능"

            # hostname 확인
            REMOTE_HOSTNAME=$(timeout 5 ssh -o ConnectTimeout=5 "$node" "hostname" 2>/dev/null)
            echo "  Hostname: $REMOTE_HOSTNAME"
            echo ""

            # slurmd 설치 확인
            echo "[slurmd 설치]"
            SLURMD_PATH=$(timeout 5 ssh -o ConnectTimeout=5 "$node" "which slurmd" 2>/dev/null)
            if [[ -n "$SLURMD_PATH" ]]; then
                echo "  ✓ slurmd 설치됨: $SLURMD_PATH"
            else
                echo "  ✗ slurmd가 설치되지 않음"
            fi
            echo ""

            # slurmd 서비스 상태
            echo "[slurmd 서비스]"
            SLURMD_STATUS=$(timeout 5 ssh -o ConnectTimeout=5 "$node" "systemctl is-active slurmd 2>/dev/null || echo inactive" 2>/dev/null)
            if [[ "$SLURMD_STATUS" == "active" ]]; then
                echo "  ✓ slurmd 서비스: active"
            else
                echo "  ✗ slurmd 서비스: $SLURMD_STATUS"
            fi

            # 서비스 상세 상태
            timeout 5 ssh -o ConnectTimeout=5 "$node" "systemctl status slurmd --no-pager | head -10" 2>/dev/null | sed 's/^/  /'
            echo ""

            # slurmd 프로세스
            echo "[slurmd 프로세스]"
            SLURMD_PROC=$(timeout 5 ssh -o ConnectTimeout=5 "$node" "pgrep -a slurmd" 2>/dev/null)
            if [[ -n "$SLURMD_PROC" ]]; then
                echo "  ✓ 실행 중:"
                echo "$SLURMD_PROC" | sed 's/^/    /'
            else
                echo "  ✗ slurmd 프로세스 없음"
            fi
            echo ""

            # slurmd 로그 (최근 에러)
            echo "[slurmd 로그 (최근 에러)]"
            SLURMD_LOG=$(timeout 5 ssh -o ConnectTimeout=5 "$node" "sudo tail -30 /var/log/slurm/slurmd.log 2>/dev/null | grep -i error" 2>/dev/null)
            if [[ -n "$SLURMD_LOG" ]]; then
                echo "$SLURMD_LOG" | head -5 | sed 's/^/  /'
            else
                echo "  최근 에러 없음 (또는 로그 파일 없음)"
            fi

        else
            echo "  ✗ SSH 접속 실패"
            echo "    - SSH 키 설정 확인 필요"
            echo "    - StrictHostKeyChecking 설정 확인"
        fi
    fi

    echo ""
done

echo "=========================================="
echo "진단 결과 요약"
echo "=========================================="
echo ""

# 요약
ALL_OK=1
for node in $EXPANDED_NODES; do
    if ! timeout 3 ping -c 1 -W 2 "$node" &>/dev/null; then
        echo "✗ $node: 네트워크 연결 없음"
        ALL_OK=0
    elif ! timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" "systemctl is-active slurmd" &>/dev/null | grep -q "active"; then
        echo "✗ $node: slurmd 서비스 실행 안 됨"
        ALL_OK=0
    else
        echo "✓ $node: 정상"
    fi
done
echo ""

if [[ $ALL_OK -eq 0 ]]; then
    echo "=========================================="
    echo "해결 방법"
    echo "=========================================="
    echo ""
    echo "1. viz 노드에 slurm 배포:"
    echo "   ./offline_deploy/deploy_to_compute_node.sh"
    echo ""
    echo "2. slurmd 서비스 시작 (각 viz 노드에서):"
    for node in $EXPANDED_NODES; do
        echo "   ssh $node 'sudo systemctl start slurmd'"
        echo "   ssh $node 'sudo systemctl enable slurmd'"
    done
    echo ""
    echo "3. 노드 상태 복구 (헤드노드에서):"
    for node in $EXPANDED_NODES; do
        echo "   sudo scontrol update nodename=$node state=resume"
    done
    echo ""
    echo "4. SSH 키 설정 (필요시):"
    for node in $EXPANDED_NODES; do
        echo "   ssh-copy-id $node"
    done
    echo ""
else
    echo "모든 viz 노드가 정상입니다!"
fi
