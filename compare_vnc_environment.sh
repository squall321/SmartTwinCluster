#!/bin/bash
# VNC 환경 비교 스크립트 - 이 서버에서 실행하여 오프라인 서버와 비교할 정보 수집

echo "=========================================="
echo "VNC 환경 정보 수집 (이 서버)"
echo "=========================================="
echo ""
echo "이 정보를 오프라인 서버와 비교하세요"
echo ""

# 1. Slurm 파티션 설정
echo "=== 1. Slurm 파티션 설정 ==="
echo "viz 파티션:"
grep "^PartitionName=viz" /etc/slurm/slurm.conf 2>/dev/null || echo "  ✗ viz 파티션 설정 없음"
echo ""

# 2. viz 노드 설정
echo "=== 2. viz 노드 Slurm 설정 ==="
grep "^NodeName=viz" /etc/slurm/slurm.conf | head -3 2>/dev/null || echo "  ✗ viz 노드 설정 없음"
echo ""

# 3. gres.conf 설정
echo "=== 3. gres.conf 설정 ==="
if [[ -f /etc/slurm/gres.conf ]]; then
    echo "파일 존재: /etc/slurm/gres.conf"
    echo "내용:"
    cat /etc/slurm/gres.conf
else
    echo "  ✗ /etc/slurm/gres.conf 파일 없음"
fi
echo ""

# 4. viz 노드 상태
echo "=== 4. viz 노드 상태 ==="
timeout 5 sinfo -p viz -o "%P|%a|%l|%D|%T|%N|%G" 2>/dev/null || echo "  sinfo 실패 또는 timeout"
echo ""

# 5. GlusterFS 마운트
echo "=== 5. GlusterFS 마운트 ==="
mount | grep gluster || echo "  ✗ GlusterFS 마운트 없음"
echo ""

# 6. 로그 디렉토리 상태
echo "=== 6. 로그 디렉토리 ==="
for dir in "/mnt/gluster/logs" "/shared/logs"; do
    if [[ -e "$dir" ]]; then
        echo "$dir:"
        ls -ld "$dir"
        if [[ -L "$dir" ]]; then
            echo "  → 심볼릭 링크: $(readlink -f "$dir")"
        fi
    else
        echo "$dir: 없음"
    fi
done
echo ""

# 7. VNC 백엔드 설정
echo "=== 7. VNC 백엔드 로그 경로 설정 ==="
if [[ -f dashboard/backend_5010/vnc_api.py ]]; then
    echo "VNC_LOG_DIR 설정:"
    grep "^VNC_LOG_DIR" dashboard/backend_5010/vnc_api.py || echo "  설정 없음"
else
    echo "  vnc_api.py 파일 없음"
fi
echo ""

# 8. 최근 성공한 VNC Job 확인
echo "=== 8. 최근 성공한 VNC Job (이 서버) ==="
COMPLETED_JOBS=$(sacct -S now-7days -n -o JobID,JobName,State,NodeList -P 2>/dev/null | grep "vnc-" | grep "COMPLETED" | head -5 ||
                 /usr/local/slurm/bin/sacct -S now-7days -n -o JobID,JobName,State,NodeList -P 2>/dev/null | grep "vnc-" | grep "COMPLETED" | head -5)

if [[ -n "$COMPLETED_JOBS" ]]; then
    echo "최근 성공한 VNC Job들:"
    echo "Job ID | Job Name | State | NodeList"
    echo "$COMPLETED_JOBS"
    echo ""

    # 첫 번째 성공 Job의 스크립트 찾기
    FIRST_JOB_ID=$(echo "$COMPLETED_JOBS" | head -1 | cut -d'|' -f1)
    SCRIPT_FILE=$(find /tmp -name "vnc_job_*${FIRST_JOB_ID}*.sh" -o -name "vnc_job_*.sh" 2>/dev/null | head -1)

    if [[ -n "$SCRIPT_FILE" ]]; then
        echo "Job 스크립트 예시: $SCRIPT_FILE"
        echo "SBATCH 옵션:"
        grep "^#SBATCH" "$SCRIPT_FILE" | head -15
    fi
else
    echo "  최근 7일간 성공한 VNC job 없음"
fi
echo ""

# 9. slurmdbd 및 accounting 설정
echo "=== 9. Slurm Accounting 설정 ==="
echo "AccountingStorageType:"
grep "^AccountingStorageType" /etc/slurm/slurm.conf 2>/dev/null || echo "  설정 없음"
echo ""
echo "slurmdbd 서비스:"
systemctl is-active slurmdbd 2>/dev/null || echo "  slurmdbd 서비스 없음 또는 inactive"
echo ""

# 10. 서비스 상태
echo "=== 10. 관련 서비스 상태 ==="
echo "slurmctld:"
systemctl is-active slurmctld 2>/dev/null || echo "  inactive"
echo "slurmdbd:"
systemctl is-active slurmdbd 2>/dev/null || echo "  inactive"
echo "mariadb:"
systemctl is-active mariadb 2>/dev/null || echo "  inactive"
echo "dashboard_backend (vnc_api):"
systemctl is-active dashboard_backend 2>/dev/null || echo "  inactive"
echo ""

# 11. YAML 설정 비교
echo "=== 11. YAML viz 노드 설정 ==="
if [[ -f my_multihead_cluster_2.yaml ]]; then
    echo "viz_nodes 섹션:"
    python3 << 'EOPY'
import yaml
try:
    with open('my_multihead_cluster_2.yaml', 'r') as f:
        config = yaml.safe_load(f)
    viz_nodes = config.get('nodes', {}).get('viz_nodes', [])
    for node in viz_nodes:
        print(f"  - hostname: {node.get('hostname')}")
        print(f"    ip: {node.get('ip_address')}")
        hardware = node.get('hardware', {})
        print(f"    gpus: {hardware.get('gpus', 0)}")
        print(f"    gpu_type: {hardware.get('gpu_type', 'N/A')}")
        print()
except Exception as e:
    print(f"  ERROR: {e}")
EOPY
else
    echo "  my_multihead_cluster_2.yaml 파일 없음"
fi
echo ""

echo "=========================================="
echo "오프라인 서버에서 동일한 항목 확인:"
echo "=========================================="
echo ""
echo "1. viz 파티션 설정:"
echo "   grep '^PartitionName=viz' /etc/slurm/slurm.conf"
echo ""
echo "2. gres.conf 존재 여부:"
echo "   ls -la /etc/slurm/gres.conf"
echo "   cat /etc/slurm/gres.conf"
echo ""
echo "3. viz 노드 상태:"
echo "   sinfo -p viz"
echo ""
echo "4. 로그 디렉토리:"
echo "   ls -la /mnt/gluster/logs"
echo "   ls -la /shared/logs"
echo ""
echo "5. slurmdbd 서비스:"
echo "   systemctl status slurmdbd"
echo ""
echo "6. 최근 Job 실패 로그:"
echo "   sudo tail -100 /var/log/slurm/slurmctld.log | grep -i 'job 2'"
echo ""
