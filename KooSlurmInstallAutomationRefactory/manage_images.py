#!/usr/bin/env python3
"""
Apptainer 이미지 관리 통합 도구
이미지 업로드, 목록 조회, 동기화, 삭제 등을 관리
"""

import sys
import argparse
from pathlib import Path
from typing import List, Dict
import yaml

sys.path.insert(0, str(Path(__file__).parent))

from src.ssh_manager import SSHManager
from sync_apptainer_images import ApptainerImageSync


def list_images(syncer: ApptainerImageSync):
    """이미지 목록 조회"""
    print("\n📋 Apptainer 이미지 목록")
    print("=" * 70)
    
    # 중앙 저장소
    print("\n📦 중앙 저장소 (/share/apptainer/images):")
    central_images = syncer.list_central_images()
    
    if central_images:
        for img_path in central_images:
            img_name = Path(img_path).name
            
            # 파일 크기 확인
            exit_code, size_output, _ = syncer.ssh_manager.execute_command(
                syncer.controller['hostname'],
                f"stat -c '%s' {img_path}",
                show_output=False
            )
            
            size_mb = int(size_output.strip()) / (1024 * 1024) if size_output else 0
            print(f"   - {img_name} ({size_mb:.1f} MB)")
    else:
        print("   (이미지 없음)")
    
    # 각 계산 노드
    for node in syncer.compute_nodes:
        hostname = node['hostname']
        print(f"\n💾 {hostname} (/scratch/apptainer/images):")
        
        exit_code, stdout, _ = syncer.ssh_manager.execute_command(
            hostname,
            f"find {syncer.scratch_image_path} -name '*.sif' -type f",
            show_output=False
        )
        
        if exit_code == 0 and stdout:
            images = [line.strip() for line in stdout.strip().split('\n') if line.strip()]
            for img_path in images:
                img_name = Path(img_path).name
                
                # 파일 크기 확인
                exit_code, size_output, _ = syncer.ssh_manager.execute_command(
                    hostname,
                    f"stat -c '%s' {img_path}",
                    show_output=False
                )
                
                size_mb = int(size_output.strip()) / (1024 * 1024) if size_output else 0
                print(f"   - {img_name} ({size_mb:.1f} MB)")
        else:
            print("   (이미지 없음)")


def upload_image(syncer: ApptainerImageSync, local_path: str):
    """로컬 이미지를 중앙 저장소로 업로드"""
    local_file = Path(local_path)
    
    if not local_file.exists():
        print(f"❌ 파일을 찾을 수 없습니다: {local_path}")
        return False
    
    if not local_file.suffix == '.sif':
        print(f"⚠️  경고: .sif 파일이 아닙니다: {local_path}")
        response = input("계속하시겠습니까? (y/N): ")
        if response.lower() != 'y':
            return False
    
    print(f"\n📤 이미지 업로드 중...")
    print(f"   원본: {local_path}")
    print(f"   대상: {syncer.central_image_path}/{local_file.name}")
    
    # 파일 크기 확인
    size_mb = local_file.stat().st_size / (1024 * 1024)
    print(f"   크기: {size_mb:.1f} MB")
    
    # scp로 업로드
    controller = syncer.controller
    upload_cmd = (
        f"scp {local_path} "
        f"{controller['ssh_user']}@{controller['hostname']}:{syncer.central_image_path}/"
    )
    
    import subprocess
    result = subprocess.run(upload_cmd, shell=True)
    
    if result.returncode == 0:
        print(f"✅ 업로드 완료!")
        
        # 자동 동기화 물어보기
        response = input("\n계산 노드로 자동 동기화하시겠습니까? (Y/n): ")
        if response.lower() != 'n':
            syncer.sync_images_to_compute_nodes()
        
        return True
    else:
        print(f"❌ 업로드 실패")
        return False


