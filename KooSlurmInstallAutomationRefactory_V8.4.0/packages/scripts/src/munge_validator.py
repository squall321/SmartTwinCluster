#!/usr/bin/env python3
"""
Munge 검증 모듈
Phase 1-3: Munge 키 배포 검증 강화
"""

import time
from typing import Dict, List, Any
from ssh_manager import SSHManager


class MungeValidator:
    """Munge 인증 시스템 설정 및 검증"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.slurm_user = config['users']['slurm_user']
    
    def setup_and_validate_munge(self) -> bool:
        """Munge 설정 및 전체 검증"""
        print("\n🔐 Munge 인증 시스템 설정 중...")
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        compute_nodes = self.config['nodes']['compute_nodes']
        
        # 1. 컨트롤러에서 Munge 설치 및 키 생성
        if not self._setup_munge_on_controller(controller_hostname):
            return False
        
        # 2. 계산 노드들에 Munge 배포
        if not self._distribute_munge_to_nodes(controller_hostname, compute_nodes):
            return False
        
        # 3. 전체 검증
        if not self._validate_all_nodes(controller_hostname, compute_nodes):
            return False
        
        print("✅ Munge 인증 시스템 설정 및 검증 완료\n")
        return True
    
    def _setup_munge_on_controller(self, hostname: str) -> bool:
        """컨트롤러에서 Munge 설정"""
        print(f"🔑 {hostname}: Munge 설치 및 키 생성...")
        
        commands = [
            # Munge 설치 (OS에 따라 자동 선택)
            "yum install -y munge munge-libs munge-devel 2>/dev/null || apt-get install -y munge 2>/dev/null",
            
            # 기존 키 백업
            "[ -f /etc/munge/munge.key ] && cp /etc/munge/munge.key /etc/munge/munge.key.backup.$(date +%Y%m%d_%H%M%S) || true",
            
            # 새 키 생성
            "create-munge-key -f 2>/dev/null || /usr/sbin/create-munge-key -f 2>/dev/null || dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key",
            
            # 권한 설정
            "chown munge:munge /etc/munge/munge.key",
            "chmod 400 /etc/munge/munge.key",
            
            # 서비스 활성화 및 시작
            "systemctl enable munge",
            "systemctl restart munge",
            "systemctl status munge --no-pager"
        ]
        
        for cmd in commands:
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                hostname, cmd, show_output=False
            )
            
            if "status munge" in cmd and exit_code == 0:
                print(f"  ✅ {hostname}: Munge 서비스 실행 중")
        
        # 자체 검증
        time.sleep(2)
        exit_code, stdout, stderr = self.ssh_manager.execute_command(
            hostname,
            "munge -n | unmunge",
            show_output=False
        )
        
        if exit_code == 0:
            print(f"  ✅ {hostname}: Munge 자체 검증 성공")
            return True
        else:
            print(f"  ❌ {hostname}: Munge 자체 검증 실패")
            print(f"     오류: {stderr}")
            return False
    
    def _distribute_munge_to_nodes(self, controller_hostname: str, compute_nodes: List[Dict]) -> bool:
        """계산 노드들에 Munge 키 배포"""
        print(f"\n📤 Munge 키 배포 중...")
        
        # 1. 컨트롤러에서 키 내용 읽기
        exit_code, key_content, stderr = self.ssh_manager.execute_command(
            controller_hostname,
            "base64 /etc/munge/munge.key",
            show_output=False
        )
        
        if exit_code != 0 or not key_content.strip():
            print("❌ 컨트롤러에서 Munge 키를 읽을 수 없습니다")
            return False
        
        # 2. 각 계산 노드에 배포
        for node in compute_nodes:
            hostname = node['hostname']
            print(f"  🔑 {hostname}: Munge 설정 중...")
            
            # Munge 설치
            self.ssh_manager.execute_command(
                hostname,
                "yum install -y munge munge-libs munge-devel 2>/dev/null || apt-get install -y munge 2>/dev/null",
                show_output=False
            )
            
            # 디렉토리 생성
            self.ssh_manager.execute_command(
                hostname,
                "mkdir -p /etc/munge && mkdir -p /var/log/munge && mkdir -p /var/lib/munge",
                show_output=False
            )
            
            # 기존 키 백업
            self.ssh_manager.execute_command(
                hostname,
                "[ -f /etc/munge/munge.key ] && cp /etc/munge/munge.key /etc/munge/munge.key.backup.$(date +%Y%m%d_%H%M%S) || true",
                show_output=False
            )
            
            # 키 전송 (base64 인코딩 사용)
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname,
                f"echo '{key_content.strip()}' | base64 -d > /etc/munge/munge.key",
                show_output=False
            )
            
            if exit_code != 0:
                print(f"  ❌ {hostname}: Munge 키 전송 실패")
                continue
            
            # 권한 설정
            permission_cmds = [
                "chown munge:munge /etc/munge/munge.key",
                "chmod 400 /etc/munge/munge.key",
                "chown -R munge:munge /var/log/munge",
                "chown -R munge:munge /var/lib/munge",
                "chmod 700 /var/lib/munge"
            ]
            
            for cmd in permission_cmds:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            # 서비스 시작
            service_cmds = [
                "systemctl enable munge",
                "systemctl stop munge 2>/dev/null || true",
                "systemctl start munge",
            ]
            
            for cmd in service_cmds:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
            
            time.sleep(1)
            print(f"  ✅ {hostname}: Munge 배포 완료")
        
        return True
    
    def _validate_all_nodes(self, controller_hostname: str, compute_nodes: List[Dict]) -> bool:
        """모든 노드에서 Munge 검증"""
        print(f"\n🔍 Munge 인증 검증 중...")
        
        all_nodes = [controller_hostname] + [node['hostname'] for node in compute_nodes]
        failed_nodes = []
        
        for hostname in all_nodes:
            # 1. 서비스 상태 확인
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname,
                "systemctl is-active munge",
                show_output=False
            )
            
            if exit_code != 0:
                print(f"  ❌ {hostname}: Munge 서비스가 실행되지 않음")
                failed_nodes.append(hostname)
                continue
            
            # 2. 인증 테스트
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                hostname,
                "munge -n | unmunge",
                show_output=False,
                timeout=10
            )
            
            if exit_code == 0 and "STATUS" in stdout and "Success" in stdout:
                print(f"  ✅ {hostname}: Munge 인증 성공")
            else:
                print(f"  ❌ {hostname}: Munge 인증 실패")
                print(f"     stdout: {stdout[:200]}")
                print(f"     stderr: {stderr[:200]}")
                failed_nodes.append(hostname)
        
        # 3. 노드 간 상호 인증 테스트
        print(f"\n🔗 노드 간 Munge 상호 인증 테스트...")
        
        for node in compute_nodes:
            hostname = node['hostname']
            
            # 컨트롤러 -> 계산 노드 인증 테스트
            exit_code, stdout, stderr = self.ssh_manager.execute_command(
                controller_hostname,
                f"munge -n | ssh {hostname} unmunge",
                show_output=False,
                timeout=15
            )
            
            if exit_code == 0:
                print(f"  ✅ {controller_hostname} -> {hostname}: 상호 인증 성공")
            else:
                print(f"  ⚠️  {controller_hostname} -> {hostname}: 상호 인증 실패 (SSH 키 문제일 수 있음)")
        
        if failed_nodes:
            print(f"\n❌ Munge 검증 실패 노드: {', '.join(failed_nodes)}")
            return False
        
        print("\n✅ 모든 노드 Munge 인증 검증 성공")
        return True
    
    def verify_munge_key_consistency(self) -> bool:
        """모든 노드의 Munge 키가 동일한지 확인"""
        print("\n🔍 Munge 키 일관성 검증...")
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        compute_nodes = self.config['nodes']['compute_nodes']
        
        # 컨트롤러 키의 체크섬
        exit_code, controller_checksum, _ = self.ssh_manager.execute_command(
            controller_hostname,
            "md5sum /etc/munge/munge.key | awk '{print $1}'",
            show_output=False
        )
        
        if exit_code != 0:
            print("❌ 컨트롤러 Munge 키 체크섬 확인 실패")
            return False
        
        controller_checksum = controller_checksum.strip()
        print(f"  📌 컨트롤러 키 체크섬: {controller_checksum}")
        
        # 각 노드의 체크섬 비교
        all_match = True
        for node in compute_nodes:
            hostname = node['hostname']
            
            exit_code, node_checksum, _ = self.ssh_manager.execute_command(
                hostname,
                "md5sum /etc/munge/munge.key | awk '{print $1}'",
                show_output=False
            )
            
            if exit_code != 0:
                print(f"  ❌ {hostname}: 체크섬 확인 실패")
                all_match = False
                continue
            
            node_checksum = node_checksum.strip()
            
            if node_checksum == controller_checksum:
                print(f"  ✅ {hostname}: 키 일치 ({node_checksum})")
            else:
                print(f"  ❌ {hostname}: 키 불일치! (컨트롤러: {controller_checksum}, 노드: {node_checksum})")
                all_match = False
        
        if all_match:
            print("\n✅ 모든 노드의 Munge 키가 일치합니다")
        else:
            print("\n❌ 일부 노드의 Munge 키가 일치하지 않습니다")
        
        return all_match
    
    def get_munge_status_report(self) -> Dict[str, Any]:
        """Munge 상태 리포트 생성"""
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        compute_nodes = self.config['nodes']['compute_nodes']
        
        all_nodes = [controller_hostname] + [node['hostname'] for node in compute_nodes]
        
        report = {
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'nodes': {}
        }
        
        for hostname in all_nodes:
            node_status = {
                'service_running': False,
                'authentication_ok': False,
                'key_checksum': None
            }
            
            # 서비스 상태
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, "systemctl is-active munge", show_output=False
            )
            node_status['service_running'] = (exit_code == 0)
            
            # 인증 테스트
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "munge -n | unmunge", show_output=False
            )
            node_status['authentication_ok'] = (exit_code == 0 and "Success" in stdout)
            
            # 키 체크섬
            exit_code, checksum, _ = self.ssh_manager.execute_command(
                hostname, "md5sum /etc/munge/munge.key | awk '{print $1}'",
                show_output=False
            )
            if exit_code == 0:
                node_status['key_checksum'] = checksum.strip()
            
            report['nodes'][hostname] = node_status
        
        return report


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python munge_validator.py <config_file>")
        return
    
    try:
        # 설정 파일 로드
        parser = ConfigParser(sys.argv[1])
        config = parser.load_config()
        
        # SSH 관리자 설정
        ssh_manager = SSHManager()
        all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
        
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        # 연결
        ssh_manager.connect_all_nodes()
        
        # Munge 검증
        validator = MungeValidator(config, ssh_manager)
        
        if validator.setup_and_validate_munge():
            print("\n✅ Munge 설정 성공!")
            
            # 일관성 검증
            validator.verify_munge_key_consistency()
            
            # 상태 리포트
            report = validator.get_munge_status_report()
            print("\n📊 Munge 상태 리포트:")
            import json
            print(json.dumps(report, indent=2))
        else:
            print("\n❌ Munge 설정 실패!")
        
        ssh_manager.disconnect_all()
        
    except Exception as e:
        print(f"오류 발생: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
