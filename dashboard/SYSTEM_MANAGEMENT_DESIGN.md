# 시스템 관리 기능 추가 설계 문서

## 📋 목표
다음 4가지 시스템 관리 기능을 추가:
1. **설정 관리 UI** - Slurm 설정을 웹에서 편집
2. **노드 관리** - 노드 상태 제어 및 모니터링
3. **자동 스케일링** - 부하에 따른 자동 리소스 조정
4. **Health Check 시스템** - 시스템 상태 모니터링 및 자동 복구

---

## 🎯 현재 시스템 분석

### Frontend 구조 분석
```
Dashboard.tsx (메인)
├── activeTab: 'cluster' | 'monitoring' | 'data' | 'jobs' | 'prometheus' | 'templates' | 'customdash' | 'reports'
├── ConfigurationManager.tsx (기존) - JSON/YAML 설정 다운로드/업로드
├── GroupPanel.tsx - 그룹(파티션) 관리
├── ClusterStats.tsx - 클러스터 통계
├── NodeCard.tsx - 개별 노드 카드
└── RealtimeMonitoring.tsx - 실시간 모니터링
```

**발견 사항**:
- ✅ `ConfigurationManager.tsx`가 이미 존재 (기본 설정 저장/로드)
- ✅ Dashboard에 탭 시스템 존재 (새 탭 추가 가능)
- ✅ `NodeCard.tsx` 존재 (노드 UI 컴포넌트)
- ⚠️ 시스템 관리 전용 탭이 없음

### Backend 구조 분석
```
app.py (메인)
├── alerts_api.py - 디스크 알림
├── dashboard_api.py - 대시보드 설정
├── notifications_api.py - 알림
├── prometheus_api.py - 메트릭
├── slurm_config_manager.py (기존) - Slurm 설정 관리
├── slurm_commands.py - Slurm 명령 래퍼
└── monitoring.py - 모니터링 로직
```

**발견 사항**:
- ✅ `slurm_config_manager.py`가 이미 존재 (QoS, Partition 관리)
- ✅ `monitoring.py` 존재 (모니터링 기능)
- ⚠️ 노드 제어 API 없음
- ⚠️ Health check API 없음
- ⚠️ 스케일링 API 없음

---

## 🏗️ 설계 방안

## 1. 설정 관리 UI 강화

### 1.1 Frontend 추가 위치

#### 옵션 A: 기존 ConfigurationManager 확장 (추천)
```typescript
// ConfigurationManager.tsx 확장
// 현재: JSON/YAML 다운로드/업로드만 지원
// 추가: 실시간 편집 기능

<ConfigurationManager>
  <Tabs>
    <Tab label="Import/Export">
      {/* 기존 기능 */}
      <ImportExport />
    </Tab>
    
    {/* 🆕 새로운 탭들 */}
    <Tab label="Slurm Config">
      <SlurmConfigEditor />
    </Tab>
    
    <Tab label="QoS Management">
      <QoSManager />
    </Tab>
    
    <Tab label="Partition Settings">
      <PartitionEditor />
    </Tab>
  </Tabs>
</ConfigurationManager>
```

**장점**:
- 기존 UI 패턴 재사용
- 설정 관련 기능이 한 곳에 집중
- 최소한의 구조 변경

**단점**:
- ConfigurationManager가 너무 비대해질 수 있음

#### 옵션 B: 새로운 SystemSettings 컴포넌트 생성
```typescript
// Dashboard.tsx
<Dashboard>
  <Tab activeTab="system-settings">
    <SystemSettings>
      <SlurmConfigEditor />
      <QoSManager />
      <PartitionEditor />
      <GeneralSettings />
    </SystemSettings>
  </Tab>
</Dashboard>
```

**장점**:
- 명확한 분리
- 확장성 좋음
- 시스템 관리 전용 공간

**단점**:
- Dashboard.tsx 수정 필요
- 새로운 라우팅 필요

### 1.2 새로운 컴포넌트 구조

```
src/components/SystemManagement/
├── index.tsx                          # 메인 컴포넌트
├── ConfigEditor/
│   ├── SlurmConfigEditor.tsx          # slurm.conf 편집기
│   ├── ConfigSyntaxHighlight.tsx      # 구문 강조
│   └── ConfigValidator.tsx            # 설정 검증
├── QoSManager/
│   ├── QoSList.tsx                    # QoS 목록
│   ├── QoSForm.tsx                    # QoS 생성/수정 폼
│   └── QoSCard.tsx                    # QoS 카드
└── PartitionManager/
    ├── PartitionList.tsx              # 파티션 목록
    ├── PartitionForm.tsx              # 파티션 설정
    └── PartitionTopology.tsx          # 파티션 토폴로지 시각화
```