def delete_image(syncer: ApptainerImageSync, image_name: str):
    """이미지 삭제 (중앙 저장소 및 모든 계산 노드)"""
    print(f"\n🗑️  이미지 삭제: {image_name}")
    
    # 확인
    response = input(f"⚠️  정말 '{image_name}'을(를) 모든 노드에서 삭제하시겠습니까? (yes/NO): ")
    if response != 'yes':
        print("취소되었습니다.")
        return False
    
    # 중앙 저장소에서 삭제
    controller_hostname = syncer.controller['hostname']
    central_path = f"{syncer.central_image_path}/{image_name}"
    
    print(f"   🗑️  중앙 저장소: {controller_hostname}")
    syncer.ssh_manager.execute_command(
        controller_hostname,
        f"rm -f {central_path}",
        show_output=False
    )
    
    # 각 계산 노드에서 삭제
    for node in syncer.compute_nodes:
        hostname = node['hostname']
        scratch_path = f"{syncer.scratch_image_path}/{image_name}"
        
        print(f"   🗑️  {hostname}")
        syncer.ssh_manager.execute_command(
            hostname,
            f"rm -f {scratch_path}",
            show_output=False
        )
    
    print(f"✅ '{image_name}' 삭제 완료")
    return True


def clean_scratch(syncer: ApptainerImageSync):
    """계산 노드의 scratch 이미지 정리 (중앙에 없는 이미지 삭제)"""
    print("\n🧹 Scratch 이미지 정리 중...")
    
    # 중앙 저장소의 이미지 목록
    central_images = syncer.list_central_images()
    central_names = {Path(img).name for img in central_images}
    
    print(f"📦 중앙 저장소 이미지 수: {len(central_names)}")
    
    # 각 계산 노드 정리
    for node in syncer.compute_nodes:
        hostname = node['hostname']
        print(f"\n  🔍 {hostname} 확인 중...")
        
        # 노드의 이미지 목록
        exit_code, stdout, _ = syncer.ssh_manager.execute_command(
            hostname,
            f"find {syncer.scratch_image_path} -name '*.sif' -type f",
            show_output=False
        )
        
        if exit_code != 0 or not stdout:
            print(f"     ℹ️  이미지 없음")
            continue
        
        node_images = [line.strip() for line in stdout.strip().split('\n') if line.strip()]
        
        deleted_count = 0
        for img_path in node_images:
            img_name = Path(img_path).name
            
            if img_name not in central_names:
                print(f"     🗑️  삭제: {img_name} (중앙에 없음)")
                syncer.ssh_manager.execute_command(
                    hostname,
                    f"rm -f {img_path}",
                    show_output=False
                )
                deleted_count += 1
        
        if deleted_count > 0:
            print(f"     ✅ {deleted_count}개 이미지 삭제 완료")
        else:
            print(f"     ✅ 정리할 이미지 없음")
    
    print("\n✅ Scratch 정리 완료!")


def main():
    parser = argparse.ArgumentParser(
        description="Apptainer 이미지 관리 도구",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 이미지 목록 조회
  python3 manage_images.py list
  
  # 이미지 업로드
  python3 manage_images.py upload myapp.sif
  
  # 이미지 동기화
  python3 manage_images.py sync
  
  # 이미지 삭제
  python3 manage_images.py delete myapp.sif
  
  # Scratch 정리
  python3 manage_images.py clean
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='명령어')
    
    # list 명령어
    subparsers.add_parser('list', help='이미지 목록 조회')
    
    # upload 명령어
    upload_parser = subparsers.add_parser('upload', help='이미지 업로드')
    upload_parser.add_argument('file', help='업로드할 .sif 파일 경로')
    
    # sync 명령어
    subparsers.add_parser('sync', help='이미지 동기화')
    
    # delete 명령어
    delete_parser = subparsers.add_parser('delete', help='이미지 삭제')
    delete_parser.add_argument('image', help='삭제할 이미지 이름 (예: myapp.sif)')
    
    # clean 명령어
    subparsers.add_parser('clean', help='Scratch 이미지 정리')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # 설정 파일 로드
    config_file = Path("my_cluster.yaml")
    if not config_file.exists():
        print("❌ my_cluster.yaml 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    with open(config_file, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    # SSH 매니저 및 동기화 클래스 초기화
    ssh_manager = SSHManager(config)
    syncer = ApptainerImageSync(config, ssh_manager)
    
    # 명령어 실행
    try:
        if args.command == 'list':
            list_images(syncer)
        
        elif args.command == 'upload':
            upload_image(syncer, args.file)
        
        elif args.command == 'sync':
            syncer.setup_directories()
            syncer.sync_images_to_compute_nodes()
            syncer.verify_sync()
        
        elif args.command == 'delete':
            delete_image(syncer, args.image)
        
        elif args.command == 'clean':
            clean_scratch(syncer)
        
    except KeyboardInterrupt:
        print("\n\n⚠️  사용자에 의해 중단되었습니다.")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 오류 발생: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
