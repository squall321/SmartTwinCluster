#!/bin/bash

echo "================================================================================"
echo "🔧 Reboot API - scontrol 경로 문제 해결"
echo "================================================================================"
echo ""
echo "문제: sudo: scontrol: command not found"
echo "해결: scontrol의 전체 경로를 사용"
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory/backend_5010

# 1. scontrol 경로 찾기
echo "📍 Step 1/3: scontrol 경로 찾기"
echo "--------------------------------------------------------------------------------"

# 소스 빌드 23.x 우선 탐색 (/usr/bin의 apt 패키지 21.x는 지원 안함)
SCONTROL_PATH=""
for path in /usr/local/slurm/bin/scontrol /opt/slurm/bin/scontrol /usr/local/bin/scontrol; do
    if [ -x "$path" ]; then
        SCONTROL_PATH="$path"
        break
    fi
done

if [ -z "$SCONTROL_PATH" ]; then
    # PATH에서 찾기 (환경변수 설정된 경우)
    SCONTROL_PATH=$(which scontrol 2>/dev/null)
fi

if [ -z "$SCONTROL_PATH" ]; then
    echo "❌ scontrol을 찾을 수 없습니다"
    echo "   소스 빌드 Slurm 23.x가 설치되어 있는지 확인하세요:"
    echo "   ls -la /usr/local/slurm/bin/scontrol"
    exit 1
fi

echo "✅ scontrol 경로: $SCONTROL_PATH"
echo ""

# 2. API 코드 수정
echo "🔄 Step 2/3: API 코드 수정"
echo "--------------------------------------------------------------------------------"

# 백업
if [ ! -f "node_management_api.py.path_backup" ]; then
    cp node_management_api.py node_management_api.py.path_backup
    echo "✅ 백업 생성: node_management_api.py.path_backup"
fi

# Python 코드에서 전체 경로 사용
cat > node_management_api_with_path.py <<FULL_FILE
"""
노드 관리 API (Flask 버전) - 전체 경로 사용
- 중복 노드 제거
- sudo에서 scontrol 전체 경로 사용
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

# Slurm 명령어 경로 설정
SCONTROL_PATH = '$SCONTROL_PATH'
SINFO_PATH = SCONTROL_PATH.replace('scontrol', 'sinfo')

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
            command = ['sudo', '-n'] + command  # -n: 비밀번호 없이 실행
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
            # 실제 Slurm 명령어 실행 (전체 경로 사용)
            success, stdout, stderr = run_slurm_command(
                [SINFO_PATH, '-N', '-o', '%N|%T|%C|%m|%e|%O|%l|%D']
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
            # 실제 Slurm 명령어 실행 (전체 경로 사용)
            success, stdout, stderr = run_slurm_command(
                [SCONTROL_PATH, 'show', 'node', node_name]
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
            # 실제 Slurm 명령어 실행 (전체 경로 사용)
            success, stdout, stderr = run_slurm_command(
                [SCONTROL_PATH, 'update', f'NodeName={node_name}', 
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
            # 실제 Slurm 명령어 실행 (전체 경로 사용)
            success, stdout, stderr = run_slurm_command(
                [SCONTROL_PATH, 'update', f'NodeName={node_name}', 'State=RESUME'],
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
    
    🔧 FIX: 전체 경로로 sudo scontrol 실행
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
            # 🔧 FIX: 전체 경로로 sudo scontrol reboot 실행
            logger.info(f"Production mode: Rebooting node {node_name} using sudo {SCONTROL_PATH}")
            
            try:
                # sudo scontrol reboot 명령어 실행 (전체 경로)
                success, stdout, stderr = run_slurm_command(
                    [SCONTROL_PATH, 'reboot', node_name, f'reason={reason}'],
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
    logger.info(f"📍 Using scontrol path: {SCONTROL_PATH}")
FULL_FILE

echo "✅ node_management_api_with_path.py 생성 완료"
echo ""

# 3. 파일 교체
echo "🔄 Step 3/3: 파일 교체 및 재시작"
echo "--------------------------------------------------------------------------------"

cp node_management_api_with_path.py node_management_api.py
echo "✅ node_management_api.py 교체 완료"
echo ""

# sudoers 파일도 전체 경로로 업데이트
CURRENT_USER=$(whoami)
echo "📝 sudoers 파일 업데이트 필요:"
echo ""
echo "sudo tee /etc/sudoers.d/slurm-dashboard <<EOF"
echo "# Slurm Dashboard - Node Management"
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH"
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH *"
echo "EOF"
echo ""
echo "sudo chmod 0440 /etc/sudoers.d/slurm-dashboard"
echo ""

read -p "sudoers 파일을 업데이트하시겠습니까? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    sudo tee /etc/sudoers.d/slurm-dashboard > /dev/null <<EOF
# Slurm Dashboard - Node Management
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH
$CURRENT_USER ALL=(ALL) NOPASSWD: $SCONTROL_PATH *
EOF
    sudo chmod 0440 /etc/sudoers.d/slurm-dashboard
    echo "✅ sudoers 업데이트 완료"
    
    if sudo visudo -c; then
        echo "✅ sudoers 검증 성공"
    else
        echo "❌ sudoers 검증 실패"
        exit 1
    fi
fi
echo ""

echo "================================================================================"
echo "✅ 수정 완료!"
echo "================================================================================"
echo ""
echo "🔄 다음 단계: 백엔드 재시작"
echo "  cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/dashboard_refactory"
echo "  ./stop_all.sh"
echo "  ./start_all.sh"
echo ""
echo "🧪 테스트:"
echo "  sudo -n $SCONTROL_PATH show config"
echo ""
