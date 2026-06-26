#!/bin/bash
# reboot API 권한 문제 해결 스크립트

echo "================================================================================"
echo "🔧 Reboot API Permission 문제 해결"
echo "================================================================================"
echo ""
echo "문제: scontrol reboot 명령어가 Permission denied 에러 발생"
echo "해결: sudo 권한 추가 + sudoers 설정"
echo ""

# 1. sudoers 설정 확인
echo "📋 Step 1/4: 현재 사용자 및 권한 확인"
echo "--------------------------------------------------------------------------------"
CURRENT_USER=$(whoami)
echo "현재 사용자: $CURRENT_USER"

# scontrol 경로 확인
SCONTROL_PATH=$(which scontrol 2>/dev/null || echo "/usr/local/slurm/bin/scontrol")
echo "scontrol 경로: $SCONTROL_PATH"

# sudo 테스트
if sudo -n $SCONTROL_PATH show config >/dev/null 2>&1; then
    echo "✅ sudo scontrol 실행 가능 (비밀번호 없이)"
else
    echo "❌ sudo scontrol 실행 불가 (비밀번호 필요 또는 권한 없음)"
fi
echo ""

# 2. sudoers 설정 추가
echo "🔧 Step 2/4: sudoers 설정 추가"
echo "--------------------------------------------------------------------------------"
SUDOERS_FILE="/etc/sudoers.d/slurm-dashboard"

echo "다음 명령어를 실행하여 sudoers 설정을 추가하세요:"
echo ""
echo "sudo tee $SUDOERS_FILE <<EOF"
echo "# Slurm Dashboard - Node Management"
echo "# Allow $CURRENT_USER to run scontrol commands without password"
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH"
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH *"
echo "EOF"
echo ""
echo "sudo chmod 0440 $SUDOERS_FILE"
echo "sudo visudo -c  # 설정 검증"
echo ""

read -p "위 명령어를 실행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "sudoers 설정 중..."
    sudo tee $SUDOERS_FILE > /dev/null <<EOF
# Slurm Dashboard - Node Management
# Allow $CURRENT_USER to run scontrol commands without password
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH *
EOF
    sudo chmod 0440 $SUDOERS_FILE
    echo "✅ sudoers 설정 완료"
    
    # 검증
    if sudo visudo -c; then
        echo "✅ sudoers 설정 검증 성공"
    else
        echo "❌ sudoers 설정 검증 실패"
        echo "   수동으로 확인하세요: sudo visudo -c"
        exit 1
    fi
else
    echo "⚠️  sudoers 설정을 건너뜁니다"
    echo "   수동으로 설정하거나 다음 단계를 진행하세요"
fi
echo ""

# 3. API 코드 수정
echo "🔄 Step 3/4: API 코드에 sudo 추가"
echo "--------------------------------------------------------------------------------"

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 백업
if [ ! -f "node_management_api.py.perm_backup" ]; then
    cp node_management_api.py node_management_api.py.perm_backup
    echo "✅ 백업 생성: node_management_api.py.perm_backup"
fi