### 1.3 Backend API 추가

```python
# 새 파일: backend_5010/system_config_api.py

from flask import Blueprint, request, jsonify
from slurm_config_manager import SlurmConfigManager
import os

system_config_bp = Blueprint('system_config', __name__, url_prefix='/api/system/config')

# ===== Slurm Config 편집 =====

@system_config_bp.route('/slurm.conf', methods=['GET'])
def get_slurm_config():
    """slurm.conf 내용 조회"""
    try:
        config_path = '/etc/slurm/slurm.conf'
        with open(config_path, 'r') as f:
            content = f.read()
        
        return jsonify({
            'success': True,
            'content': content,
            'path': config_path
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@system_config_bp.route('/slurm.conf', methods=['PUT'])
def update_slurm_config():
    """slurm.conf 수정 (검증 + 백업 + 적용)"""
    try:
        new_content = request.json.get('content')
        
        # 1. 백업 생성
        manager = SlurmConfigManager()
        backup_path = manager.backup_config()
        
        # 2. 임시 파일에 쓰기
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
            tmp.write(new_content)
            tmp_path = tmp.name
        
        # 3. 검증 (scontrol로 문법 체크)
        validation = manager.validate_config(tmp_path)
        if not validation['valid']:
            os.unlink(tmp_path)
            return jsonify({
                'success': False,
                'error': 'Invalid configuration',
                'details': validation['errors']
            }), 400
        
        # 4. 적용
        subprocess.run(['sudo', 'cp', tmp_path, '/etc/slurm/slurm.conf'], check=True)
        os.unlink(tmp_path)
        
        # 5. Slurm 재설정
        manager.reconfigure_slurm()
        
        return jsonify({
            'success': True,
            'message': 'Configuration updated successfully',
            'backup': backup_path
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@system_config_bp.route('/slurm.conf/validate', methods=['POST'])
def validate_slurm_config():
    """설정 검증만 수행"""
    try:
        content = request.json.get('content')
        manager = SlurmConfigManager()
        
        # 임시 파일로 검증
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        
        validation = manager.validate_config(tmp_path)
        os.unlink(tmp_path)
        
        return jsonify({
            'success': True,
            'valid': validation['valid'],
            'errors': validation.get('errors', []),
            'warnings': validation.get('warnings', [])
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== QoS 관리 =====

@system_config_bp.route('/qos', methods=['GET'])
def list_qos():
    """QoS 목록 조회"""
    try:
        result = subprocess.run(
            ['sacctmgr', 'show', 'qos', '-P', '-n'],
            capture_output=True, text=True, check=True
        )
        
        qos_list = []
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split('|')
                qos_list.append({
                    'name': parts[0],
                    'priority': parts[1] if len(parts) > 1 else None,
                    'max_tres_per_job': parts[2] if len(parts) > 2 else None
                })
        
        return jsonify({'success': True, 'qos': qos_list})
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@system_config_bp.route('/qos', methods=['POST'])
def create_qos():
    """QoS 생성"""
    try:
        data = request.json
        name = data.get('name')
        max_cores = data.get('max_cores', 0)
        priority = data.get('priority', 1000)
        
        manager = SlurmConfigManager()
        success = manager.create_or_update_qos(name, max_cores, priority)
        
        if success:
            return jsonify({
                'success': True,
                'message': f'QoS {name} created successfully'
            })
        else:
            return jsonify({'success': False, 'error': 'Failed to create QoS'}), 500
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@system_config_bp.route('/qos/<qos_name>', methods=['PUT'])
def update_qos(qos_name):
    """QoS 수정"""
    try:
        data = request.json
        max_cores = data.get('max_cores')
        priority = data.get('priority')
        
        manager = SlurmConfigManager()
        success = manager.create_or_update_qos(qos_name, max_cores, priority)
        
        return jsonify({
            'success': success,
            'message': f'QoS {qos_name} updated'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@system_config_bp.route('/qos/<qos_name>', methods=['DELETE'])
def delete_qos(qos_name):
    """QoS 삭제"""
    try:
        manager = SlurmConfigManager()
        success = manager.delete_qos(qos_name)
        
        return jsonify({
            'success': success,
            'message': f'QoS {qos_name} deleted'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 백업/복원 =====

@system_config_bp.route('/backups', methods=['GET'])
def list_backups():
    """백업 목록 조회"""
    try:
        backup_dir = os.path.expanduser('~/.slurm_backups')
        backups = []
        
        for filename in os.listdir(backup_dir):
            if filename.startswith('slurm.conf.backup.'):
                filepath = os.path.join(backup_dir, filename)
                stat = os.stat(filepath)
                backups.append({
                    'filename': filename,
                    'path': filepath,
                    'size': stat.st_size,
                    'created_at': stat.st_mtime
                })
        
        backups.sort(key=lambda x: x['created_at'], reverse=True)
        
        return jsonify({'success': True, 'backups': backups})
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@system_config_bp.route('/restore', methods=['POST'])
def restore_backup():
    """백업에서 복원"""
    try:
        backup_path = request.json.get('backup_path')
        
        manager = SlurmConfigManager()
        manager.restore_config(backup_path)
        
        return jsonify({
            'success': True,
            'message': 'Configuration restored successfully'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
```

