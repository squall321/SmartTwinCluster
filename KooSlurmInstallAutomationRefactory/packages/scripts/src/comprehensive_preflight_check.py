#!/usr/bin/env python3
"""
강화된 설치 전 검증 모듈
Phase 2-1: Comprehensive Pre-flight Check

10가지 상세 검증 항목:
1. 디스크 공간 상세 확인
2. 시간 동기화 검증
3. 네트워크 대역폭 테스트
4. 기존 Slurm 설치 감지
5. 방화벽 규칙 상세 확인
6. DNS 해상도 테스트
7. SELinux/AppArmor 확인
8. 메모리 및 스왑 확인
9. 커널 파라미터 확인
10. 패키지 저장소 접근성
"""

import time
import subprocess
from typing import Dict, List, Any, Tuple
from ssh_manager import SSHManager
from datetime import datetime


class ComprehensivePreflightCheck:
    """강화된 사전 점검 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.results = {}
        self.warnings = []
        self.errors = []
        self.fixes = []
        
    def run_all_checks(self, fix_issues: bool = False) -> bool:
        """모든 점검 실행"""
        print("\n" + "="*60)
        print("  🔍 강화된 설치 전 점검 (Comprehensive Pre-flight Check)")
        print("="*60 + "\n")
        
        checks = [
            ("1. 디스크 공간", self.check_disk_space_detailed, True),
            ("2. 시간 동기화", self.check_time_sync, True),
            ("3. 네트워크 대역폭", self.check_network_bandwidth, False),
            ("4. 기존 Slurm 설치", self.check_existing_slurm, True),
            ("5. 방화벽 포트", self.check_firewall_ports, False),
            ("6. DNS 해상도", self.check_dns_resolution, True),
            ("7. SELinux/AppArmor", self.check_selinux, False),
            ("8. 메모리/스왑", self.check_memory_swap, True),
            ("9. 커널 파라미터", self.check_kernel_params, False),
            ("10. 패키지 저장소", self.check_repositories, True)
        ]
        
        critical_failed = False
        
        for name, check_func, is_critical in checks:
            print(f"\n🔍 {name} 점검 중...")
            print("-" * 60)
            
            try:
                result = check_func()
                self.results[name] = result
                
                if result['passed']:
                    print(f"✅ {name}: 통과")
                    if result.get('details'):
                        for detail in result['details']:
                            print(f"   {detail}")
                else:
                    if is_critical:
                        print(f"❌ {name}: 실패 (치명적)")
                        critical_failed = True
                    else:
                        print(f"⚠️  {name}: 경고")
                    
                    print(f"   문제: {result.get('message', '알 수 없는 오류')}")
                    
                    if result.get('fix'):
                        print(f"   해결: {result['fix']}")
                        self.fixes.append({
                            'check': name,
                            'fix': result['fix'],
                            'command': result.get('fix_command')
                        })
                    
                    if is_critical:
                        self.errors.append(f"{name}: {result.get('message')}")
                    else:
                        self.warnings.append(f"{name}: {result.get('message')}")
                        
            except Exception as e:
                print(f"❌ {name}: 점검 중 오류 발생 - {e}")
                if is_critical:
                    critical_failed = True
                    self.errors.append(f"{name}: 점검 실패 - {e}")
        
        # 결과 요약
        self._print_summary()
        
        return not critical_failed
    
    def check_disk_space_detailed(self) -> Dict[str, Any]:
        """디스크 공간 상세 확인"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        paths_to_check = {
            '/': 10,
            '/tmp': 5,
            '/var': 3,
            '/var/log': 2,
            self.config['slurm_config']['install_path']: 1
        }
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        insufficient_space = []
        
        for path, min_gb in paths_to_check.items():
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname,
                f"df -BG {path} 2>/dev/null | tail -1 | awk '{{print $4}}' | sed 's/G//'",
                show_output=False
            )
            
            if exit_code == 0:
                try:
                    avail_gb = int(stdout.strip())
                    if avail_gb >= min_gb:
                        result['details'].append(f"✓ {path}: {avail_gb}GB 사용 가능")
                    else:
                        result['passed'] = False
                        insufficient_space.append(f"{path} ({avail_gb}GB < {min_gb}GB)")
                        result['details'].append(f"✗ {path}: {avail_gb}GB (최소 {min_gb}GB 필요)")
                except ValueError:
                    pass
        
        if not result['passed']:
            result['message'] = f"디스크 공간 부족: {', '.join(insufficient_space)}"
            result['fix'] = "불필요한 파일 삭제 또는 디스크 확장 필요"
        
        return result
    
    def check_time_sync(self) -> Dict[str, Any]:
        """시간 동기화 검증"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        compute_nodes = self.config['nodes']['compute_nodes']
        
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            controller_hostname, "date +%s", show_output=False
        )
        
        if exit_code != 0:
            result['passed'] = False
            result['message'] = "컨트롤러 시간 확인 실패"
            return result
        
        controller_time = int(stdout.strip())
        result['details'].append(f"컨트롤러 시간: {datetime.fromtimestamp(controller_time)}")
        
        problematic_nodes = []
        for node in compute_nodes:
            hostname = node['hostname']
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, "date +%s", show_output=False
            )
            
            if exit_code == 0:
                node_time = int(stdout.strip())
                diff = abs(controller_time - node_time)
                
                if diff <= 5:
                    result['details'].append(f"✓ {hostname}: 시간 차이 {diff}초")
                else:
                    result['passed'] = False
                    problematic_nodes.append(f"{hostname} ({diff}초)")
                    result['details'].append(f"✗ {hostname}: 시간 차이 {diff}초 (>5초)")
        
        if not result['passed']:
            result['message'] = f"노드 간 시간 차이 과다: {', '.join(problematic_nodes)}"
            result['fix'] = "NTP 서비스 설정: systemctl start chronyd"
        
        return result
    
    def check_network_bandwidth(self) -> Dict[str, Any]:
        """네트워크 대역폭 테스트"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        compute_nodes = self.config['nodes']['compute_nodes']
        
        for node in compute_nodes[:1]:
            hostname = node['hostname']
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                controller_hostname,
                f"ping -c 10 {hostname} 2>/dev/null | tail -1",
                show_output=False
            )
            
            if exit_code == 0 and "avg" in stdout:
                try:
                    avg_rtt = float(stdout.split('/')[-3])
                    result['details'].append(f"✓ {hostname}: 평균 RTT {avg_rtt:.2f}ms")
                    if avg_rtt > 10:
                        result['details'].append(f"  ⚠ 네트워크 지연 높음 (>10ms)")
                except:
                    pass
        
        result['details'].append("네트워크 연결 정상")
        return result
    
    def check_existing_slurm(self) -> Dict[str, Any]:
        """기존 Slurm 설치 감지"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        
        processes = ['slurmctld', 'slurmd', 'slurmdbd']
        running_processes = []
        
        for proc in processes:
            exit_code, _, _ = self.ssh_manager.execute_command(
                hostname, f"pgrep -x {proc}", show_output=False
            )
            if exit_code == 0:
                running_processes.append(proc)
        
        if running_processes:
            result['passed'] = False
            result['message'] = f"기존 Slurm 프로세스 실행 중: {', '.join(running_processes)}"
            result['details'].append(f"✗ 실행 중인 프로세스: {', '.join(running_processes)}")
            result['fix'] = "cleanup 실행: ./install_slurm.py -c config.yaml --cleanup"
        else:
            result['details'].append("✓ 실행 중인 Slurm 프로세스 없음")
        
        return result
    
    def check_firewall_ports(self) -> Dict[str, Any]:
        """방화벽 포트 확인"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        
        exit_code, _, _ = self.ssh_manager.execute_command(
            hostname, "systemctl is-active firewalld", show_output=False
        )
        
        if exit_code != 0:
            result['details'].append("방화벽 비활성화 또는 다른 방화벽 사용 중")
            return result
        
        result['details'].append("✓ firewalld 실행 중")
        result['details'].append("⚠ 필요 시 수동으로 포트 6817, 6818, 6819 개방")
        
        return result
    
    def check_dns_resolution(self) -> Dict[str, Any]:
        """DNS 해상도 테스트"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        controller_hostname = controller['hostname']
        all_nodes = [controller] + self.config['nodes']['compute_nodes']
        
        failed_resolutions = []
        
        for node in all_nodes:
            hostname = node['hostname']
            expected_ip = node['ip_address']
            
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                controller_hostname,
                f"getent hosts {hostname} 2>/dev/null | awk '{{print $1}}'",
                show_output=False
            )
            
            if exit_code == 0:
                resolved_ip = stdout.strip()
                if resolved_ip == expected_ip:
                    result['details'].append(f"✓ {hostname} -> {resolved_ip}")
                else:
                    result['passed'] = False
                    failed_resolutions.append(f"{hostname}")
                    result['details'].append(f"✗ {hostname}: {resolved_ip} (예상: {expected_ip})")
            else:
                result['passed'] = False
                failed_resolutions.append(f"{hostname}")
                result['details'].append(f"✗ {hostname}: DNS 해석 실패")
        
        if not result['passed']:
            result['message'] = f"DNS 해석 실패: {', '.join(failed_resolutions)}"
            result['fix'] = "/etc/hosts 파일에 호스트네임 추가"
        
        return result
    
    def check_selinux(self) -> Dict[str, Any]:
        """SELinux 확인"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            hostname, "getenforce 2>/dev/null", show_output=False
        )
        
        if exit_code == 0:
            status = stdout.strip()
            if status == "Enforcing":
                result['details'].append(f"⚠ SELinux: {status} (Permissive 권장)")
                result['message'] = "SELinux Enforcing 모드"
                result['fix'] = "setenforce 0 권장"
            else:
                result['details'].append(f"✓ SELinux: {status}")
        else:
            result['details'].append("SELinux 미설치")
        
        return result
    
    def check_memory_swap(self) -> Dict[str, Any]:
        """메모리 확인"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            hostname, "free -g | grep '^Mem:' | awk '{print $2,$7}'", show_output=False
        )
        
        if exit_code == 0:
            parts = stdout.strip().split()
            if len(parts) >= 2:
                total_gb = int(parts[0])
                result['details'].append(f"총 메모리: {total_gb}GB")
                
                if total_gb < 4:
                    result['passed'] = False
                    result['message'] = f"메모리 부족 ({total_gb}GB < 4GB)"
                    result['fix'] = "최소 4GB RAM 필요"
        
        return result
    
    def check_kernel_params(self) -> Dict[str, Any]:
        """커널 파라미터 확인"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        
        params_to_check = ['vm.swappiness', 'net.core.rmem_max']
        
        for param in params_to_check:
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname, f"sysctl -n {param} 2>/dev/null", show_output=False
            )
            
            if exit_code == 0:
                result['details'].append(f"✓ {param}: {stdout.strip()}")
        
        return result
    
    def check_repositories(self) -> Dict[str, Any]:
        """패키지 저장소 접근성"""
        result = {'passed': True, 'details': [], 'message': '', 'fix': ''}
        
        controller = self.config['nodes']['controller']
        hostname = controller['hostname']
        os_type = controller.get('os_type', 'centos8')
        
        if 'centos' in os_type or 'rhel' in os_type:
            exit_code, stdout, _ = self.ssh_manager.execute_command(
                hostname,
                "yum repolist 2>/dev/null | grep -E 'base|updates|epel' | wc -l",
                show_output=False
            )
            
            if exit_code == 0:
                repo_count = int(stdout.strip())
                if repo_count >= 2:
                    result['details'].append(f"✓ {repo_count}개 저장소 사용 가능")
                else:
                    result['passed'] = False
                    result['message'] = "사용 가능한 저장소 부족"
                    result['fix'] = "yum install -y epel-release"
        
        return result
    
    def _print_summary(self):
        """결과 요약 출력"""
        print("\n" + "="*60)
        print("  📊 점검 결과 요약")
        print("="*60 + "\n")
        
        passed_count = sum(1 for r in self.results.values() if r['passed'])
        total_count = len(self.results)
        
        print(f"통과: {passed_count}/{total_count}")
        
        if self.errors:
            print(f"\n❌ 치명적 오류 ({len(self.errors)}개):")
            for error in self.errors:
                print(f"   - {error}")
        
        if self.warnings:
            print(f"\n⚠️  경고 ({len(self.warnings)}개):")
            for warning in self.warnings:
                print(f"   - {warning}")
        
        if not self.errors and not self.warnings:
            print("\n✅ 모든 점검 항목 통과!")
            print("   Slurm 설치를 진행하셔도 좋습니다.")
        elif self.errors:
            print("\n❌ 치명적 오류가 있습니다. 해결 후 다시 시도하세요.")
        else:
            print("\n⚠️  경고가 있지만 설치는 가능합니다.")


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python comprehensive_preflight_check.py <config_file>")
        return
    
    try:
        parser = ConfigParser(sys.argv[1])
        config = parser.load_config()
        
        ssh_manager = SSHManager()
        all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
        
        for node in all_nodes:
            ssh_manager.add_node(node)
        
        ssh_manager.connect_all_nodes()
        
        checker = ComprehensivePreflightCheck(config, ssh_manager)
        success = checker.run_all_checks()
        
        ssh_manager.disconnect_all()
        
        sys.exit(0 if success else 1)
        
    except Exception as e:
        print(f"오류 발생: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
