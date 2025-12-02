#!/usr/bin/env python3
"""
Scratch Nodes API 함수 개선
Production 모드에서 더 명확한 로깅 추가
"""

# 이 코드를 app.py의 @app.route('/api/storage/scratch/nodes') 함수로 교체하세요

@app.route('/api/storage/scratch/nodes', methods=['GET'])
def get_scratch_nodes():
    """모든 노드의 /scratch 정보"""
    try:
        if MOCK_MODE:
            # Mock 데이터
            print("🎭 Scratch Nodes: Using mock data (MOCK_MODE=true)")
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': []  # 프론트에서 mock 데이터 사용
            })
        else:
            # Production: Slurm 노드 목록 가져오기
            print("=" * 80)
            print("🚀 Scratch Nodes: Production Mode - Querying real nodes")
            print("=" * 80)
            
            nodes = get_storage_nodes()
            
            if not nodes:
                print("⚠️  No nodes found from Slurm (sinfo)")
                print("   Possible causes:")
                print("   1. Slurm is not running (check: systemctl status slurmctld)")
                print("   2. sinfo command not in PATH (check: which sinfo)")
                print("   3. No compute nodes configured")
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': [],
                    'message': 'No nodes found from Slurm. Check if slurmctld is running.'
                })
            
            print(f"✅ Found {len(nodes)} node(s) from Slurm:")
            for i, node in enumerate(nodes, 1):
                print(f"   {i}. {node}")
            print("")
            
            scratch_data = []
            
            for node_idx, node in enumerate(nodes, 1):
                print(f"[{node_idx}/{len(nodes)}] Processing node: {node}")
                
                # 원격 노드에서 /scratch 정보 가져오기
                print(f"   → SSH: df -B1 /scratch ...")
                df_output = run_remote_command(node, "df -B1 /scratch | tail -1")
                
                if not df_output:
                    print(f"   ✗ SSH failed or /scratch not mounted on {node}")
                    print(f"     Troubleshoot:")
                    print(f"       ssh {node} 'echo test'")
                    print(f"       ssh {node} 'df -h /scratch'")
                    continue
                
                parts = df_output.split()
                if len(parts) >= 4:
                    total_bytes = int(parts[1])
                    used_bytes = int(parts[2])
                    avail_bytes = int(parts[3])
                    usage_percent = (used_bytes / total_bytes * 100) if total_bytes > 0 else 0
                    
                    print(f"   ✓ Disk: {format_size(used_bytes)} / {format_size(total_bytes)} ({usage_percent:.1f}%)")
                    
                    # /scratch 디렉토리 목록
                    print(f"   → SSH: ls -la /scratch ...")
                    ls_output = run_remote_command(node, "ls -la /scratch | tail -n +2")
                    directories = []
                    
                    if ls_output:
                        for line in ls_output.strip().split('\n'):
                            if line and line.startswith('d'):
                                parts_ls = line.split()
                                if len(parts_ls) >= 9:
                                    dir_name = parts_ls[8]
                                    if not dir_name.startswith('.'):
                                        directories.append({
                                            'id': f"{node}-{dir_name}",
                                            'name': dir_name,
                                            'path': f"/scratch/{dir_name}",
                                            'owner': parts_ls[2],
                                            'group': parts_ls[3],
                                            'size': 'Calculating...',
                                            'sizeBytes': 0,
                                            'fileCount': 0,
                                            'createdAt': f"{parts_ls[5]} {parts_ls[6]}",
                                            'lastModified': f"{parts_ls[5]} {parts_ls[6]}"
                                        })
                        print(f"   ✓ Found {len(directories)} director{'y' if len(directories) == 1 else 'ies'}")
                    else:
                        print(f"   ✗ Could not list /scratch directories")
                    
                    scratch_data.append({
                        'nodeId': node,
                        'nodeName': node,
                        'totalSpace': format_size(total_bytes),
                        'totalSpaceBytes': total_bytes,
                        'usedSpace': format_size(used_bytes),
                        'usedSpaceBytes': used_bytes,
                        'availableSpace': format_size(avail_bytes),
                        'availableSpaceBytes': avail_bytes,
                        'usagePercent': round(usage_percent, 1),
                        'fileCount': len(directories),
                        'directories': directories,
                        'status': 'online',
                        'lastUpdated': datetime.now().isoformat()
                    })
                    print(f"   ✅ Node {node} processed successfully")
                else:
                    print(f"   ✗ Invalid df output format")
                
                print("")
            
            print("=" * 80)
            print(f"✅ Scratch Nodes Summary:")
            print(f"   Total nodes from Slurm: {len(nodes)}")
            print(f"   Successfully queried: {len(scratch_data)}")
            print(f"   Failed: {len(nodes) - len(scratch_data)}")
            print("=" * 80)
            print("")
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': scratch_data
            })
            
    except Exception as e:
        print(f"❌ Error in get_scratch_nodes: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