---

## 2. 노드 관리

### 2.1 Frontend 컴포넌트

```
src/components/NodeManagement/
├── index.tsx                      # 메인 노드 관리 페이지
├── NodeList.tsx                   # 노드 목록 (테이블/그리드)
├── NodeDetailPanel.tsx            # 노드 상세 정보 사이드 패널
├── NodeControlPanel.tsx           # 노드 제어 (Drain/Resume/Reboot)
├── NodeGroupManager.tsx           # 노드 그룹 관리
├── MaintenanceScheduler.tsx       # 유지보수 스케줄
└── NodeHealthIndicator.tsx        # 노드 헬스 표시기
```

#### 노드 관리 UI 모습
```typescript
// NodeManagement/index.tsx
<NodeManagement>
  <div className="grid grid-cols-4 gap-4">
    {/* 왼쪽: 노드 목록 */}
    <div className="col-span-3">
      <NodeList
        nodes={nodes}
        onSelectNode={setSelectedNode}
        filters={{
          state: ['idle', 'allocated', 'down', 'drain'],
          partition: partitions,
          group: nodeGroups
        }}
      />
    </div>
    
    {/* 오른쪽: 선택된 노드 제어 */}
    <div className="col-span-1">
      <NodeDetailPanel node={selectedNode}>
        <NodeHealthIndicator />
        <NodeControlPanel>
          <Button onClick={drainNode}>Drain</Button>
          <Button onClick={resumeNode}>Resume</Button>
          <Button onClick={rebootNode}>Reboot</Button>
          <Button onClick={powerOff}>Power Off</Button>
        </NodeControlPanel>
        <MaintenanceScheduler />
      </NodeDetailPanel>
    </div>
  </div>
</NodeManagement>
```

### 2.2 Backend API

