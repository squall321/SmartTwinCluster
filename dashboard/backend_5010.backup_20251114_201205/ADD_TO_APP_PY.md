# 📌 실제 Slurm 노드 정보 조회 API 추가

이 코드를 backend/app.py 파일의 `@app.route('/api/slurm/qos', methods=['GET'])` 
엔드포인트 바로 아래에 추가하세요:

```python
# ==================== 실제 노드 정보 조회 API ====================

@app.route('/api/slurm/nodes/real', methods=['GET'])
def get_real_slurm_nodes():
    """
    실제 Slurm 클러스터의 노드 정보 가져오기
    Production 모드에서만 실제 데이터 반환
    """
    try:
        if MOCK_MODE:
            return jsonify({
                'success': False,
                'mode': 'mock',
                'message': 'Real node information is only available in Production mode',
                'hint': 'Set MOCK_MODE=false to enable this feature'
            }), 400
        
        # Production 모드: 실제 노드 정보 가져오기
        from slurm_utils import get_slurm_nodes, get_partitions
        
        nodes = get_slurm_nodes()
        partitions = get_partitions()
        
        # 파티션별로 노드 그룹화
        nodes_by_partition = {}
        for node in nodes:
            partition = node.get('partition', 'default')
            if partition not in nodes_by_partition:
                nodes_by_partition[partition] = []
            nodes_by_partition[partition].append(node)
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'data': {
                'nodes': nodes,
                'partitions': partitions,
                'nodes_by_partition': nodes_by_partition,
                'total_nodes': len(nodes),
                'timestamp': datetime.now().isoformat()
            }
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/slurm/nodes/<hostname>', methods=['GET'])
def get_node_detail(hostname):
    """특정 노드의 상세 정보"""
    try:
        if MOCK_MODE:
            return jsonify({
                'success': False,
                'mode': 'mock',
                'message': 'Node details only available in Production mode'
            }), 400
        
        from slurm_utils import get_node_details
        
        details = get_node_details(hostname)
        
        if not details:
            return jsonify({
                'success': False,
                'error': f'Node {hostname} not found'
            }), 404
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'data': details
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/slurm/sync-nodes', methods=['POST'])
def sync_nodes_to_dashboard():
    """
    실제 Slurm 노드를 대시보드 형식으로 변환
    """
    try:
        if MOCK_MODE:
            return jsonify({
                'success': False,
                'mode': 'mock',
                'message': 'Node sync only available in Production mode'
            }), 400
        
        from slurm_utils import get_slurm_nodes, get_partitions
        
        nodes = get_slurm_nodes()
        partitions = get_partitions()
        
        # 파티션을 그룹으로 변환
        groups = []
        for idx, partition in enumerate(partitions, start=1):
            partition_nodes = [
                n for n in nodes 
                if n.get('partition') == partition['name']
            ]
            
            # IP 주소 생성 (실제로는 scontrol에서 가져와야 함)
            for i, node in enumerate(partition_nodes):
                node['id'] = f"{partition['name']}-{node['hostname']}"
                node['ipAddress'] = f"192.168.{idx}.{i+1}"
                node['groupId'] = idx
            
            total_cores = sum(n['cores'] for n in partition_nodes)
            
            groups.append({
                'id': idx,
                'name': partition['name'].capitalize(),
                'description': f'Partition: {partition["name"]}',
                'color': ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'][idx % 6],
                'qosName': f'{partition["name"]}_qos',
                'partitionName': partition['name'],
                'allowedCoreSizes': [128, 256, 512, 1024],
                'nodeCount': len(partition_nodes),
                'totalCores': total_cores,
                'nodes': partition_nodes
            })
        
        total_nodes = len(nodes)
        total_cores = sum(n['cores'] for n in nodes)
        
        dashboard_config = {
            'clusterName': 'Production Cluster',
            'controllerIp': '192.168.1.1',  # 실제 값으로 교체 필요
            'totalNodes': total_nodes,
            'totalCores': total_cores,
            'groups': groups
        }
        
        return jsonify({
            'success': True,
            'mode': 'production',
            'message': f'Synced {total_nodes} nodes from Slurm',
            'data': dashboard_config
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
```

그런 다음 if __name__ == '__main__': 블록의 "Available Endpoints:" 섹션에 다음 줄을 추가하세요:

```python
    print("  GET  /api/slurm/nodes/real")
    print("  GET  /api/slurm/nodes/<hostname>")
    print("  POST /api/slurm/sync-nodes")
```
