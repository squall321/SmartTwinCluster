#!/usr/bin/env python3
"""
로컬 /scratch 정보만 표시하는 대체 함수
SSH 접근이 불가능할 때 사용
"""

# backend/app.py의 get_scratch_nodes 함수를 이것으로 교체

@app.route('/api/storage/scratch/nodes', methods=['GET'])
def get_scratch_nodes():
    """모든 노드의 /scratch 정보 (SSH 실패 시 로컬만)"""
    try:
        if MOCK_MODE:
            print("🎭 Scratch Nodes: Using mock data")
            return jsonify({
                'success': True,
                'mode': 'mock',
                'data': []
            })
        else:
            print("=" * 80)
            print("🚀 Scratch Nodes: Production Mode")
            print("=" * 80)
            
            nodes = get_storage_nodes()  # sinfo로 노드 목록
            
            if not nodes:
                print("⚠️  No nodes found from Slurm")
                return jsonify({
                    'success': True,
                    'mode': 'production',
                    'data': [],
                    'message': 'No nodes found'
                })
            
            print(f"✅ Found {len(nodes)} node(s) from Slurm:")
            for i, node in enumerate(nodes, 1):
                print(f"   {i}. {node}")
            print("")
            
            scratch_data = []
            ssh_failed_nodes = []
            
            for node_idx, node in enumerate(nodes, 1):
                print(f"[{node_idx}/{len(nodes)}] Processing: {node}")
                
                # SSH로 원격 접근 시도
                df_output = run_remote_command(node, "df -B1 /scratch | tail -1")
                
                if df_output:
                    # SSH 성공: 원격 정보 사용
                    parts = df_output.split()
                    if len(parts) >= 4:
                        total_bytes = int(parts[1])
                        used_bytes = int(parts[2])
                        avail_bytes = int(parts[3])
                        usage_percent = (used_bytes / total_bytes * 100) if total_bytes > 0 else 0
                        
                        print(f"   ✓ SSH 성공: {format_size(used_bytes)} / {format_size(total_bytes)}")
                        
                        # 디렉토리 목록
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
                    # SSH 실패: 로컬 /scratch 정보로 대체 (관리 노드인 경우만)
                    print(f"   ✗ SSH failed to {node}")
                    ssh_failed_nodes.append(node)
                    
                    # 현재 노드(관리 노드)의 /scratch 정보라도 보여주기
                    import socket
                    current_hostname = socket.gethostname()
                    
                    if node in [current_hostname, 'localhost', '127.0.0.1']:
                        print(f"   → Falling back to local /scratch (management node)")
                        
                        scratch_path = '/scratch'
                        if os.path.exists(scratch_path):
                            try:
                                # 로컬 디스크 사용량
                                stat_info = os.statvfs(scratch_path)
                                total_bytes = stat_info.f_blocks * stat_info.f_frsize
                                used_bytes = (stat_info.f_blocks - stat_info.f_bfree) * stat_info.f_frsize
                                avail_bytes = stat_info.f_bavail * stat_info.f_frsize
                                usage_percent = (used_bytes / total_bytes * 100) if total_bytes > 0 else 0
                                
                                # 로컬 디렉토리 목록
                                directories = []
                                for entry in os.listdir(scratch_path):
                                    full_path = os.path.join(scratch_path, entry)
                                    if os.path.isdir(full_path) and not entry.startswith('.'):
                                        stat = os.stat(full_path)
                                        directories.append({
                                            'id': f"{node}-{entry}",
                                            'name': entry,
                                            'path': f"/scratch/{entry}",
                                            'owner': pwd.getpwuid(stat.st_uid).pw_name,
                                            'group': grp.getgrgid(stat.st_gid).gr_name,
                                            'size': 'Calculating...',
                                            'sizeBytes': 0,
                                            'fileCount': 0,
                                            'createdAt': datetime.fromtimestamp(stat.st_ctime).strftime('%b %d'),
                                            'lastModified': datetime.fromtimestamp(stat.st_mtime).strftime('%b %d')
                                        })
                                
                                scratch_data.append({
                                    'nodeId': node,
                                    'nodeName': f"{node} (local)",
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
                                print(f"   ✅ Local /scratch info added")
                            except Exception as e:
                                print(f"   ✗ Failed to read local /scratch: {e}")
                        else:
                            print(f"   ✗ /scratch not found locally")
                    else:
                        print(f"   ⚠️  Skipping - not management node")
                
                print("")
            
            print("=" * 80)
            print(f"✅ Scratch Nodes Summary:")
            print(f"   Total nodes: {len(nodes)}")
            print(f"   Successfully queried: {len(scratch_data)}")
            print(f"   SSH failed: {len(ssh_failed_nodes)}")
            if ssh_failed_nodes:
                print(f"   Failed nodes: {', '.join(ssh_failed_nodes)}")
                print(f"")
                print(f"⚠️  SSH Setup Required:")
                print(f"   1. ssh-keygen -t rsa -b 4096")
                for node in ssh_failed_nodes:
                    print(f"   2. ssh-copy-id {node}")
            print("=" * 80)
            print("")
            
            return jsonify({
                'success': True,
                'mode': 'production',
                'data': scratch_data,
                'warnings': {
                    'ssh_failed_nodes': ssh_failed_nodes,
                    'message': 'Some nodes are not accessible via SSH. Only showing locally accessible data.'
                } if ssh_failed_nodes else None
            })
            
    except Exception as e:
        print(f"❌ Error in get_scratch_nodes: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