```python
# 새 파일: backend_5010/node_management_api.py

from flask import Blueprint, request, jsonify
import subprocess
from datetime import datetime

node_mgmt_bp = Blueprint('node_management', __name__, url_prefix='/api/nodes')

# ===== 노드 상태 제어 =====

@node_mgmt_bp.route('/<node_name>/drain', methods=['POST'])
def drain_node(node_name):
    """노드를 Drain 상태로 전환"""
    try:
        reason = request.json.get('reason', 'Manual drain from dashboard')
        
        # scontrol update NodeName=node001 State=DRAIN Reason="maintenance"
        subprocess.run([
            'sudo', 'scontrol', 'update',
            f'NodeName={node_name}',
            'State=DRAIN',
            f'Reason="{reason}"'
        ], check=True)
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} drained',
            'reason': reason
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@node_mgmt_bp.route('/<node_name>/resume', methods=['POST'])
def resume_node(node_name):
    """노드를 Resume (정상 상태로)"""
    try:
        subprocess.run([
            'sudo', 'scontrol', 'update',
            f'NodeName={node_name}',
            'State=RESUME'
        ], check=True)
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} resumed'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@node_mgmt_bp.route('/<node_name>/reboot', methods=['POST'])
def reboot_node(node_name):
    """노드 재부팅"""
    try:
        # SSH로 원격 재부팅
        subprocess.run([
            'ssh', node_name,
            'sudo', 'reboot'
        ], check=True)
        
        # Slurm에 노드 다운 표시
        subprocess.run([
            'sudo', 'scontrol', 'update',
            f'NodeName={node_name}',
            'State=DOWN',
            'Reason="Rebooting"'
        ], check=True)
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} rebooting'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@node_mgmt_bp.route('/<node_name>/power', methods=['POST'])
def control_node_power(node_name):
    """노드 전원 제어 (on/off)"""
    try:
        action = request.json.get('action')  # 'on' or 'off'
        
        if action == 'off':
            # 안전하게 종료
            subprocess.run([
                'ssh', node_name,
                'sudo', 'shutdown', '-h', 'now'
            ], check=True)
            
            # Slurm에 표시
            subprocess.run([
                'sudo', 'scontrol', 'update',
                f'NodeName={node_name}',
                'State=DOWN',
                'Reason="Powered off"'
            ], check=True)
            
        elif action == 'on':
            # IPMI나 Wake-on-LAN 사용
            # 예: ipmitool -H <node_ip> -U admin -P pass power on
            pass
        
        return jsonify({
            'success': True,
            'message': f'Node {node_name} power {action}'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 노드 그룹 관리 =====

@node_mgmt_bp.route('/groups', methods=['GET'])
def list_node_groups():
    """노드 그룹 목록"""
    # DB에서 조회 또는 설정 파일에서 로드
    pass

@node_mgmt_bp.route('/groups', methods=['POST'])
def create_node_group():
    """노드 그룹 생성"""
    # 그룹명, 노드 리스트 저장
    pass

# ===== 유지보수 스케줄 =====

@node_mgmt_bp.route('/<node_name>/maintenance', methods=['POST'])
def schedule_maintenance(node_name):
    """유지보수 스케줄 등록"""
    try:
        data = request.json
        start_time = data.get('start_time')  # ISO format
        end_time = data.get('end_time')
        reason = data.get('reason')
        
        # DB에 스케줄 저장
        # 시간이 되면 자동으로 Drain 수행
        
        return jsonify({
            'success': True,
            'message': 'Maintenance scheduled',
            'schedule_id': 'maint-001'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@node_mgmt_bp.route('/maintenance', methods=['GET'])
def list_maintenance_schedules():
    """유지보수 스케줄 목록"""
    # DB에서 스케줄 조회
    pass
```

---

## 3. 자동 스케일링

### 3.1 Frontend 컴포넌트

```
src/components/AutoScaling/
├── index.tsx                      # 메인 자동 스케일링 페이지
├── ScalingPolicyList.tsx          # 스케일링 정책 목록
├── ScalingPolicyForm.tsx          # 정책 생성/수정 폼
├── ScalingHistory.tsx             # 스케일링 히스토리
├── ScalingMetrics.tsx             # 메트릭 차트
└── ScalingSimulator.tsx           # 시뮬레이터 (정책 테스트)
```

#### 자동 스케일링 UI 모습
```typescript
<AutoScaling>
  <div className="grid grid-cols-3 gap-6">
    {/* 왼쪽: 정책 목록 */}
    <div className="col-span-2">
      <ScalingPolicyList>
        <PolicyCard
          name="Scale up on high CPU"
          trigger="CPU > 80% for 5 min"
          action="Add 2 nodes"
          enabled={true}
        />
        <PolicyCard
          name="Scale down on idle"
          trigger="CPU < 20% for 30 min"
          action="Remove 1 node"
          enabled={false}
        />
      </ScalingPolicyList>
      
      <ScalingHistory />
    </div>
    
    {/* 오른쪽: 메트릭 */}
    <div className="col-span-1">
      <ScalingMetrics>
        <Chart type="cpu_usage" />
        <Chart type="queue_length" />
        <Chart type="node_count" />
      </ScalingMetrics>
    </div>
  </div>
</AutoScaling>
```

### 3.2 Backend API

