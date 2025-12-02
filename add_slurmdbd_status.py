#!/usr/bin/env python3
"""
Add slurmdbd status message to setup_cluster_full.sh
"""

with open('/home/koopark/claude/KooSlurmInstallAutomationRefactory/setup_cluster_full.sh', 'r') as f:
    lines = f.readlines()

# Find "다음 단계" section
for i, line in enumerate(lines):
    if '다음 단계' in line and 'echo' in line:
        # Insert slurmdbd status message after this line and the separator
        insert_pos = i + 3  # After "다음 단계", "====", and ""
        
        new_lines = [
            '\n',
            '# slurmdbd 설치 상태 표시\n',
            'if [ "${SLURMDBD_INSTALLED:-false}" = true ]; then\n',
            '    echo "✅ Slurm Accounting (slurmdbd) 설치됨"\n',
            '    echo "   - QoS 기능 사용 가능"\n',
            '    echo "   - Dashboard Apply Configuration 정상 작동"\n',
            '    echo "   - 그룹별 CPU 제한 및 우선순위 관리 가능"\n',
            '    echo ""\n',
            '    echo "   🧪 QoS 테스트:"\n',
            '    echo "      sacctmgr show qos"\n',
            '    echo "      sacctmgr show cluster"\n',
            '    echo ""\n',
            'else\n',
            '    echo "⚠️  Slurm Accounting (slurmdbd) 미설치"\n',
            '    echo "   - 기본 Slurm 기능은 정상 작동 ✅"\n',
            '    echo "   - QoS 기능 비활성화 (그룹별 CPU 제한 불가) ❌"\n',
            '    echo "   - Dashboard Apply Configuration 실패 예상 ❌"\n',
            '    echo ""\n',
            '    echo "   💡 나중에 QoS 기능을 사용하려면:"\n',
            '    echo "      ./install_slurm_accounting.sh"\n',
            '    echo ""\n',
            'fi\n',
            '\n',
        ]
        
        lines[insert_pos:insert_pos] = new_lines
        break

# Write back
with open('/home/koopark/claude/KooSlurmInstallAutomationRefactory/setup_cluster_full.sh', 'w') as f:
    f.writelines(lines)

print("✅ setup_cluster_full.sh updated with slurmdbd status message")
