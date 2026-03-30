#!/usr/bin/env python3
"""
오프라인 설치 지원 모듈
Phase 1-4: 폐쇄망(air-gapped) 환경 지원
"""

import os
import hashlib
import subprocess
from typing import Dict, List, Optional, Any
from pathlib import Path
from ssh_manager import SSHManager
import json


class OfflinePackageManager:
    """오프라인 패키지 관리"""
    
    def __init__(self, config: Dict[str, Any], ssh_manager: SSHManager):
        self.config = config
        self.ssh_manager = ssh_manager
        self.slurm_version = config['slurm_config']['version']
        
        # 오프라인 패키지 디렉토리
        self.offline_dir = config.get('installation', {}).get('offline_package_dir', './offline_packages')
        self.offline_mode = config.get('installation', {}).get('offline_mode', False)
        
        # 패키지 정보
        self.packages = {
            'slurm': {
                'url': f'https://download.schedmd.com/slurm/slurm-{self.slurm_version}.tar.bz2',
                'filename': f'slurm-{self.slurm_version}.tar.bz2',
                'checksum_type': 'sha256'
            },
            'go': {
                'url': 'https://go.dev/dl/go1.21.5.linux-amd64.tar.gz',
                'filename': 'go1.21.5.linux-amd64.tar.gz',
                'checksum_type': 'sha256'
            },
            'munge': {
                'url': 'https://github.com/dun/munge/releases/download/munge-0.5.15/munge-0.5.15.tar.xz',
                'filename': 'munge-0.5.15.tar.xz',
                'checksum_type': 'sha256'
            }
        }
    
    def prepare_offline_packages(self) -> bool:
        """오프라인 설치를 위한 패키지 다운로드"""
        print("\n📦 오프라인 패키지 준비 중...")
        print(f"📁 저장 위치: {self.offline_dir}")
        
        # 디렉토리 생성
        os.makedirs(self.offline_dir, exist_ok=True)
        
        # 각 패키지 다운로드
        for name, info in self.packages.items():
            if not self._download_package(name, info):
                print(f"❌ {name} 패키지 다운로드 실패")
                return False
        
        # 의존성 RPM/DEB 패키지 수집
        if not self._collect_dependency_packages():
            print("⚠️  의존성 패키지 수집 실패 (계속 진행)")
        
        # 매니페스트 파일 생성
        self._generate_manifest()
        
        print("✅ 오프라인 패키지 준비 완료")
        return True
    
    def _download_package(self, name: str, info: Dict[str, str]) -> bool:
        """개별 패키지 다운로드"""
        url = info['url']
        filename = info['filename']
        filepath = os.path.join(self.offline_dir, filename)
        
        # 이미 존재하면 체크섬 검증
        if os.path.exists(filepath):
            print(f"  ℹ️  {filename} 이미 존재 - 체크섬 검증 중...")
            if self._verify_checksum(filepath, info.get('checksum')):
                print(f"  ✅ {filename} 검증 성공 (다운로드 건너뜀)")
                return True
            else:
                print(f"  ⚠️  체크섬 불일치 - 재다운로드...")
                os.remove(filepath)
        
        print(f"  📥 {filename} 다운로드 중...")
        
        # wget 또는 curl 사용
        try:
            # wget 시도
            result = subprocess.run(
                ['wget', '-q', '--show-progress', '--timeout=60', '--tries=3', 
                 '-O', filepath, url],
                capture_output=True,
                text=True,
                timeout=600
            )
            
            if result.returncode != 0:
                # curl로 재시도
                result = subprocess.run(
                    ['curl', '-L', '--progress-bar', '--max-time', '60', 
                     '--retry', '3', '-o', filepath, url],
                    capture_output=True,
                    text=True,
                    timeout=600
                )
            
            if result.returncode == 0 and os.path.exists(filepath):
                # 체크섬 계산 및 저장
                checksum = self._calculate_checksum(filepath)
                info['checksum'] = checksum
                print(f"  ✅ {filename} 다운로드 완료 (체크섬: {checksum[:16]}...)")
                return True
            else:
                print(f"  ❌ 다운로드 실패: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            print(f"  ❌ 다운로드 시간 초과")
            return False
        except FileNotFoundError as e:
            print(f"  ❌ wget/curl을 찾을 수 없습니다. 수동으로 다운로드하세요:")
            print(f"     URL: {url}")
            print(f"     저장 위치: {filepath}")
            return False
        except Exception as e:
            print(f"  ❌ 다운로드 오류: {e}")
            return False
    
    def _calculate_checksum(self, filepath: str, algorithm: str = 'sha256') -> str:
        """파일 체크섬 계산"""
        hash_func = hashlib.new(algorithm)
        
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b''):
                hash_func.update(chunk)
        
        return hash_func.hexdigest()
    
    def _verify_checksum(self, filepath: str, expected_checksum: Optional[str]) -> bool:
        """체크섬 검증"""
        if not expected_checksum:
            return True  # 체크섬이 없으면 통과
        
        actual_checksum = self._calculate_checksum(filepath)
        return actual_checksum == expected_checksum
    
    def _collect_dependency_packages(self) -> bool:
        """의존성 RPM/DEB 패키지 수집"""
        print("\n  📦 의존성 패키지 수집 중...")
        
        # yumdownloader로 RPM 패키지 다운로드 (CentOS/RHEL)
        rpm_dir = os.path.join(self.offline_dir, 'rpms')
        os.makedirs(rpm_dir, exist_ok=True)
        
        rpm_packages = [
            'munge', 'munge-libs', 'munge-devel',
            'gcc', 'gcc-c++', 'make', 'openssl-devel',
            'pam-devel', 'readline-devel', 'perl-ExtUtils-MakeMaker',
            'mysql-devel', 'hwloc-devel', 'lua-devel'
        ]
        
        try:
            # yumdownloader 확인
            result = subprocess.run(['which', 'yumdownloader'], capture_output=True)
            if result.returncode == 0:
                print("  📥 RPM 패키지 다운로드 중...")
                for pkg in rpm_packages:
                    subprocess.run(
                        ['yumdownloader', '--resolve', '--destdir', rpm_dir, pkg],
                        capture_output=True,
                        timeout=300
                    )
                print(f"  ✅ RPM 패키지 수집 완료: {rpm_dir}")
        except Exception as e:
            print(f"  ⚠️  RPM 패키지 수집 실패: {e}")
        
        # apt-get download로 DEB 패키지 다운로드 (Ubuntu/Debian)
        deb_dir = os.path.join(self.offline_dir, 'debs')
        os.makedirs(deb_dir, exist_ok=True)
        
        deb_packages = [
            'munge', 'libmunge-dev',
            'build-essential', 'libssl-dev',
            'libpam0g-dev', 'libreadline-dev',
            'libmariadb-dev', 'libhwloc-dev', 'liblua5.3-dev'
        ]
        
        try:
            result = subprocess.run(['which', 'apt-get'], capture_output=True)
            if result.returncode == 0:
                print("  📥 DEB 패키지 다운로드 중...")
                for pkg in deb_packages:
                    subprocess.run(
                        ['apt-get', 'download', pkg],
                        cwd=deb_dir,
                        capture_output=True,
                        timeout=300
                    )
                print(f"  ✅ DEB 패키지 수집 완료: {deb_dir}")
        except Exception as e:
            print(f"  ⚠️  DEB 패키지 수집 실패: {e}")
        
        return True
    
    def _generate_manifest(self):
        """매니페스트 파일 생성"""
        manifest = {
            'generated_at': subprocess.check_output(['date', '+%Y-%m-%d %H:%M:%S']).decode().strip(),
            'slurm_version': self.slurm_version,
            'packages': self.packages,
            'files': []
        }
        
        # 모든 파일 목록 및 체크섬
        for root, dirs, files in os.walk(self.offline_dir):
            for filename in files:
                if filename == 'manifest.json':
                    continue
                    
                filepath = os.path.join(root, filename)
                relpath = os.path.relpath(filepath, self.offline_dir)
                
                file_info = {
                    'path': relpath,
                    'size': os.path.getsize(filepath),
                    'checksum': self._calculate_checksum(filepath)
                }
                manifest['files'].append(file_info)
        
        # manifest.json 저장
        manifest_path = os.path.join(self.offline_dir, 'manifest.json')
        with open(manifest_path, 'w') as f:
            json.dump(manifest, indent=2, fp=f)
        
        print(f"  ✅ 매니페스트 생성: {manifest_path}")
        print(f"     총 파일 수: {len(manifest['files'])}")
    
    def verify_offline_packages(self) -> bool:
        """오프라인 패키지 검증"""
        print("\n🔍 오프라인 패키지 검증 중...")
        
        manifest_path = os.path.join(self.offline_dir, 'manifest.json')
        
        if not os.path.exists(manifest_path):
            print("❌ manifest.json을 찾을 수 없습니다")
            return False
        
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        
        print(f"  📋 매니페스트: {manifest['generated_at']}")
        print(f"  📦 Slurm 버전: {manifest['slurm_version']}")
        
        # 파일 검증
        missing_files = []
        checksum_errors = []
        
        for file_info in manifest['files']:
            filepath = os.path.join(self.offline_dir, file_info['path'])
            
            if not os.path.exists(filepath):
                missing_files.append(file_info['path'])
                continue
            
            # 체크섬 검증
            actual_checksum = self._calculate_checksum(filepath)
            if actual_checksum != file_info['checksum']:
                checksum_errors.append({
                    'path': file_info['path'],
                    'expected': file_info['checksum'],
                    'actual': actual_checksum
                })
        
        # 결과 출력
        if missing_files:
            print(f"\n  ❌ 누락된 파일 ({len(missing_files)}개):")
            for path in missing_files[:5]:
                print(f"     - {path}")
            if len(missing_files) > 5:
                print(f"     ... 외 {len(missing_files) - 5}개")
        
        if checksum_errors:
            print(f"\n  ❌ 체크섬 오류 ({len(checksum_errors)}개):")
            for error in checksum_errors[:3]:
                print(f"     - {error['path']}")
                print(f"       예상: {error['expected'][:16]}...")
                print(f"       실제: {error['actual'][:16]}...")
        
        if not missing_files and not checksum_errors:
            print("\n  ✅ 모든 패키지 검증 성공")
            return True
        else:
            print("\n  ❌ 패키지 검증 실패")
            return False
    
    def upload_packages_to_nodes(self, hostnames: List[str]) -> bool:
        """오프라인 패키지를 노드들에 업로드"""
        print("\n📤 오프라인 패키지 업로드 중...")
        
        remote_dir = '/tmp/slurm_offline_packages'
        
        for hostname in hostnames:
            print(f"\n  📦 {hostname}: 패키지 업로드 중...")
            
            # 원격 디렉토리 생성
            self.ssh_manager.execute_command(
                hostname,
                f"mkdir -p {remote_dir}",
                show_output=False
            )
            
            # 파일 업로드
            manifest_path = os.path.join(self.offline_dir, 'manifest.json')
            with open(manifest_path, 'r') as f:
                manifest = json.load(f)
            
            uploaded_count = 0
            failed_count = 0
            
            for file_info in manifest['files']:
                local_path = os.path.join(self.offline_dir, file_info['path'])
                remote_path = f"{remote_dir}/{file_info['path']}"
                
                # 원격 디렉토리 생성
                remote_file_dir = os.path.dirname(remote_path)
                self.ssh_manager.execute_command(
                    hostname,
                    f"mkdir -p {remote_file_dir}",
                    show_output=False
                )
                
                # 파일 업로드
                success = self.ssh_manager.upload_file(
                    local_path,
                    f"{hostname}:{remote_path}"
                )
                
                if success:
                    uploaded_count += 1
                else:
                    failed_count += 1
                    print(f"    ⚠️  업로드 실패: {file_info['path']}")
            
            print(f"  ✅ {hostname}: 업로드 완료 (성공: {uploaded_count}, 실패: {failed_count})")
        
        return True
    
    def install_from_offline_packages(self, hostname: str, os_type: str) -> bool:
        """오프라인 패키지로부터 설치"""
        print(f"\n📦 {hostname}: 오프라인 패키지 설치 중...")
        
        remote_dir = '/tmp/slurm_offline_packages'
        
        if os_type in ['centos', 'centos7', 'centos8', 'centos9', 'rhel', 'rhel7', 'rhel8', 'rhel9']:
            return self._install_rpm_offline(hostname, remote_dir)
        elif os_type in ['ubuntu', 'ubuntu18', 'ubuntu20', 'ubuntu22', 'ubuntu24']:
            return self._install_deb_offline(hostname, remote_dir)
        else:
            print(f"  ❌ 지원하지 않는 OS: {os_type}")
            return False
    
    def _install_rpm_offline(self, hostname: str, remote_dir: str) -> bool:
        """오프라인 RPM 설치"""
        rpm_dir = f"{remote_dir}/rpms"
        
        # RPM 파일 확인
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            hostname,
            f"ls {rpm_dir}/*.rpm 2>/dev/null | wc -l",
            show_output=False
        )
        
        rpm_count = int(stdout.strip()) if exit_code == 0 else 0
        
        if rpm_count == 0:
            print(f"  ⚠️  RPM 파일을 찾을 수 없음")
            return False
        
        print(f"  📦 {rpm_count}개의 RPM 파일 설치 중...")
        
        # 의존성 RPM 설치
        exit_code, stdout, stderr = self.ssh_manager.execute_command(
            hostname,
            f"yum localinstall -y {rpm_dir}/*.rpm",
            show_output=False,
            timeout=600
        )
        
        if exit_code == 0:
            print(f"  ✅ RPM 설치 성공")
            return True
        else:
            print(f"  ❌ RPM 설치 실패")
            print(f"     {stderr[:200]}")
            return False
    
    def _install_deb_offline(self, hostname: str, remote_dir: str) -> bool:
        """오프라인 DEB 설치"""
        deb_dir = f"{remote_dir}/debs"
        
        # DEB 파일 확인
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            hostname,
            f"ls {deb_dir}/*.deb 2>/dev/null | wc -l",
            show_output=False
        )
        
        deb_count = int(stdout.strip()) if exit_code == 0 else 0
        
        if deb_count == 0:
            print(f"  ⚠️  DEB 파일을 찾을 수 없음")
            return False
        
        print(f"  📦 {deb_count}개의 DEB 파일 설치 중 (APT 저장소 방식)...")

        # 로컬 APT 저장소 방식으로 안전하게 설치 (의존성 자동 해결)
        apt_install_cmds = f"""
            REPO_LIST="/etc/apt/sources.list.d/offline-install.list"
            # APT 인덱스 생성
            cd {deb_dir} && dpkg-scanpackages . /dev/null > Packages 2>/dev/null && gzip -k -f Packages
            # 로컬 저장소 설정
            echo "deb [trusted=yes] file://{deb_dir} ./" > "$REPO_LIST"
            # APT 캐시 업데이트
            apt-get update -o Dir::Etc::sourcelist="$REPO_LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null || true
            # 패키지 설치
            DEBIAN_FRONTEND=noninteractive apt-get install -f -y 2>/dev/null || true
            # 정리
            rm -f "$REPO_LIST" 2>/dev/null || true
        """

        exit_code, stdout, stderr = self.ssh_manager.execute_command(
            hostname,
            apt_install_cmds,
            show_output=False,
            timeout=600
        )

        if exit_code == 0:
            print(f"  ✅ DEB 설치 성공 (APT 저장소 방식)")
            return True
        else:
            print(f"  ❌ DEB 설치 실패")
            print(f"     {stderr[:200]}")
            return False