```python
# 새 파일: backend_5010/autoscaling_api.py

from flask import Blueprint, request, jsonify
from datetime import datetime
import threading
import time

autoscaling_bp = Blueprint('autoscaling', __name__, url_prefix='/api/autoscaling')

# 스케일링 정책 저장 (간단한 예, 실제로는 DB 사용)
scaling_policies = []
scaling_history = []

# ===== 스케일링 정책 관리 =====

@autoscaling_bp.route('/policies', methods=['GET'])
def list_policies():
    """스케일링 정책 목록"""
    return jsonify({
        'success': True,
        'policies': scaling_policies
    })

@autoscaling_bp.route('/policies', methods=['POST'])
def create_policy():
    """스케일링 정책 생성"""
    try:
        data = request.json
        
        policy = {
            'id': f"policy-{len(scaling_policies) + 1}",
            'name': data.get('name'),
            'enabled': data.get('enabled', True),
            'trigger': {
                'metric': data.get('metric'),  # 'cpu_usage', 'queue_length', 'memory_usage'
                'operator': data.get('operator'),  # '>', '<', '=='
                'threshold': data.get('threshold'),
                'duration': data.get('duration')  # seconds
            },
            'action': {
                'type': data.get('action_type'),  # 'add_nodes', 'remove_nodes'
                'count': data.get('node_count'),
                'node_type': data.get('node_type', 'compute')  # AWS 인스턴스 타입 등
            },
            'cooldown': data.get('cooldown', 300),  # 재실행 대기 시간
            'created_at': datetime.now().isoformat()
        }
        
        scaling_policies.append(policy)
        
        return jsonify({
            'success': True,
            'policy': policy
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@autoscaling_bp.route('/policies/<policy_id>', methods=['PUT'])
def update_policy(policy_id):
    """정책 수정"""
    # 정책 업데이트
    pass

@autoscaling_bp.route('/policies/<policy_id>', methods=['DELETE'])
def delete_policy(policy_id):
    """정책 삭제"""
    # 정책 삭제
    pass

@autoscaling_bp.route('/policies/<policy_id>/toggle', methods=['POST'])
def toggle_policy(policy_id):
    """정책 활성화/비활성화"""
    try:
        for policy in scaling_policies:
            if policy['id'] == policy_id:
                policy['enabled'] = not policy['enabled']
                return jsonify({
                    'success': True,
                    'enabled': policy['enabled']
                })
        
        return jsonify({'success': False, 'error': 'Policy not found'}), 404
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 스케일링 실행 =====

@autoscaling_bp.route('/scale', methods=['POST'])
def execute_scaling():
    """수동 스케일링 실행"""
    try:
        data = request.json
        action = data.get('action')  # 'add' or 'remove'
        count = data.get('count', 1)
        node_type = data.get('node_type', 'compute')
        
        if action == 'add':
            result = add_nodes(count, node_type)
        elif action == 'remove':
            result = remove_nodes(count)
        else:
            return jsonify({'success': False, 'error': 'Invalid action'}), 400
        
        # 히스토리 저장
        scaling_history.append({
            'timestamp': datetime.now().isoformat(),
            'action': action,
            'count': count,
            'node_type': node_type,
            'result': result,
            'trigger': 'manual'
        })
        
        return jsonify({
            'success': True,
            'result': result
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 클라우드 프로바이더 통합 =====

def add_nodes(count: int, node_type: str):
    """노드 추가 (AWS/Azure/GCP)"""
    # 예: AWS EC2 인스턴스 생성
    # boto3.client('ec2').run_instances(...)
    
    # Slurm에 노드 등록
    # scontrol create NodeName=cloud-node-001 ...
    
    return {
        'nodes_added': count,
        'node_names': [f'cloud-node-{i}' for i in range(count)]
    }

def remove_nodes(count: int):
    """노드 제거"""
    # 1. 유휴 노드 찾기
    # 2. Drain 상태로 변경
    # 3. 작업 완료 대기
    # 4. Slurm에서 제거
    # 5. 클라우드 인스턴스 종료
    
    return {
        'nodes_removed': count
    }

# ===== 스케일링 모니터링 =====

@autoscaling_bp.route('/history', methods=['GET'])
def get_scaling_history():
    """스케일링 히스토리"""
    limit = request.args.get('limit', 50, type=int)
    
    return jsonify({
        'success': True,
        'history': scaling_history[-limit:]
    })

@autoscaling_bp.route('/metrics', methods=['GET'])
def get_scaling_metrics():
    """현재 스케일링 관련 메트릭"""
    try:
        # Prometheus에서 메트릭 가져오기
        # - 현재 노드 수
        # - CPU/메모리 평균 사용률
        # - 큐에 대기 중인 작업 수
        
        return jsonify({
            'success': True,
            'metrics': {
                'current_nodes': 10,
                'cpu_usage': 65.5,
                'memory_usage': 72.3,
                'queue_length': 5,
                'idle_nodes': 2
            }
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 백그라운드 모니터링 스레드 =====

def autoscaling_monitor():
    """백그라운드에서 정책 모니터링 및 자동 실행"""
    while True:
        for policy in scaling_policies:
            if not policy['enabled']:
                continue
            
            # 메트릭 확인
            metrics = get_current_metrics()
            trigger = policy['trigger']
            
            metric_value = metrics.get(trigger['metric'])
            threshold = trigger['threshold']
            operator = trigger['operator']
            
            # 조건 확인
            triggered = False
            if operator == '>' and metric_value > threshold:
                triggered = True
            elif operator == '<' and metric_value < threshold:
                triggered = True
            
            if triggered:
                # 쿨다운 확인
                last_execution = policy.get('last_execution')
                if last_execution:
                    elapsed = (datetime.now() - datetime.fromisoformat(last_execution)).seconds
                    if elapsed < policy['cooldown']:
                        continue
                
                # 액션 실행
                action = policy['action']
                if action['type'] == 'add_nodes':
                    add_nodes(action['count'], action['node_type'])
                elif action['type'] == 'remove_nodes':
                    remove_nodes(action['count'])
                
                policy['last_execution'] = datetime.now().isoformat()
        
        time.sleep(60)  # 1분마다 체크

# 서버 시작 시 모니터링 스레드 시작
# threading.Thread(target=autoscaling_monitor, daemon=True).start()
```

