import { ClusterConfig, SlurmGroup } from '../types';

/**
 * 대시보드 설정을 Slurm 설치용 YAML 형식으로 변환
 */
export const convertToSlurmYAML = (config: ClusterConfig): string => {
  const { clusterName, controllerIp, groups } = config;

  // 컨트롤러 노드 (첫 번째 그룹의 첫 번째 노드를 컨트롤러로 가정)
  const controllerNode = groups[0]?.nodes[0] || {
    hostname: 'controller',
    ipAddress: controllerIp,
    cores: 128,
    memory: 262144,
  };

  // 모든 계산 노드 수집
  const computeNodes: any[] = [];
  groups.forEach(group => {
    group.nodes.forEach(node => {
      if (node.id !== controllerNode.id) {
        computeNodes.push({
          hostname: node.hostname,
          ipAddress: node.ipAddress,
          cores: node.cores,
          memory: node.memory,
          groupId: node.groupId,
          state: node.state,
        });
      }
    });
  });

  // 파티션 설정 생성
  const partitions = groups.map(group => ({
    name: group.partitionName,
    nodes: group.nodes.map(n => n.hostname).join(','),
    default: group.id === 1,
    max_time: '7-00:00:00',
    max_nodes: group.nodeCount,
  }));

  // YAML 생성
  const yaml = `# Slurm Cluster Configuration
# Generated from Dashboard at ${new Date().toISOString()}
# Source: Dashboard Configuration Manager

stage: 1  # 설치 단계 (1: 기본, 2: 고급, 3: 최적화)

cluster_info:
  cluster_name: "${clusterName}"
  domain: "hpc.local"
  admin_email: "admin@${clusterName}.local"
  timezone: "Asia/Seoul"

nodes:
  controller:
    hostname: "${controllerNode.hostname}"
    ip_address: "${controllerNode.ipAddress}"
    ssh_user: "root"
    ssh_port: 22
    ssh_key_path: "~/.ssh/id_rsa"
    os_type: "centos8"
    hardware:
      cpus: ${controllerNode.cores}
      memory_mb: ${controllerNode.memory}
      disk_gb: 500
  
  compute_nodes:
${computeNodes.map((node, idx) => `    - hostname: "${node.hostname}"
      ip_address: "${node.ipAddress}"
      ssh_user: "root"
      ssh_port: 22
      ssh_key_path: "~/.ssh/id_rsa"
      os_type: "centos8"
      hardware:
        cpus: ${node.cores}
        sockets: 1
        cores_per_socket: ${Math.floor(node.cores / 2)}
        threads_per_core: 2
        memory_mb: ${node.memory}
        tmp_disk_mb: 102400`).join('\n')}

network:
  management_network: "${controllerIp.split('.').slice(0, 3).join('.')}.0/24"
  compute_network: "${controllerIp.split('.').slice(0, 3).join('.')}.0/24"
  firewall:
    enabled: true
    ports:
      slurmd: 6818
      slurmctld: 6817
      slurmdbd: 6819
      ssh: 22

slurm_config:
  version: "22.05.8"
  install_path: "/usr/local/slurm"
  config_path: "/usr/local/slurm/etc"
  log_path: "/var/log/slurm"
  partitions:
${partitions.map(p => `    - name: "${p.name}"
      nodes: "${p.nodes}"
      default: ${p.default}
      max_time: "${p.max_time}"
      max_nodes: ${p.max_nodes}`).join('\n')}

users:
  slurm_user: "slurm"
  slurm_uid: 1001
  slurm_gid: 1001
  cluster_users:
    - username: "user01"
      uid: 2001
      gid: 2001
      groups: 
        - "users"
        - "hpc"

shared_storage:
  nfs_server: "${controllerIp}"
  mount_points:
    - source: "/export/home"
      target: "/home"
      options: "rw,sync,no_root_squash"
    - source: "/export/share"
      target: "/share"
      options: "rw,sync,no_root_squash"

# QoS 설정
qos_config:
${groups.map(group => `  - name: "${group.qosName}"
    description: "${group.description}"
    priority: ${1000 + group.id * 100}
    max_tres_per_job: "cpu=${Math.max(...group.allowedCoreSizes)}"
    max_jobs_per_user: 50
    max_wall: "7-00:00:00"`).join('\n')}

# 그룹별 코어 제한
core_limits:
${groups.map(group => `  ${group.name}:
    allowed_sizes: [${group.allowedCoreSizes.join(', ')}]
    partition: "${group.partitionName}"
    qos: "${group.qosName}"`).join('\n')}
`;

  return yaml;
};

/**
 * YAML 파일 다운로드
 */
export const downloadSlurmYAML = (config: ClusterConfig, filename?: string) => {
  const yamlContent = convertToSlurmYAML(config);
  const blob = new Blob([yamlContent], { type: 'text/yaml' });
  const url = URL.createObjectURL(blob);
  
  const a = document.createElement('a');
  a.href = url;
  a.download = filename || `slurm-cluster-${new Date().toISOString().split('T')[0]}.yaml`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
};

/**
 * Slurm YAML을 클립보드에 복사
 */
export const copySlurmYAMLToClipboard = async (config: ClusterConfig): Promise<boolean> => {
  try {
    const yamlContent = convertToSlurmYAML(config);
    await navigator.clipboard.writeText(yamlContent);
    return true;
  } catch (error) {
    console.error('Failed to copy to clipboard:', error);
    return false;
  }
};