def main():
    """테스트 메인 함수"""
    from config_parser import ConfigParser
    from ssh_manager import SSHManager
    import sys
    
    if len(sys.argv) < 2:
        print("사용법: python offline_installer.py <config_file> [prepare|verify|upload|install]")
        print("\n명령어:")
        print("  prepare - 오프라인 패키지 다운로드")
        print("  verify  - 오프라인 패키지 검증")
        print("  upload  - 노드에 패키지 업로드")
        print("  install - 오프라인 패키지 설치")
        return
    
    config_file = sys.argv[1]
    command = sys.argv[2] if len(sys.argv) > 2 else 'prepare'
    
    try:
        # 설정 파일 로드
        parser = ConfigParser(config_file)
        config = parser.load_config()
        
        # SSH 관리자
        ssh_manager = SSHManager()
        
        # 오프라인 관리자
        offline_mgr = OfflinePackageManager(config, ssh_manager)
        
        if command == 'prepare':
            # 패키지 준비
            offline_mgr.prepare_offline_packages()
            
        elif command == 'verify':
            # 검증
            offline_mgr.verify_offline_packages()
            
        elif command == 'upload':
            # 업로드
            all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
            for node in all_nodes:
                ssh_manager.add_node(node)
            
            ssh_manager.connect_all_nodes()
            
            hostnames = [node['hostname'] for node in all_nodes]
            offline_mgr.upload_packages_to_nodes(hostnames)
            
            ssh_manager.disconnect_all()
            
        elif command == 'install':
            # 설치
            all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
            for node in all_nodes:
                ssh_manager.add_node(node)
            
            ssh_manager.connect_all_nodes()
            
            for node in all_nodes:
                hostname = node['hostname']
                os_type = node.get('os_type', 'centos8')
                offline_mgr.install_from_offline_packages(hostname, os_type)
            
            ssh_manager.disconnect_all()
        
        else:
            print(f"알 수 없는 명령어: {command}")
            
    except Exception as e:
        print(f"오류 발생: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