---

## 4. Health Check 시스템

### 4.1 Frontend 컴포넌트

```
src/components/HealthCheck/
├── index.tsx                      # 헬스 체크 대시보드
├── SystemStatus.tsx               # 전체 시스템 상태
├── ServiceStatus.tsx              # 각 서비스 상태
├── HealthHistory.tsx              # 헬스 체크 히스토리
├── AlertRules.tsx                 # 알림 규칙 설정
└── IncidentLog.tsx                # 장애 로그
```

#### Health Check UI 모습
```typescript
<HealthCheck>
  <div className="grid grid-cols-1 gap-6">
    {/* 전체 상태 */}
    <SystemStatus>
      <StatusCard
        service="Backend API"
        status="healthy"
        uptime="99.9%"
        lastCheck="2s ago"
      />
      <StatusCard
        service="WebSocket"
        status="healthy"
        uptime="99.8%"
        lastCheck="1s ago"
      />
      <StatusCard
        service="Prometheus"
        status="warning"
        uptime="98.5%"
        lastCheck="5s ago"
        message="High memory usage"
      />
      <StatusCard
        service="Slurm Controller"
        status="healthy"
        uptime="100%"
        lastCheck="3s ago"
      />
    </SystemStatus>
    
    {/* 서비스별 상세 */}
    <ServiceStatus>
      <Tabs>
        <Tab label="API Endpoints">
          <EndpointHealthList />
        </Tab>
        <Tab label="Database">
          <DatabaseHealth />
        </Tab>
        <Tab label="Storage">
          <StorageHealth />
        </Tab>
        <Tab label="Network">
          <NetworkHealth />
        </Tab>
      </Tabs>
    </ServiceStatus>
    
    {/* 히스토리 및 로그 */}
    <div className="grid grid-cols-2 gap-6">
      <HealthHistory />
      <IncidentLog />
    </div>
  </div>
</HealthCheck>
```

### 4.2 Backend API

