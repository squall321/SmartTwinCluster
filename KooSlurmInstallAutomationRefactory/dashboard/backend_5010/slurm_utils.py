"""
실제 Slurm 노드 정보를 가져오는 유틸리티
"""

import subprocess
import re
from typing import List, Dict, Any

def get_slurm_nodes() -> List[Dict[str, Any]]:
    """
    sinfo 명령으로 실제 Slurm 노드 정보 가져오기 (IP 주소 포함)
    """
    try:
        # sinfo -N -o "%N %C %m %T %P" --noheader
        # %N: NodeName
        # %C: CPUs(A/I/O/T) - Allocated/Idle/Other/Total
        # %m: Memory
        # %T: State
        # %P: Partition
        result = subprocess.run(
            ['sinfo', '-N', '-o', '%N|%C|%m|%T|%P', '--noheader'],
            capture_output=True,
            text=True,
            check=True
        )
        
        nodes = []
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
                
            parts = line.split('|')
            if len(parts) < 5:
                continue
            
            hostname = parts[0].strip()
            cpus_info = parts[1].strip()  # A/I/O/T 형식
            memory = parts[2].strip()
            state = parts[3].strip()
            partition = parts[4].strip().rstrip('*')
            
            # CPUs 파싱 (A/I/O/T -> Total)
            cpu_match = re.search(r'(\d+)/(\d+)/(\d+)/(\d+)', cpus_info)
            if cpu_match:
                allocated, idle, other, total = map(int, cpu_match.groups())
                total_cpus = total
            else:
                total_cpus = 128  # 기본값
            
            # State 매핑
            state_lower = state.lower()
            if 'idle' in state_lower:
                node_state = 'idle'
            elif 'allocated' in state_lower or 'alloc' in state_lower:
                node_state = 'allocated'
            elif 'mix' in state_lower:
                node_state = 'mixed'
            elif 'down' in state_lower or 'drain' in state_lower:
                node_state = 'down'
            else:
                node_state = 'idle'
            
            # Memory 파싱 (MB 단위)
            try:
                memory_mb = int(memory)
            except:
                memory_mb = 262144  # 기본값 256GB
            
            # IP 주소 가져오기 (scontrol 사용)
            ip_address = get_node_ip_address(hostname)
            
            nodes.append({
                'hostname': hostname,
                'ipAddress': ip_address,
                'cores': total_cpus,
                'memory': memory_mb,
                'state': node_state,
                'partition': partition,
                'cpus_allocated': allocated if cpu_match else 0,
                'cpus_idle': idle if cpu_match else total_cpus,
            })
        
        return nodes
        
    except subprocess.CalledProcessError as e:
        print(f"Error running sinfo: {e}")
        return []
    except Exception as e:
        print(f"Error parsing sinfo output: {e}")
        return []


def get_node_ip_address(hostname: str) -> str:
    """
    특정 노드의 IP 주소 가져오기
    """
    try:
        result = subprocess.run(
            ['scontrol', 'show', 'node', hostname],
            capture_output=True,
            text=True,
            check=True,
            timeout=5
        )
        
        # NodeAddr 파싱
        ip_match = re.search(r'NodeAddr=([^\s]+)', result.stdout)
        if ip_match:
            return ip_match.group(1)
        else:
            # NodeAddr가 없으면 hostname 반환
            return hostname
            
    except Exception as e:
        print(f"Warning: Could not get IP for {hostname}: {e}")
        return hostname


def get_node_details(hostname: str) -> Dict[str, Any]:
    """
    특정 노드의 상세 정보 가져오기
    """
    try:
        result = subprocess.run(
            ['scontrol', 'show', 'node', hostname],
            capture_output=True,
            text=True,
            check=True
        )
        
        output = result.stdout
        details = {}
        
        # 정규표현식으로 파싱
        details['hostname'] = hostname
        
        # IP Address (NodeAddr)
        ip_match = re.search(r'NodeAddr=([^\s]+)', output)
        if ip_match:
            details['ipAddress'] = ip_match.group(1)
        else:
            details['ipAddress'] = hostname  # fallback
        
        # CPUs
        cpu_match = re.search(r'CPUTot=(\d+)', output)
        if cpu_match:
            details['cpus'] = int(cpu_match.group(1))
        else:
            details['cpus'] = 128
        
        # Memory
        mem_match = re.search(r'RealMemory=(\d+)', output)
        if mem_match:
            details['memory'] = int(mem_match.group(1))
        else:
            details['memory'] = 262144
        
        # State
        state_match = re.search(r'State=(\w+)', output)
        if state_match:
            details['state'] = state_match.group(1).lower()
        else:
            details['state'] = 'unknown'
        
        # Partitions
        part_match = re.search(r'Partitions=([^\s]+)', output)
        if part_match:
            details['partitions'] = part_match.group(1).split(',')
        else:
            details['partitions'] = []
        
        # Features
        feat_match = re.search(r'AvailableFeatures=([^\s]+)', output)
        if feat_match:
            details['features'] = feat_match.group(1).split(',')
        else:
            details['features'] = []
        
        # Gres (GPU 등)
        gres_match = re.search(r'Gres=([^\s]+)', output)
        if gres_match:
            details['gres'] = gres_match.group(1)
        else:
            details['gres'] = None
        
        return details
        
    except Exception as e:
        print(f"Error getting node details for {hostname}: {e}")
        return {}


def get_partitions() -> List[Dict[str, Any]]:
    """
    Slurm 파티션 정보 가져오기
    """
    try:
        result = subprocess.run(
            ['sinfo', '-o', '%P|%a|%l|%D|%T|%N', '--noheader'],
            capture_output=True,
            text=True,
            check=True
        )
        
        partitions = []
        seen = set()
        
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            
            parts = line.split('|')
            if len(parts) < 6:
                continue
            
            partition_name = parts[0].strip().rstrip('*')
            
            if partition_name in seen:
                continue
            seen.add(partition_name)
            
            partitions.append({
                'name': partition_name,
                'availability': parts[1].strip(),
                'timelimit': parts[2].strip(),
                'nodes': int(parts[3].strip()),
                'state': parts[4].strip(),
                'nodelist': parts[5].strip(),
            })
        
        return partitions
        
    except Exception as e:
        print(f"Error getting partitions: {e}")
        return []
