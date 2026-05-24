#!/usr/bin/env python3
"""
Apptainer 이미지 동기화 모듈
중앙 저장소의 이미지를 모든 계산 노드의 scratch로 자동 복사
"""

import sys
import os
from typing import Dict, Any, List, TYPE_CHECKING
from pathlib import Path
import time

# src 디렉토리 경로 추가
src_path = Path(__file__).parent / 'src'
sys.path.insert(0, str(src_path))

import ssh_manager

if TYPE_CHECKING:
    from ssh_manager import SSHManager


class ApptainerImageSync:
    """Apptainer 이미지 동기화 클래스"""
    
    def __init__(self, config: Dict[str, Any], ssh_mgr):
        self.config = config
        self.ssh_manager = ssh_mgr
        
        container_config = config.get('container_support', {}).get('apptainer', {})
        
        # 경로 설정
        self.central_image_path = container_config.get('image_path', '/share/apptainer/images')
        self.scratch_image_path = container_config.get('scratch_image_path', '/scratch/apptainer/images')
        
        # 노드 정보
        self.controller = config['nodes']['controller']
        self.compute_nodes = config['nodes']['compute_nodes']
        self.all_nodes = [self.controller] + self.compute_nodes
    
    def setup_directories(self) -> bool:
        """이미지 디렉토리 생성"""
        print("\n📁 Apptainer 이미지 디렉토리 설정 중...")
        
        # 컨트롤러에 중앙 저장소 생성
        controller_hostname = self.controller['hostname']
        print(f"  📦 {controller_hostname}: 중앙 저장소 생성 - {self.central_image_path}")
        
        commands = [
            f"mkdir -p {self.central_image_path}",
            f"chmod 755 {self.central_image_path}",
            f"chown -R koopark:koopark {self.central_image_path}"
        ]
        
        for cmd in commands:
            self.ssh_manager.execute_command(controller_hostname, cmd, show_output=False)
        
        # 모든 노드에 scratch 디렉토리 생성
        for node in self.all_nodes:
            hostname = node['hostname']
            print(f"  💾 {hostname}: 로컬 캐시 생성 - {self.scratch_image_path}")
            
            commands = [
                f"mkdir -p {self.scratch_image_path}",
                f"chmod 755 {self.scratch_image_path}",
                f"chown -R koopark:koopark {self.scratch_image_path}"
            ]
            
            for cmd in commands:
                self.ssh_manager.execute_command(hostname, cmd, show_output=False)
        
        print("✅ 디렉토리 설정 완료!")
        return True
    
    def list_central_images(self) -> List[str]:
        """중앙 저장소의 이미지 목록 조회"""
        controller_hostname = self.controller['hostname']
        
        exit_code, stdout, _ = self.ssh_manager.execute_command(
            controller_hostname,
            f"find {self.central_image_path} -name '*.sif' -type f",
            show_output=False
        )
        
        if exit_code == 0 and stdout:
            images = [line.strip() for line in stdout.strip().split('\n') if line.strip()]
            return images
        
        return []
    
    def sync_images_to_compute_nodes(self) -> bool:
        """계산 노드로 이미지 동기화"""
        print("\n🔄 Apptainer 이미지 동기화 시작...")
        
        # 중앙 저장소의 이미지 목록 확인
        central_images = self.list_central_images()
        
        if not central_images:
            print("⚠️  중앙 저장소에 이미지가 없습니다.")
            print(f"💡 이미지를 다음 경로에 업로드하세요: {self.central_image_path}")
            print(f"   예시: scp myapp.sif koopark@smarttwincluster:{self.central_image_path}/")
            return True
        
        print(f"📋 발견된 이미지 수: {len(central_images)}")
        for img in central_images:
            print(f"   - {Path(img).name}")
        
        # 각 계산 노드로 복사
        for node in self.compute_nodes:
            hostname = node['hostname']
            print(f"\n  🚀 {hostname}: 이미지 동기화 중...")
            
            for image_path in central_images:
                image_name = Path(image_path).name
                
                # 파일 크기 확인
                exit_code, size_output, _ = self.ssh_manager.execute_command(
                    self.controller['hostname'],
                    f"stat -f '%z' {image_path} 2>/dev/null || stat -c '%s' {image_path}",
                    show_output=False
                )
                
                size_mb = int(size_output.strip()) / (1024 * 1024) if size_output else 0
                
                print(f"     📦 복사 중: {image_name} ({size_mb:.1f} MB)")
                
                # rsync로 복사 (빠르고 안전)
                sync_cmd = f"""
                rsync -avz --progress \
                    {self.central_image_path}/{image_name} \
                    {hostname}:{self.scratch_image_path}/{image_name}
                """
                
                start_time = time.time()
                exit_code, stdout, stderr = self.ssh_manager.execute_command(
                    self.controller['hostname'],
                    sync_cmd,
                    show_output=False,
                    timeout=1800  # 30분
                )
                elapsed = time.time() - start_time
                
                if exit_code == 0:
                    speed = size_mb / elapsed if elapsed > 0 else 0
                    print(f"     ✅ 완료! (소요시간: {elapsed:.1f}초, 속도: {speed:.1f} MB/s)")
                else:
                    print(f"     ⚠️  복사 실패: {image_name}")
                    if stderr:
                        print(f"        오류: {stderr[:200]}")
        
        print("\n✅ 이미지 동기화 완료!")
        return True
    
    def verify_sync(self) -> bool:
        """동기화 검증"""
        print("\n🧪 이미지 동기화 검증 중...")
        
        central_images = self.list_central_images()
        
        if not central_images:
            print("ℹ️  중앙 저장소에 이미지가 없어 검증을 건너뜁니다.")
            return True
        
        all_success = True
        
        for node in self.compute_nodes:
            hostname = node['hostname']
            print(f"\n  🔍 {hostname} 확인 중...")
            
            for central_image in central_images:
                image_name = Path(central_image).name
                local_path = f"{self.scratch_image_path}/{image_name}"
                
                # 파일 존재 확인
                exit_code, _, _ = self.ssh_manager.execute_command(
                    hostname,
                    f"test -f {local_path}",
                    show_output=False
                )
                
                if exit_code == 0:
                    # 파일 크기 확인
                    exit_code, size_output, _ = self.ssh_manager.execute_command(
                        hostname,
                        f"stat -f '%z' {local_path} 2>/dev/null || stat -c '%s' {local_path}",
                        show_output=False
                    )
                    
                    if size_output:
                        size_mb = int(size_output.strip()) / (1024 * 1024)
                        print(f"     ✅ {image_name} ({size_mb:.1f} MB)")
                    else:
                        print(f"     ✅ {image_name}")
                else:
                    print(f"     ❌ {image_name} - 파일이 없습니다")
                    all_success = False
        
        if all_success:
            print("\n✅ 동기화 검증 완료! 모든 이미지가 정상적으로 복사되었습니다.")
        else:
            print("\n⚠️  일부 이미지 복사 실패")
        
        return all_success
    
    def create_sync_cron(self) -> bool:
        """자동 동기화 cron job 생성"""
        print("\n⏰ 자동 동기화 cron job 설정 중...")
        
        controller_hostname = self.controller['hostname']
        
        # 동기화 스크립트 생성
        sync_script = f"""#!/bin/bash
# Apptainer 이미지 자동 동기화 스크립트
# 중앙 저장소의 이미지를 계산 노드로 동기화

CENTRAL_PATH="{self.central_image_path}"
SCRATCH_PATH="{self.scratch_image_path}"
LOG_FILE="/var/log/apptainer_sync.log"

echo "========================================" >> $LOG_FILE
echo "동기화 시작: $(date)" >> $LOG_FILE

# 중앙 저장소의 이미지 목록
IMAGES=$(find $CENTRAL_PATH -name '*.sif' -type f)

if [ -z "$IMAGES" ]; then
    echo "동기화할 이미지가 없습니다." >> $LOG_FILE
    exit 0
fi

# 각 계산 노드로 동기화
"""
        
        for node in self.compute_nodes:
            hostname = node['hostname']
            sync_script += f"""
echo "동기화 중: {hostname}" >> $LOG_FILE
rsync -avz --progress $CENTRAL_PATH/*.sif {hostname}:$SCRATCH_PATH/ >> $LOG_FILE 2>&1
"""
        
        sync_script += """
echo "동기화 완료: $(date)" >> $LOG_FILE
"""
        
        # 스크립트 업로드
        script_path = "/usr/local/bin/apptainer_sync.sh"
        self.ssh_manager.execute_command(
            controller_hostname,
            f"echo '{sync_script}' > {script_path}",
            show_output=False
        )
        self.ssh_manager.execute_command(
            controller_hostname,
            f"chmod +x {script_path}",
            show_output=False
        )
        
        # cron job 추가 (매일 새벽 3시)
        cron_entry = f"0 3 * * * {script_path}"
        self.ssh_manager.execute_command(
            controller_hostname,
            f"(crontab -l 2>/dev/null | grep -v '{script_path}'; echo '{cron_entry}') | crontab -",
            show_output=False
        )
        
        print(f"✅ 자동 동기화 설정 완료 (매일 03:00)")
        print(f"   스크립트: {script_path}")
        print(f"   로그: /var/log/apptainer_sync.log")
        
        return True