```python
# 새 파일: backend_5010/health_check_api.py

from flask import Blueprint, jsonify
import subprocess
import psutil
import requests
from datetime import datetime
import sqlite3

health_bp = Blueprint('health', __name__, url_prefix='/api/health')

# ===== 전체 시스템 상태 =====

@health_bp.route('/status', methods=['GET'])
def system_status():
    """전체 시스템 헬스 체크"""
    try:
        checks = {
            'backend': check_backend(),
            'websocket': check_websocket(),
            'prometheus': check_prometheus(),
            'node_exporter': check_node_exporter(),
            'slurm': check_slurm(),
            'database': check_database(),
            'storage': check_storage()
        }
        
        # 전체 상태 판단
        overall_status = 'healthy'
        for service, status in checks.items():
            if status['status'] == 'down':
                overall_status = 'critical'
                break
            elif status['status'] == 'warning' and overall_status == 'healthy':
                overall_status = 'warning'
        
        return jsonify({
            'success': True,
            'overall_status': overall_status,
            'timestamp': datetime.now().isoformat(),
            'services': checks
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 개별 서비스 체크 함수 =====

def check_backend():
    """Backend API 상태"""
    try:
        # 자기 자신 체크
        return {
            'status': 'healthy',
            'uptime': get_process_uptime('app.py'),
            'memory': psutil.Process().memory_info().rss / 1024 / 1024,  # MB
            'cpu': psutil.Process().cpu_percent(interval=1)
        }
    except:
        return {'status': 'down'}

def check_websocket():
    """WebSocket 서버 상태"""
    try:
        response = requests.get('http://localhost:5012/health', timeout=5)
        if response.status_code == 200:
            data = response.json()
            return {
                'status': 'healthy',
                'clients': data.get('clients', 0),
                'subscriptions': data.get('subscriptions', {})
            }
        else:
            return {'status': 'warning', 'message': f'HTTP {response.status_code}'}
    except:
        return {'status': 'down'}

def check_prometheus():
    """Prometheus 상태"""
    try:
        response = requests.get('http://localhost:9090/-/healthy', timeout=5)
        if response.status_code == 200:
            # 추가 체크: 타겟 상태
            targets = requests.get('http://localhost:9090/api/v1/targets').json()
            active_targets = targets['data']['activeTargets']
            down_targets = [t for t in active_targets if t['health'] != 'up']
            
            status = 'healthy' if len(down_targets) == 0 else 'warning'
            
            return {
                'status': status,
                'total_targets': len(active_targets),
                'down_targets': len(down_targets),
                'issues': down_targets if down_targets else None
            }
        else:
            return {'status': 'warning'}
    except:
        return {'status': 'down'}

def check_node_exporter():
    """Node Exporter 상태"""
    try:
        response = requests.get('http://localhost:9100/metrics', timeout=5)
        return {
            'status': 'healthy' if response.status_code == 200 else 'warning'
        }
    except:
        return {'status': 'down'}

def check_slurm():
    """Slurm 상태"""
    try:
        # scontrol ping
        result = subprocess.run(
            ['scontrol', 'ping'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            # slurmctld, slurmd 응답 확인
            output = result.stdout
            slurmctld_up = 'Slurmctld(primary)' in output or 'UP' in output
            
            return {
                'status': 'healthy' if slurmctld_up else 'warning',
                'details': output
            }
        else:
            return {'status': 'down', 'error': result.stderr}
            
    except:
        return {'status': 'down'}

def check_database():
    """데이터베이스 상태"""
    try:
        conn = sqlite3.connect('dashboard.db', timeout=5)
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM notifications')
        count = cursor.fetchone()[0]
        conn.close()
        
        return {
            'status': 'healthy',
            'notifications_count': count
        }
    except Exception as e:
        return {'status': 'down', 'error': str(e)}

def check_storage():
    """스토리지 상태"""
    try:
        # /data 파티션 체크
        disk = psutil.disk_usage('/data')
        usage_percent = disk.percent
        
        status = 'healthy'
        if usage_percent > 90:
            status = 'critical'
        elif usage_percent > 80:
            status = 'warning'
        
        return {
            'status': status,
            'usage_percent': usage_percent,
            'free_gb': disk.free / 1024 / 1024 / 1024
        }
    except:
        return {'status': 'down'}

# ===== API 엔드포인트 체크 =====

@health_bp.route('/endpoints', methods=['GET'])
def check_endpoints():
    """주요 API 엔드포인트 테스트"""
    endpoints = [
        '/api/nodes',
        '/api/jobs',
        '/api/notifications',
        '/api/prometheus/health',
        '/api/reports'
    ]
    
    results = []
    for endpoint in endpoints:
        try:
            start = datetime.now()
            response = requests.get(f'http://localhost:5010{endpoint}', timeout=10)
            elapsed = (datetime.now() - start).total_seconds() * 1000
            
            results.append({
                'endpoint': endpoint,
                'status': 'healthy' if response.status_code == 200 else 'warning',
                'response_time_ms': round(elapsed, 2),
                'status_code': response.status_code
            })
        except Exception as e:
            results.append({
                'endpoint': endpoint,
                'status': 'down',
                'error': str(e)
            })
    
    return jsonify({
        'success': True,
        'endpoints': results
    })

# ===== 자동 복구 =====

@health_bp.route('/auto-heal', methods=['POST'])
def auto_heal():
    """서비스 자동 복구 시도"""
    try:
        service = request.json.get('service')
        
        if service == 'websocket':
            # WebSocket 서버 재시작
            subprocess.run([
                'bash', '-c',
                'cd /path/to/websocket_5011 && ./stop.sh && ./start.sh'
            ], check=True)
            
        elif service == 'prometheus':
            # Prometheus 재시작
            subprocess.run([
                'bash', '-c',
                'cd /path/to/prometheus_9090 && ./stop.sh && ./start.sh'
            ], check=True)
        
        return jsonify({
            'success': True,
            'message': f'{service} restarted'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ===== 헬스 체크 히스토리 =====

@health_bp.route('/history', methods=['GET'])
def health_history():
    """헬스 체크 히스토리 (DB에서 조회)"""
    # 지난 24시간 헬스 체크 기록
    pass

# ===== 유틸리티 함수 =====

def get_process_uptime(process_name):
    """프로세스 업타임 계산"""
    try:
        for proc in psutil.process_iter(['name', 'create_time']):
            if process_name in proc.info['name']:
                create_time = datetime.fromtimestamp(proc.info['create_time'])
                uptime = datetime.now() - create_time
                return str(uptime).split('.')[0]  # HH:MM:SS
        return 'Unknown'
    except:
        return 'Unknown'
```

