#!/usr/bin/env python3
"""
설정 파일 자동 수정 스크립트
my_cluster.yaml의 오류를 자동으로 수정합니다.
"""

import yaml
import sys
from pathlib import Path


def fix_config():
    """설정 파일 오류 자동 수정"""
    config_file = Path("my_cluster.yaml")
    backup_file = Path("my_cluster.yaml.backup")
    
    print("🔧 설정 파일 자동 수정 시작...")
    
    # 백업 생성
    if config_file.exists():
        print(f"📦 백업 생성: {backup_file}")
        with open(config_file, 'r', encoding='utf-8') as f:
            backup_content = f.read()
        with open(backup_file, 'w', encoding='utf-8') as f:
            f.write(backup_content)
    
    # 수정된 설정 파일 작성
    fixed_config = {
        'config_version': '1.0',
        'stage': 3,  # Stage 3으로 변경 (컨테이너 지원 포함)
        
        'cluster_info': {
            'cluster_name': 'mini-cluster',
            'domain': 'hpc.local',
            'admin_email': 'admin@hpc.local',
            'timezone': 'Asia/Seoul'
        },
        
        'installation': {
            'install_method': 'package',
            'offline_mode': False,
            'package_cache_path': '/var/cache/slurm_packages',
            'compile_options': '--with-pmix --with-hwloc'
        },
        
        'nodes': {
            'controller': {
                'hostname': 'smarttwincluster',
                'ip_address': '192.168.122.1',
                'ssh_user': 'koopark',
                'ssh_port': 22,
                'ssh_key_path': '~/.ssh/id_rsa',
                'os_type': 'ubuntu22',
                'node_type': 'controller',
                'hardware': {
                    'cpus': 8,
                    'memory_mb': 4096,
                    'disk_gb': 500
                }
            },
            'compute_nodes': [
                {
                    'hostname': 'node001',
                    'ip_address': '192.168.122.90',
                    'ssh_user': 'koopark',
                    'ssh_port': 22,
                    'ssh_key_path': '~/.ssh/id_rsa',
                    'os_type': 'ubuntu22',
                    'node_type': 'compute',
                    'hardware': {
                        'cpus': 2,
                        'sockets': 1,
                        'cores_per_socket': 2,
                        'threads_per_core': 1,
                        'memory_mb': 4096,
                        'tmp_disk_mb': 102400
                    }
                },
                {
                    'hostname': 'node002',
                    'ip_address': '192.168.122.103',
                    'ssh_user': 'koopark',
                    'ssh_port': 22,
                    'ssh_key_path': '~/.ssh/id_rsa',
                    'os_type': 'ubuntu22',
                    'node_type': 'compute',
                    'hardware': {
                        'cpus': 2,
                        'sockets': 1,
                        'cores_per_socket': 2,
                        'threads_per_core': 1,
                        'memory_mb': 4096,
                        'tmp_disk_mb': 102400
                    }
                }
            ]
        },
        
        'network': {
            'management_network': '192.168.122.0/24',
            'compute_network': '192.168.122.0/24',
            'firewall': {
                'enabled': True,
                'ports': {
                    'slurmd': 6818,
                    'slurmctld': 6817,
                    'slurmdbd': 6819,
                    'ssh': 22
                }
            }
        },
        
        'time_synchronization': {
            'enabled': True,
            'ntp_servers': [
                'time.google.com',
                'time.cloudflare.com',
                'pool.ntp.org'
            ],
            'timezone': 'Asia/Seoul'
        },
        
        'slurm_config': {
            'version': '22.05.8',
            'install_path': '/usr/local/slurm',
            'config_path': '/usr/local/slurm/etc',
            'log_path': '/var/log/slurm',
            'spool_path': '/var/spool/slurm',
            'state_save_location': '/var/spool/slurm/state',
            'scheduler': {
                'type': 'sched/backfill',
                'max_job_count': 10000,
                'max_array_size': 1000
            },
            'accounting': {
                'storage_type': 'accounting_storage/none',
                'storage_host': ''
            },
            'partitions': [
                {
                    'name': 'normal',
                    'nodes': 'node[1-2]',
                    'default': True,
                    'max_time': '7-00:00:00',
                    'max_nodes': 2,
                    'state': 'UP'
                },
                {
                    'name': 'debug',
                    'nodes': 'node1',
                    'default': False,
                    'max_time': '00:30:00',
                    'max_nodes': 1,
                    'state': 'UP'
                }
            ]
        },
        
        'users': {
            'slurm_user': 'slurm',
            'slurm_uid': 1001,
            'slurm_gid': 1001,
            'munge_user': 'munge',
            'munge_uid': 1002,
            'munge_gid': 1002,
            'cluster_users': [
                {
                    'username': 'user01',
                    'uid': 2001,
                    'gid': 2001,
                    'groups': ['users', 'hpc']
                },
                {
                    'username': 'user02',
                    'uid': 2002,
                    'gid': 2001,
                    'groups': ['users', 'hpc']
                }
            ]
        },
        
        'shared_storage': {
            'nfs_server': '192.168.122.1',
            'mount_points': [
                {
                    'source': '/export/home',
                    'target': '/home',
                    'options': 'rw,sync,hard,intr'
                },
                {
                    'source': '/export/share',
                    'target': '/share',
                    'options': 'rw,sync,hard,intr'
                },
                {
                    'source': '/export/apps',
                    'target': '/apps',
                    'options': 'ro,sync,hard,intr'
                }
            ]
        },
        
        'database': {
            'enabled': False
        },
        
        'monitoring': {
            'ganglia': {'enabled': False},
            'prometheus': {'enabled': False},
            'grafana': {'enabled': False}
        },
        
        'high_availability': {
            'controller_ha': {'enabled': False}
        },
        
        'security': {
            'munge': {'key_rotation_days': 30},
            'selinux': {'enabled': True, 'mode': 'permissive'}
        },
        
        'environment_modules': {
            'enabled': False
        },
        
        'performance_tuning': {
            'enabled': False
        },
        
        'power_management': {
            'enabled': False
        },
        
        # 🎯 Apptainer 활성화 + 이미지 관리
        'container_support': {
            'apptainer': {
                'enabled': True,
                'version': '1.2.5',
                'install_path': '/usr/local',
                'image_path': '/share/apptainer/images',  # 중앙 저장소
                'cache_path': '/tmp/apptainer',
                'scratch_image_path': '/scratch/apptainer/images',  # 로컬 복사본
                'bind_paths': ['/home', '/share', '/scratch', '/tmp'],
                'auto_sync_images': True  # 자동 동기화 활성화
            },
            'singularity': {
                'enabled': False
            },
            'docker': {
                'enabled': False
            }
        },
        
        # 🎯 MPI 라이브러리 자동 설치
        'mpi_support': {
            'enabled': True,
            'mpi_type': 'openmpi',  # openmpi 또는 mpich
            'version': 'latest',
            'install_path': '/usr/local/mpi',
            'auto_configure': True
        },
        
        'parallel_filesystems': {
            'lustre': {'enabled': False},
            'beegfs': {'enabled': False}
        },
        
        'gpu_computing': {
            'nvidia': {'enabled': False},
            'amd': {'enabled': False}
        },
        
        'backup_and_recovery': {
            'config_backup': {
                'enabled': True,
                'schedule': '0 3 * * 0',
                'retention_days': 30,
                'backup_path': '/backup/slurm'
            }
        }
    }
    
    # YAML 저장
    with open(config_file, 'w', encoding='utf-8') as f:
        yaml.dump(fixed_config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    print("✅ 설정 파일 수정 완료!")
    print("\n📋 주요 변경 사항:")
    print("   ✅ compute_nodes 중복 제거")
    print("   ✅ stage를 3으로 변경 (컨테이너 지원)")
    print("   ✅ Apptainer 활성화")
    print("   ✅ MPI 지원 활성화")
    print("   ✅ 파티션 설정 수정 (normal, debug)")
    print("   ✅ Apptainer 이미지 경로 설정:")
    print(f"      - 중앙 저장소: /share/apptainer/images")
    print(f"      - 로컬 캐시: /scratch/apptainer/images")
    print("\n💡 백업 파일: my_cluster.yaml.backup")


if __name__ == '__main__':
    try:
        fix_config()
    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        sys.exit(1)