def main():
    """메인 함수"""
    import yaml
    
    print("=" * 70)
    print("🔄 Apptainer 이미지 동기화 도구")
    print("=" * 70)
    
    # 설정 파일 로드
    config_file = Path("my_multihead_cluster.yaml")
    if not config_file.exists():
        print("❌ my_multihead_cluster.yaml 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    # SSH 매니저 초기화
    ssh_mgr = ssh_manager.SSHManager()
    
    # 모든 노드 추가
    all_nodes = [config['nodes']['controller']] + config['nodes']['compute_nodes']
    for node in all_nodes:
        ssh_mgr.add_node(node)
    
    # 연결
    ssh_mgr.connect_all_nodes()
    
    # 동기화 클래스 초기화
    syncer = ApptainerImageSync(config, ssh_mgr)
    
    # 작업 수행
    if not syncer.setup_directories():
        print("❌ 디렉토리 설정 실패")
        sys.exit(1)
    
    if not syncer.sync_images_to_compute_nodes():
        print("❌ 이미지 동기화 실패")
        sys.exit(1)
    
    syncer.verify_sync()
    syncer.create_sync_cron()
    
    # 연결 종료
    ssh_mgr.disconnect_all()
    
    print("\n" + "=" * 70)
    print("🎉 모든 작업 완료!")
    print("=" * 70)
    print("\n💡 사용 방법:")
    print(f"   1. 이미지 업로드: scp myapp.sif koopark@smarttwincluster:/share/apptainer/images/")
    print(f"   2. 수동 동기화: python3 sync_apptainer_images.py")
    print(f"   3. 자동 동기화: 매일 03:00 자동 실행")
    print(f"   4. Job에서 사용: apptainer exec /scratch/apptainer/images/myapp.sif ...")


if __name__ == '__main__':
    main()