# run_slurm_command 함수 수정
cat > temp_fix.py <<'EOF'
def run_slurm_command(command, mock_response=None, use_sudo=False):
    """
    Slurm 명령어 실행 (Mock 모드 지원)
    
    Args:
        command: 실행할 명령어 리스트
        mock_response: Mock 모드에서 반환할 응답
        use_sudo: sudo 권한으로 실행 여부
    """
    if MOCK_MODE and mock_response is not None:
        logger.info(f"🎭 Mock mode: {' '.join(command)}")
        return True, mock_response, ""
    
    try:
        # sudo 권한이 필요한 경우
        if use_sudo:
            command = ['sudo'] + command
            logger.info(f"Running with sudo: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timeout"
    except Exception as e:
        return False, "", str(e)
EOF

echo "✅ run_slurm_command 함수에 sudo 옵션 추가"
echo ""

# reboot_node 함수의 scontrol 호출 수정
echo "수정 내용:"
echo "  - run_slurm_command에 use_sudo=True 추가"
echo "  - scontrol reboot 명령어를 sudo로 실행"
echo ""

# 4. 완성된 파일 생성
cat > node_management_api_sudo.py <<'FULL_FILE'
"""
노드 관리 API (Flask 버전) - Sudo 권한 추가
- 중복 노드 제거
- Reboot API에 sudo 권한 추가
"""
from flask import Blueprint, request, jsonify
import subprocess
from datetime import datetime
import logging
import os

# 로거 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Blueprint 생성 (url_prefix 추가)
node_bp = Blueprint('node_management', __name__, url_prefix='/api')

# Mock 모드 확인
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'

# 데이터베이스 (간단한 인메모리 저장소, 추후 SQLite로 확장)
node_history = []


def run_slurm_command(command, mock_response=None, use_sudo=False):
    """
    Slurm 명령어 실행 (Mock 모드 지원)
    
    Args:
        command: 실행할 명령어 리스트
        mock_response: Mock 모드에서 반환할 응답
        use_sudo: sudo 권한으로 실행 여부
    """
    if MOCK_MODE and mock_response is not None:
        logger.info(f"🎭 Mock mode: {' '.join(command)}")
        return True, mock_response, ""
    
    try:
        # sudo 권한이 필요한 경우
        if use_sudo:
            command = ['sudo'] + command
            logger.info(f"Running with sudo: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timeout"
    except Exception as e:
        return False, "", str(e)


@node_bp.route('/nodes', methods=['GET'])
def get_nodes():
    """
    모든 노드 목록 및 상태 조회
    GET /api/nodes
    
    🔧 FIX: 중복 노드 제거 로직 추가
    """
    try:
        if MOCK_MODE:
            # Mock 데이터
            nodes = [
                {
                    'name': 'cn01',
                    'state': 'IDLE',
                    'cpus': '64/0/0/64',
                    'memory': '256000',
                    'free_memory': '200000',
                    'cpu_load': '0.50',
                    'time_limit': 'infinite',
                    'nodes': '1'
                },
                {
                    'name': 'cn02',
                    'state': 'ALLOCATED',
                    'cpus': '64/48/0/64',
                    'memory': '256000',
                    'free_memory': '100000',
                    'cpu_load': '12.30',
                    'time_limit': 'infinite',
                    'nodes': '1'
                },
                {
                    'name': 'cn03',
                    'state': 'DRAINED',
                    'cpus': '64/0/0/64',
                    'memory': '256000',
                    'free_memory': '250000',
                    'cpu_load': '0.00',
                    'time_limit': 'infinite',
                    'nodes': '1'
                }
            ]
            actual_mode = 'mock'
        else:
            # 실제 Slurm 명령어 실행
            success, stdout, stderr = run_slurm_command(
                ['sinfo', '-N', '-o', '%N|%T|%C|%m|%e|%O|%l|%D']
            )
            
            if not success:
                # Slurm 명령어 실패 시 Mock 데이터로 Fallback
                logger.warning(f"Slurm command failed: {stderr}. Falling back to mock data.")
                nodes = [
                    {'name': 'node01', 'state': 'IDLE', 'cpus': '32/0/0/32', 'memory': '128000', 'free_memory': '120000', 'cpu_load': '0.50', 'time_limit': 'infinite', 'nodes': '1'},
                    {'name': 'node02', 'state': 'ALLOCATED', 'cpus': '32/16/0/32', 'memory': '128000', 'free_memory': '64000', 'cpu_load': '5.20', 'time_limit': 'infinite', 'nodes': '1'}
                ]
                actual_mode = 'mock'
            else:
                # 결과 파싱
                lines = stdout.strip().split('\n')
                nodes_dict = {}  # 🔧 FIX: 중복 제거를 위한 딕셔너리 사용
                
                for line in lines[1:]:  # 헤더 스킵
                    parts = line.split('|')
                    if len(parts) >= 8:
                        node_name = parts[0]
                        # 🔧 FIX: 같은 이름의 노드가 있으면 덮어쓰기 (최신 상태 유지)
                        nodes_dict[node_name] = {
                            'name': node_name,
                            'state': parts[1],
                            'cpus': parts[2],
                            'memory': parts[3],
                            'free_memory': parts[4],
                            'cpu_load': parts[5],
                            'time_limit': parts[6],
                            'nodes': parts[7]
                        }
                
                # 딕셔너리를 리스트로 변환
                nodes = list(nodes_dict.values())
                logger.info(f"Parsed {len(nodes)} unique nodes")
                actual_mode = 'production'
        
        return jsonify({
            'success': True,
            'nodes': nodes,
            'count': len(nodes),
            'mode': actual_mode,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error fetching nodes: {str(e)}")
        # 예외 발생 시도 Mock 데이터 반환
        return jsonify({
            'success': True,
            'nodes': [
                {'name': 'fallback-node', 'state': 'UNKNOWN', 'cpus': '0/0/0/0', 'memory': '0', 'free_memory': '0', 'cpu_load': '0.00', 'time_limit': 'infinite', 'nodes': '1'}
            ],
            'count': 1,
            'mode': 'mock',
            'error_message': str(e),
            'timestamp': datetime.now().isoformat()
        })


@node_bp.route('/nodes/<node_name>', methods=['GET'])
def get_node_detail(node_name):
    """
    특정 노드의 상세 정보 조회
    GET /api/nodes/<node_name>
    """
    try:
        if MOCK_MODE:
            # Mock 데이터
            node_info = {
                'NodeName': node_name,
                'State': 'IDLE' if node_name != 'cn03' else 'DRAINED',
                'CPUAlloc': '0' if node_name != 'cn02' else '48',
                'CPUTot': '64',
                'RealMemory': '256000',
                'AllocMem': '0' if node_name != 'cn02' else '128000',
                'FreeMem': '220000',
                'CPULoad': '0.50' if node_name != 'cn02' else '12.30',
                'Partitions': 'standard,gpu',
                'OS': 'Linux 5.15.0',
                'Arch': 'x86_64',
                'Reason': 'Manual maintenance' if node_name == 'cn03' else 'None'
            }
        else:
            # 실제 Slurm 명령어 실행
            success, stdout, stderr = run_slurm_command(
                ['scontrol', 'show', 'node', node_name]
            )
            
            if not success:
                return jsonify({
                    'success': False,
                    'error': f'Node {node_name} not found',
                    'details': stderr
                }), 404
            
            # 결과를 딕셔너리로 변환
            node_info = {}
            for line in stdout.split('\n'):
                if '=' in line:
                    key_value_pairs = line.split()
                    for pair in key_value_pairs:
                        if '=' in pair:
                            key, value = pair.split('=', 1)
                            node_info[key] = value
        
        return jsonify({
            'success': True,
            'node': node_info,
            'mode': 'mock' if MOCK_MODE else 'production',
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error fetching node detail: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@node_bp.route('/nodes/drain', methods=['POST'])
def drain_node():
    """
    노드를 DRAIN 상태로 변경
    POST /api/nodes/drain
    Body: { "node_name": "cn01", "reason": "maintenance" }
    """
    try:
        data = request.get_json()
        node_name = data.get('node_name')
        reason = data.get('reason', 'Manual maintenance')
        
        if not node_name:
            return jsonify({
                'success': False,
                'error': 'node_name is required'
            }), 400
        
        if MOCK_MODE:
            # Mock 모드에서는 성공으로 간주
            logger.info(f"🎭 Mock: Draining node {node_name} with reason: {reason}")
            success = True
        else:
            # 실제 Slurm 명령어 실행
            success, stdout, stderr = run_slurm_command(
                ['scontrol', 'update', f'NodeName={node_name}', 
                 'State=DRAIN', f'Reason="{reason}"'],
                use_sudo=True  # 🔧 sudo 권한 사용
            )
            
            if not success:
                return jsonify({
                    'success': False,
                    'error': 'Failed to drain node',
                    'details': stderr
                }), 500
        
        # 이력 기록
        history_entry = {
            'timestamp': datetime.now().isoformat(),
            'action': 'drain',
            'node_name': node_name,
            'reason': reason,
            'success': True
        }
        node_history.append(history_entry)
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} drained successfully',
            'node_name': node_name,
            'reason': reason,
            'mode': 'mock' if MOCK_MODE else 'production',
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error draining node: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@node_bp.route('/nodes/resume', methods=['POST'])
def resume_node():
    """
    노드를 RESUME 상태로 변경
    POST /api/nodes/resume
    Body: { "node_name": "cn01" }
    """
    try:
        data = request.get_json()
        node_name = data.get('node_name')
        
        if not node_name:
            return jsonify({
                'success': False,
                'error': 'node_name is required'
            }), 400
        
        if MOCK_MODE:
            # Mock 모드에서는 성공으로 간주
            logger.info(f"🎭 Mock: Resuming node {node_name}")
            success = True
        else:
            # 실제 Slurm 명령어 실행
            success, stdout, stderr = run_slurm_command(
                ['scontrol', 'update', f'NodeName={node_name}', 'State=RESUME'],
                use_sudo=True  # 🔧 sudo 권한 사용
            )
            
            if not success:
                return jsonify({
                    'success': False,
                    'error': 'Failed to resume node',
                    'details': stderr
                }), 500
        
        # 이력 기록
        history_entry = {
            'timestamp': datetime.now().isoformat(),
            'action': 'resume',
            'node_name': node_name,
            'success': True
        }
        node_history.append(history_entry)
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} resumed successfully',
            'node_name': node_name,
            'mode': 'mock' if MOCK_MODE else 'production',
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error resuming node: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@node_bp.route('/nodes/reboot', methods=['POST'])
def reboot_node():
    """
    노드를 재부팅
    POST /api/nodes/reboot
    Body: { "node_name": "cn01", "reason": "system update" }
    
    🔧 FIX: sudo 권한으로 scontrol reboot 실행
    """
    try:
        data = request.get_json()
        
        if data is None:
            logger.error("Failed to parse JSON from request")
            return jsonify({
                'success': False,
                'error': 'Invalid JSON or Content-Type. Expected application/json'
            }), 400
        
        node_name = data.get('node_name')
        reason = data.get('reason', 'Manual reboot')
        
        if not node_name:
            return jsonify({
                'success': False,
                'error': 'node_name is required'
            }), 400
        
        logger.info(f"Reboot request for node {node_name}, reason: {reason}")
        
        if MOCK_MODE:
            # Mock 모드에서는 성공으로 간주
            logger.info(f"🎭 Mock: Rebooting node {node_name}")
            success = True
        else:
            # 🔧 FIX: sudo 권한으로 scontrol reboot 실행
            logger.info(f"Production mode: Rebooting node {node_name} using sudo scontrol")
            
            try:
                # sudo scontrol reboot 명령어 실행
                success, stdout, stderr = run_slurm_command(
                    ['scontrol', 'reboot', node_name, f'reason={reason}'],
                    use_sudo=True  # 🔧 sudo 권한 사용
                )
                
                if success:
                    logger.info(f"✅ Node {node_name} reboot command sent successfully")
                else:
                    logger.error(f"❌ Reboot command failed: {stderr}")
                    return jsonify({
                        'success': False,
                        'error': 'Failed to send reboot command',
                        'details': stderr
                    }), 500
                    
            except Exception as reboot_error:
                logger.error(f"Reboot command error: {reboot_error}")
                import traceback
                logger.error(traceback.format_exc())
                return jsonify({
                    'success': False,
                    'error': f'Reboot command error: {str(reboot_error)}'
                }), 500
        
        # 이력 기록
        history_entry = {
            'timestamp': datetime.now().isoformat(),
            'action': 'reboot',
            'node_name': node_name,
            'reason': reason,
            'success': True
        }
        node_history.append(history_entry)
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} reboot command sent successfully',
            'node_name': node_name,
            'reason': reason,
            'mode': 'mock' if MOCK_MODE else 'production',
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error rebooting node: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@node_bp.route('/nodes/history', methods=['GET'])
def get_node_history():
    """
    노드 작업 이력 조회
    GET /api/nodes/history?node_name=cn01&limit=100
    """
    try:
        node_name = request.args.get('node_name')
        limit = int(request.args.get('limit', 100))
        
        # 필터링
        filtered_history = node_history
        if node_name:
            filtered_history = [h for h in node_history if h.get('node_name') == node_name]
        
        # 최신순 정렬 및 제한
        filtered_history = sorted(filtered_history, key=lambda x: x['timestamp'], reverse=True)[:limit]
        
        return jsonify({
            'success': True,
            'history': filtered_history,
            'count': len(filtered_history),
            'mode': 'mock' if MOCK_MODE else 'production',
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error fetching node history: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def init_app(app):
    """
    Flask 앱에 Blueprint 등록
    """
    app.register_blueprint(node_bp)
    logger.info("✅ Node Management API registered")
FULL_FILE

echo "✅ node_management_api_sudo.py 파일 생성 완료"
echo ""

# 파일 교체 여부 확인
read -p "node_management_api.py를 수정된 버전으로 교체하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp node_management_api_sudo.py node_management_api.py
    echo "✅ node_management_api.py 교체 완료"
else
    echo "⚠️  교체하지 않음. 수동으로 교체하려면:"
    echo "   cp node_management_api_sudo.py node_management_api.py"
fi
echo ""

# 4. 백엔드 재시작 안내
echo "🔄 Step 4/4: 백엔드 재시작"
echo "--------------------------------------------------------------------------------"
echo "수정 사항을 적용하려면 백엔드를 재시작해야 합니다:"
echo ""
echo "cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory"
echo "./stop_all.sh"
echo "./start_all.sh"
echo ""
echo "--------------------------------------------------------------------------------"
echo ""

echo "================================================================================"
echo "✅ 수정 완료!"
echo "================================================================================"
echo ""
echo "🧪 테스트 방법:"
echo "  1. sudo 권한 확인: sudo -n scontrol show config"
echo "  2. Reboot API 테스트:"
echo "     curl -X POST http://localhost:5010/api/nodes/reboot \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d '{\"node_name\": \"node001\", \"reason\": \"test\"}' | jq ."
echo ""