---

## 📊 통합 방안 요약

### Dashboard.tsx 수정
```typescript
// 새로운 탭 추가
type TabType = 
  | 'cluster' | 'monitoring' | 'data' | 'jobs' 
  | 'prometheus' | 'templates' | 'customdash' | 'reports'
  | 'system-management'  // 🆕 추가
  | 'node-management'     // 🆕 추가
  | 'auto-scaling'        // 🆕 추가
  | 'health-check';       // 🆕 추가

// 탭 컴포넌트 임포트
import SystemManagement from './SystemManagement';
import NodeManagement from './NodeManagement';
import AutoScaling from './AutoScaling';
import HealthCheck from './HealthCheck';

// 렌더링
{activeTab === 'system-management' && <SystemManagement />}
{activeTab === 'node-management' && <NodeManagement />}
{activeTab === 'auto-scaling' && <AutoScaling />}
{activeTab === 'health-check' && <HealthCheck />}
```

### app.py 수정
```python
# 새 Blueprint 임포트
from system_config_api import system_config_bp
from node_management_api import node_mgmt_bp
from autoscaling_api import autoscaling_bp
from health_check_api import health_bp

# Blueprint 등록
app.register_blueprint(system_config_bp)
app.register_blueprint(node_mgmt_bp)
app.register_blueprint(autoscaling_bp)
app.register_blueprint(health_bp)
```

---

## 🎯 구현 우선순위

### Phase 1: 기본 기능 (2주)
1. **Health Check 시스템** - 가장 중요, 시스템 안정성
2. **노드 관리 기본** - Drain/Resume만

### Phase 2: 고급 기능 (3주)
3. **설정 관리 UI** - QoS 관리
4. **노드 관리 확장** - 유지보수 스케줄, 그룹 관리

### Phase 3: 자동화 (4주)
5. **자동 스케일링** - 클라우드 통합 필요

---

## 📁 파일 구조 최종안

```
dashboard_refactory/
├── frontend_3010/
│   └── src/
│       └── components/
│           ├── SystemManagement/        # 🆕
│           │   ├── index.tsx
│           │   ├── ConfigEditor/
│           │   ├── QoSManager/
│           │   └── PartitionManager/
│           ├── NodeManagement/          # 🆕
│           │   ├── index.tsx
│           │   ├── NodeList.tsx
│           │   ├── NodeControlPanel.tsx
│           │   └── MaintenanceScheduler.tsx
│           ├── AutoScaling/             # 🆕
│           │   ├── index.tsx
│           │   ├── ScalingPolicyList.tsx
│           │   └── ScalingHistory.tsx
│           └── HealthCheck/             # 🆕
│               ├── index.tsx
│               ├── SystemStatus.tsx
│               └── ServiceStatus.tsx
└── backend_5010/
    ├── system_config_api.py             # 🆕
    ├── node_management_api.py           # 🆕
    ├── autoscaling_api.py               # 🆕
    ├── health_check_api.py              # 🆕
    └── slurm_config_manager.py          # 확장
```

이렇게 설계하면 기존 시스템을 크게 건드리지 않으면서도 새로운 기능들을 체계적으로 추가할 수 있습니다!