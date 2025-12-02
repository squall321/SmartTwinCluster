#!/bin/bash
################################################################################
# slurmctld 빠른 진단 - 일반적인 문제들 체크
################################################################################

echo "========================================"
echo "⚡ slurmctld 빠른 진단"
echo "========================================"
echo ""

ISSUES_FOUND=0

# 1. 노드 DNS/연결 확인
echo "1️⃣  노드 연결성 확인..."
echo "----------------------------------------"

NODES=("node001" "node002")
NODE_IPS=("192.168.122.90" "192.168.122.103")

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    ip="${NODE_IPS[$i]}"
    
    echo -n "  $node ($ip): "
    
    # ping 테스트
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        echo "✅ 연결됨"
    else
        echo "❌ 연결 실패"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    
    # SSH 테스트 (빠르게)
    echo -n "    SSH: "
    if timeout 3 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no koopark@"$ip" "echo ok" &>/dev/null; then
        echo "✅"
    else
        echo "❌ SSH 연결 실패"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done
echo ""

# 2. slurm.conf에 정의된 노드와 실제 노드 비교
echo "2️⃣  slurm.conf 노드 정의 확인..."
echo "----------------------------------------"

if [ -f /usr/local/slurm/etc/slurm.conf ]; then
    echo "NodeName 정의:"
    grep "^NodeName=" /usr/local/slurm/etc/slurm.conf
    echo ""
    echo "PartitionName 정의:"
    grep "^PartitionName=" /usr/local/slurm/etc/slurm.conf
    
    # 노드 이름이 일치하는지 확인
    if grep -q "^NodeName=node001" /usr/local/slurm/etc/slurm.conf && \
       grep -q "^NodeName=node002" /usr/local/slurm/etc/slurm.conf; then
        echo "✅ 노드 정의 확인"
    else
        echo "❌ 노드 정의 문제 발견"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    
    # 파티션 노드 이름 확인
    if grep -q "Nodes=node\[001-002\]" /usr/local/slurm/etc/slurm.conf; then
        echo "✅ 파티션 노드 이름 올바름"
    else
        echo "⚠️  파티션 노드 이름 확인 필요:"
        grep "PartitionName=normal" /usr/local/slurm/etc/slurm.conf
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    echo "❌ slurm.conf를 찾을 수 없습니다!"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# 3. 계산 노드에서 slurmd가 실행 중인지 확인
echo "3️⃣  계산 노드 slurmd 상태 확인..."
echo "----------------------------------------"

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    ip="${NODE_IPS[$i]}"
    
    echo -n "  $node: "
    
    if timeout 5 ssh -o ConnectTimeout=2 koopark@"$ip" "systemctl is-active slurmd" &>/dev/null; then
        echo "✅ slurmd 실행 중"
    else
        echo "❌ slurmd가 실행되지 않음"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        
        # 더 자세한 상태 확인
        echo "    상태:"
        timeout 5 ssh koopark@"$ip" "systemctl status slurmd --no-pager -l | head -10" 2>/dev/null | sed 's/^/    /'
    fi
done
echo ""

# 4. 컨트롤러-노드간 Munge 통신 확인
echo "4️⃣  Munge 인증 확인..."
echo "----------------------------------------"

if command -v munge &>/dev/null; then
    echo -n "  로컬 Munge 테스트: "
    if munge -n | unmunge &>/dev/null; then
        echo "✅"
    else
        echo "❌ 로컬 Munge 실패"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    
    # 각 노드와 Munge 통신 테스트
    for i in "${!NODES[@]}"; do
        node="${NODES[$i]}"
        ip="${NODE_IPS[$i]}"
        
        echo -n "  $node Munge 통신: "
        if timeout 5 ssh koopark@"$ip" "munge -n | unmunge" &>/dev/null; then
            echo "✅"
        else
            echo "❌ 실패"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    done
else
    echo "⚠️  munge 명령어를 찾을 수 없습니다"
fi
echo ""

# 5. 포트 충돌 확인
echo "5️⃣  포트 사용 확인..."
echo "----------------------------------------"

PORTS=(6817 6818 6819)
PORT_NAMES=("slurmctld" "slurmd" "slurmdbd")

for i in "${!PORTS[@]}"; do
    port="${PORTS[$i]}"
    name="${PORT_NAMES[$i]}"
    
    echo -n "  포트 $port ($name): "
    if netstat -tuln | grep -q ":$port "; then
        echo "🟡 사용 중"
        netstat -tuln | grep ":$port " | sed 's/^/    /'
    else
        if [ "$name" == "slurmctld" ]; then
            echo "⚠️  열려있지 않음 (slurmctld가 시작되지 않음)"
        else
            echo "✅ 사용 가능"
        fi
    fi
done
echo ""

# 6. 파일 권한 확인
echo "6️⃣  핵심 파일/디렉토리 권한..."
echo "----------------------------------------"

check_permission() {
    local path=$1
    local expected_owner=$2
    
    if [ -e "$path" ]; then
        actual_owner=$(stat -c '%U:%G' "$path" 2>/dev/null)
        echo -n "  $path: $actual_owner "
        if [ "$actual_owner" == "$expected_owner" ]; then
            echo "✅"
        else
            echo "❌ (예상: $expected_owner)"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        echo "  $path: ❌ 존재하지 않음"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
}

check_permission "/usr/local/slurm/etc/slurm.conf" "slurm:slurm"
check_permission "/var/spool/slurm/state" "slurm:slurm"
check_permission "/var/log/slurm" "slurm:slurm"
echo ""

# 7. 최근 에러 로그 확인
echo "7️⃣  최근 에러 로그..."
echo "----------------------------------------"

if [ -f /var/log/slurm/slurmctld.log ]; then
    echo "최근 에러/fatal 메시지:"
    sudo grep -E "error:|fatal:" /var/log/slurm/slurmctld.log | tail -5 | sed 's/^/  /'
else
    echo "  ⚠️  로그 파일이 없습니다"
fi

echo ""
echo "journalctl 최근 에러:"
journalctl -u slurmctld --no-pager -n 5 -p err | sed 's/^/  /'
echo ""

# 8. 결과 요약
echo "========================================"
echo "📊 진단 결과"
echo "========================================"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo "✅ 발견된 문제 없음"
    echo ""
    echo "💡 다음 시도:"
    echo "  1. ./debug_slurmctld_realtime.sh - 실시간 디버그"
    echo "  2. sudo journalctl -u slurmctld -f - 로그 모니터링"
else
    echo "⚠️  발견된 문제: $ISSUES_FOUND개"
    echo ""
    echo "🔧 해결 방법:"
    echo "  1. 위에 표시된 ❌ 항목들을 먼저 해결하세요"
    echo "  2. ./fix_slurmctld_critical.sh - 자동 수정"
    echo "  3. ./debug_slurmctld_realtime.sh - 상세 디버깅"
fi
echo ""
