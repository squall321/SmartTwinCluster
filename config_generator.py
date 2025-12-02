#!/usr/bin/env python3
"""
Slurm 설치 자동화를 위한 설정 파일 생성기
단계별 설정 파일 템플릿을 생성합니다.
"""

import yaml
from datetime import datetime
from pathlib import Path
import json


class SlurmConfigGenerator:
    """Slurm 설정 파일 생성 클래스"""
    
    def __init__(self):
        self.config_dir = Path("configs")
        self.templates_dir = Path("templates")
        self.examples_dir = Path("examples")
        
        # 디렉토리 생성
        self.config_dir.mkdir(exist_ok=True)
        self.templates_dir.mkdir(exist_ok=True)
        self.examples_dir.mkdir(exist_ok=True)
    
    def generate_stage1_template(self):
        """1단계: 기본 Slurm 설치 템플릿"""
        template = {
            "cluster_info": {
                "cluster_name": "{{ CLUSTER_NAME }}",
                "domain": "{{ DOMAIN }}",
                "admin_email": "{{ ADMIN_EMAIL }}",
                "timezone": "{{ TIMEZONE }}"
            },
            "nodes": {
                "controller": {
                    "hostname": "{{ CONTROLLER_HOSTNAME }}",
                    "ip_address": "{{ CONTROLLER_IP }}",
                    "ssh_user": "{{ SSH_USER }}",
                    "ssh_port": 22,
                    "ssh_key_path": "{{ SSH_KEY_PATH }}",
                    "os_type": "{{ OS_TYPE }}",  # centos7, centos8, ubuntu18, ubuntu20, rhel8
                    "hardware": {
                        "cpus": "{{ CONTROLLER_CPUS }}",
                        "memory_mb": "{{ CONTROLLER_MEMORY }}",
                        "disk_gb": "{{ CONTROLLER_DISK }}"
                    }
                },
                "compute_nodes": [
                    {
                        "hostname": "{{ COMPUTE_NODE_HOSTNAME }}",
                        "ip_address": "{{ COMPUTE_NODE_IP }}",
                        "ssh_user": "{{ SSH_USER }}",
                        "ssh_port": 22,
                        "ssh_key_path": "{{ SSH_KEY_PATH }}",
                        "os_type": "{{ OS_TYPE }}",
                        "hardware": {
                            "cpus": "{{ COMPUTE_CPUS }}",
                            "sockets": "{{ COMPUTE_SOCKETS }}",
                            "cores_per_socket": "{{ CORES_PER_SOCKET }}",
                            "threads_per_core": "{{ THREADS_PER_CORE }}",
                            "memory_mb": "{{ COMPUTE_MEMORY }}",
                            "tmp_disk_mb": "{{ COMPUTE_TMP_DISK }}",
                            "gpu": {
                                "type": "{{ GPU_TYPE }}",  # none, nvidia, amd
                                "count": "{{ GPU_COUNT }}"
                            }
                        }
                    }
                ]
            },
            "network": {
                "management_network": "{{ MGMT_NETWORK }}",
                "compute_network": "{{ COMPUTE_NETWORK }}",
                "firewall": {
                    "enabled": True,
                    "ports": {
                        "slurmd": 6818,
                        "slurmctld": 6817,
                        "slurmdbd": 6819,
                        "ssh": 22
                    }
                }
            },
            "slurm_config": {
                "version": "{{ SLURM_VERSION }}",
                "install_path": "/usr/local/slurm",
                "config_path": "/usr/local/slurm/etc",
                "log_path": "/var/log/slurm",
                "partitions": [
                    {
                        "name": "{{ PARTITION_NAME }}",
                        "nodes": "{{ PARTITION_NODES }}",
                        "default": True,
                        "max_time": "{{ MAX_TIME }}",
                        "max_nodes": "{{ MAX_NODES }}"
                    }
                ]
            },
            "users": {
                "slurm_user": "slurm",
                "slurm_uid": 1001,
                "slurm_gid": 1001,
                "cluster_users": [
                    {
                        "username": "{{ USER_NAME }}",
                        "uid": "{{ USER_UID }}",
                        "gid": "{{ USER_GID }}",
                        "groups": ["{{ USER_GROUPS }}"]
                    }
                ]
            },
            "shared_storage": {
                "nfs_server": "{{ NFS_SERVER }}",
                "mount_points": [
                    {
                        "source": "{{ NFS_HOME_PATH }}",
                        "target": "/home",
                        "options": "rw,sync,hard,intr"
                    },
                    {
                        "source": "{{ NFS_SHARE_PATH }}",
                        "target": "/share",
                        "options": "rw,sync,hard,intr"
                    }
                ]
            }
        }
        
        return template
    
    def generate_stage2_template(self):
        """2단계: 고급 기능 템플릿"""
        template = {
            "database": {
                "enabled": True,
                "host": "{{ DB_HOST }}",
                "port": 3306,
                "database_name": "slurm_acct_db",
                "username": "{{ DB_USER }}",
                "password": "{{ DB_PASSWORD }}",
                "backup_schedule": "{{ DB_BACKUP_SCHEDULE }}"
            },
            "monitoring": {
                "ganglia": {
                    "enabled": "{{ GANGLIA_ENABLED }}",
                    "gmetad_host": "{{ GANGLIA_HOST }}"
                },
                "prometheus": {
                    "enabled": "{{ PROMETHEUS_ENABLED }}",
                    "port": 9090,
                    "node_exporter": True
                },
                "grafana": {
                    "enabled": "{{ GRAFANA_ENABLED }}",
                    "port": 3000
                }
            },
            "high_availability": {
                "controller_ha": {
                    "enabled": "{{ HA_ENABLED }}",
                    "primary_controller": "{{ PRIMARY_CONTROLLER }}",
                    "backup_controller": "{{ BACKUP_CONTROLLER }}",
                    "virtual_ip": "{{ VIRTUAL_IP }}"
                }
            },
            "security": {
                "munge": {
                    "key_rotation_days": "{{ MUNGE_KEY_ROTATION }}",
                    "key_backup_location": "{{ MUNGE_BACKUP_PATH }}"
                },
                "ssl": {
                    "enabled": "{{ SSL_ENABLED }}",
                    "cert_path": "{{ SSL_CERT_PATH }}",
                    "key_path": "{{ SSL_KEY_PATH }}"
                }
            },
            "environment_modules": {
                "enabled": "{{ MODULES_ENABLED }}",
                "type": "{{ MODULES_TYPE }}",  # modules, lmod
                "modulefiles_path": "{{ MODULEFILES_PATH }}",
                "default_modules": [
                    "{{ DEFAULT_MODULE_1 }}",
                    "{{ DEFAULT_MODULE_2 }}"
                ]
            }
        }
        
        return template
    
    def generate_stage3_template(self):
        """3단계: 운영 최적화 템플릿"""
        template = {
            "performance_tuning": {
                "kernel_parameters": {
                    "vm.swappiness": "{{ SWAPPINESS }}",
                    "vm.dirty_ratio": "{{ DIRTY_RATIO }}",
                    "net.core.rmem_max": "{{ RMEM_MAX }}",
                    "net.core.wmem_max": "{{ WMEM_MAX }}"
                },
                "ulimits": {
                    "nofile": "{{ ULIMIT_NOFILE }}",
                    "nproc": "{{ ULIMIT_NPROC }}",
                    "memlock": "{{ ULIMIT_MEMLOCK }}"
                }
            },
            "power_management": {
                "enabled": "{{ POWER_MGMT_ENABLED }}",
                "idle_timeout": "{{ IDLE_TIMEOUT }}",
                "suspend_program": "{{ SUSPEND_PROGRAM }}",
                "resume_program": "{{ RESUME_PROGRAM }}",
                "ipmi": {
                    "enabled": "{{ IPMI_ENABLED }}",
                    "username": "{{ IPMI_USER }}",
                    "password": "{{ IPMI_PASSWORD }}"
                }
            },
            "container_support": {
                "singularity": {
                    "enabled": "{{ SINGULARITY_ENABLED }}",
                    "version": "{{ SINGULARITY_VERSION }}",
                    "image_path": "{{ SINGULARITY_IMAGE_PATH }}"
                }
            },
            "parallel_filesystems": {
                "lustre": {
                    "enabled": "{{ LUSTRE_ENABLED }}",
                    "mds_servers": ["{{ LUSTRE_MDS }}"],
                    "oss_servers": ["{{ LUSTRE_OSS }}"],
                    "mount_point": "{{ LUSTRE_MOUNT }}"
                },
                "beegfs": {
                    "enabled": "{{ BEEGFS_ENABLED }}",
                    "mgmt_server": "{{ BEEGFS_MGMT }}",
                    "mount_point": "{{ BEEGFS_MOUNT }}"
                }
            },
            "backup_and_recovery": {
                "config_backup": {
                    "enabled": True,
                    "schedule": "{{ BACKUP_SCHEDULE }}",
                    "retention_days": "{{ BACKUP_RETENTION }}",
                    "backup_path": "{{ BACKUP_PATH }}"
                },
                "disaster_recovery": {
                    "recovery_site": "{{ DR_SITE }}",
                    "rpo_hours": "{{ RPO_HOURS }}",
                    "rto_hours": "{{ RTO_HOURS }}"
                }
            }
        }
        
        return template
    
    def generate_complete_template(self):
        """전체 단계 통합 템플릿"""
        stage1 = self.generate_stage1_template()
        stage2 = self.generate_stage2_template()
        stage3 = self.generate_stage3_template()
        
        complete_template = {
            "# Slurm 클러스터 자동 설치 설정 파일": None,
            "# 생성일": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "# 설정 단계": "1: 기본설치, 2: 고급기능, 3: 운영최적화",
            "stage": "{{ INSTALL_STAGE }}",  # 1, 2, 3
            **stage1,
            **stage2,
            **stage3
        }
        
        return complete_template
    
    def generate_2node_example(self):
        """2노드 시스템 예시 설정"""
        example = {
            "# 2노드 Slurm 클러스터 예시 설정": None,
            "# 헤드노드 1개 + 계산노드 1개": None,
            "stage": 1,
            
            "cluster_info": {
                "cluster_name": "mini-cluster",
                "domain": "hpc.local",
                "admin_email": "admin@hpc.local",
                "timezone": "Asia/Seoul"
            },
            
            "nodes": {
                "controller": {
                    "hostname": "head01",
                    "ip_address": "192.168.1.10",
                    "ssh_user": "root",
                    "ssh_port": 22,
                    "ssh_key_path": "~/.ssh/id_rsa",
                    "os_type": "centos8",
                    "hardware": {
                        "cpus": 8,
                        "memory_mb": 16384,
                        "disk_gb": 500
                    }
                },
                
                "compute_nodes": [
                    {
                        "hostname": "compute01",
                        "ip_address": "192.168.1.20",
                        "ssh_user": "root",
                        "ssh_port": 22,
                        "ssh_key_path": "~/.ssh/id_rsa",
                        "os_type": "centos8",
                        "hardware": {
                            "cpus": 16,
                            "sockets": 1,
                            "cores_per_socket": 8,
                            "threads_per_core": 2,
                            "memory_mb": 32768,
                            "tmp_disk_mb": 102400,
                            "gpu": {
                                "type": "nvidia",
                                "count": 1
                            }
                        }
                    }
                ]
            },
            
            "network": {
                "management_network": "192.168.1.0/24",
                "compute_network": "192.168.1.0/24",
                "firewall": {
                    "enabled": True,
                    "ports": {
                        "slurmd": 6818,
                        "slurmctld": 6817,
                        "slurmdbd": 6819,
                        "ssh": 22
                    }
                }
            },
            
            "slurm_config": {
                "version": "22.05.8",
                "install_path": "/usr/local/slurm",
                "config_path": "/usr/local/slurm/etc",
                "log_path": "/var/log/slurm",
                "partitions": [
                    {
                        "name": "gpu",
                        "nodes": "compute01",
                        "default": True,
                        "max_time": "7-00:00:00",
                        "max_nodes": 1
                    }
                ]
            },
            
            "users": {
                "slurm_user": "slurm",
                "slurm_uid": 1001,
                "slurm_gid": 1001,
                "cluster_users": [
                    {
                        "username": "user01",
                        "uid": 2001,
                        "gid": 2001,
                        "groups": ["users", "hpc"]
                    },
                    {
                        "username": "user02",
                        "uid": 2002,
                        "gid": 2001,
                        "groups": ["users", "hpc"]
                    }
                ]
            },
            
            "shared_storage": {
                "nfs_server": "192.168.1.10",
                "mount_points": [
                    {
                        "source": "/export/home",
                        "target": "/home",
                        "options": "rw,sync,hard,intr"
                    },
                    {
                        "source": "/export/share",
                        "target": "/share",
                        "options": "rw,sync,hard,intr"
                    }
                ]
            },
            
            # Stage 2 기본값 (비활성화)
            "database": {
                "enabled": False,
                "host": "localhost",
                "port": 3306,
                "database_name": "slurm_acct_db",
                "username": "slurm",
                "password": "changeme",
                "backup_schedule": "0 2 * * *"
            },
            
            "monitoring": {
                "ganglia": {"enabled": False},
                "prometheus": {"enabled": False},
                "grafana": {"enabled": False}
            },
            
            # Stage 3 기본값 (비활성화)
            "performance_tuning": {
                "kernel_parameters": {
                    "vm.swappiness": 1,
                    "vm.dirty_ratio": 15
                }
            },
            
            "power_management": {"enabled": False},
            "container_support": {"singularity": {"enabled": False}},
            "parallel_filesystems": {
                "lustre": {"enabled": False},
                "beegfs": {"enabled": False}
            }
        }
        
        return example
    
    def save_template(self, template, filename):
        """템플릿을 YAML 파일로 저장"""
        filepath = self.templates_dir / filename
        with open(filepath, 'w', encoding='utf-8') as f:
            yaml.dump(template, f, default_flow_style=False, 
                     allow_unicode=True, sort_keys=False)
        print(f"✅ 템플릿 생성됨: {filepath}")
    
    def save_example(self, config, filename):
        """예시 설정을 YAML 파일로 저장"""
        filepath = self.examples_dir / filename
        with open(filepath, 'w', encoding='utf-8') as f:
            yaml.dump(config, f, default_flow_style=False, 
                     allow_unicode=True, sort_keys=False)
        print(f"✅ 예시 파일 생성됨: {filepath}")
    
    def generate_all_templates(self):
        """모든 템플릿과 예시 파일 생성"""
        print("🚀 Slurm 설정 파일 템플릿 생성 시작...\n")
        
        # 단계별 템플릿 생성
        self.save_template(self.generate_stage1_template(), "stage1_basic.yaml")
        self.save_template(self.generate_stage2_template(), "stage2_advanced.yaml")
        self.save_template(self.generate_stage3_template(), "stage3_optimization.yaml")
        self.save_template(self.generate_complete_template(), "complete_template.yaml")
        
        # 예시 파일 생성
        self.save_example(self.generate_2node_example(), "2node_example.yaml")
        
        print(f"\n📁 생성된 파일 위치:")
        print(f"  - 템플릿: {self.templates_dir.absolute()}")
        print(f"  - 예시: {self.examples_dir.absolute()}")
        
        return True


def main():
    """메인 함수"""
    print("=" * 60)
    print("Slurm 클러스터 설치 자동화 - 설정 파일 생성기")
    print("=" * 60)
    
    generator = SlurmConfigGenerator()
    generator.generate_all_templates()
    
    print("\n✅ 설정 파일 생성이 완료되었습니다!")
    print("\n📋 다음 단계:")
    print("  1. examples/2node_example.yaml 파일을 참고하여 실제 환경에 맞게 수정")
    print("  2. 설정 파일을 기반으로 Slurm 설치 스크립트 실행")
    print("  3. 단계별로 기능을 확장")


if __name__ == "__main__":
    main()
