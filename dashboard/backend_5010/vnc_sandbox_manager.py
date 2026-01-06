#!/usr/bin/env python3
"""
VNC 샌드박스 관리자
- 유저별 개인 VNC 샌드박스 생성
- viz-node sticky assignment (YAML 기반)
- 권한 관리
"""

import os
import subprocess
import hashlib
from pathlib import Path

# 시스템 명령어 절대 경로 (systemd 환경에서 PATH 제한)
APPTAINER = '/usr/bin/apptainer'
DU = '/usr/bin/du'

# 기본 이미지 경로 (VNC 샌드박스 생성용 원본)
# viz-node의 /opt/apptainers에 SIF 이미지가 존재
VNC_IMAGES_DIR = "/opt/apptainers"
BASE_VNC_IMAGE = f"{VNC_IMAGES_DIR}/vnc_desktop.sif"

# 유저 샌드박스 베이스 경로 (/scratch에 저장하여 재사용)
# 형식: /scratch/vnc_sandboxes/{username}_{image_id}/
USER_SANDBOX_BASE = "/scratch/vnc_sandboxes"


def get_viz_nodes_from_yaml():
    """YAML 설정에서 viz 노드 목록 가져오기"""
    viz_nodes = []
    yaml_paths = [
        os.path.join(os.path.dirname(__file__), '..', '..', 'my_multihead_cluster.yaml'),
        '/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_multihead_cluster.yaml',
    ]
    for yaml_path in yaml_paths:
        if os.path.exists(yaml_path):
            try:
                import yaml
                with open(yaml_path) as f:
                    config = yaml.safe_load(f)
                    nodes_config = config.get('nodes', {})

                    # node_type: viz인 노드 추출
                    for node in nodes_config.get('compute_nodes', []):
                        if node.get('node_type') == 'viz':
                            viz_nodes.append(node.get('hostname'))

                    if viz_nodes:
                        print(f"✅ VNC Sandbox Manager: Found {len(viz_nodes)} viz nodes from YAML")
                        return viz_nodes
            except Exception as e:
                print(f"⚠️  Failed to load viz nodes from YAML: {e}")

    # Fallback
    print("⚠️  Using fallback viz node")
    return ['viz-node001']


# viz-node 리스트 (YAML에서 동적 로드)
VIZ_NODES = get_viz_nodes_from_yaml()


def get_assigned_viz_node(username):
    """
    유저에게 고정된 viz-node 할당 (sticky assignment)
    해시 기반으로 항상 같은 노드 반환
    """
    # 유저명 해시로 노드 선택
    hash_value = int(hashlib.md5(username.encode()).hexdigest(), 16)
    node_index = hash_value % len(VIZ_NODES)
    return VIZ_NODES[node_index]


def get_user_sandbox_path(username, image_id='xfce4'):
    """
    유저 샌드박스 경로 반환

    Args:
        username: 사용자 이름
        image_id: 이미지 ID (xfce4, gnome, gnome_lsprepost 등)

    Returns:
        str: /scratch/vnc_sandboxes/{username}_{image_id}
    """
    return f"{USER_SANDBOX_BASE}/{username}_{image_id}"


def create_user_sandbox(username, image_id='xfce4', sif_image_path=None):
    """
    유저 전용 VNC 샌드박스 생성

    Args:
        username: 사용자 이름
        image_id: 이미지 ID (xfce4, gnome, gnome_lsprepost)
        sif_image_path: SIF 이미지 경로 (기본: BASE_VNC_IMAGE)

    Returns:
        tuple: (sandbox_path, created_new)
    """
    sandbox_path = get_user_sandbox_path(username, image_id)

    # SIF 이미지 경로 결정
    if sif_image_path is None:
        sif_image_path = BASE_VNC_IMAGE

    # 이미 존재하면 재사용
    if os.path.exists(sandbox_path):
        print(f"✅ 기존 샌드박스 재사용: {sandbox_path}")
        return (sandbox_path, False)

    # 기본 디렉토리 생성
    os.makedirs(USER_SANDBOX_BASE, mode=0o755, exist_ok=True)

    # 기본 이미지에서 복사 (writable sandbox)
    print(f"📦 새 샌드박스 생성 중: {sandbox_path}")
    print(f"   원본 이미지: {sif_image_path}")

    cmd = [
        APPTAINER, "build", "--sandbox",
        sandbox_path,
        sif_image_path
    ]

    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(f"✅ 샌드박스 생성 완료: {sandbox_path}")

        # 권한 설정 (755로 설정하여 Slurm Job에서 접근 가능)
        os.chmod(sandbox_path, 0o755)

        return (sandbox_path, True)

    except subprocess.CalledProcessError as e:
        print(f"❌ 샌드박스 생성 실패: {e.stderr}")
        raise


def get_sandbox_info(username, image_id='xfce4'):
    """
    유저의 VNC 샌드박스 정보 반환

    Args:
        username: 사용자 이름
        image_id: 이미지 ID

    Returns:
        dict: {
            'sandbox_path': str,
            'viz_node': str,
            'exists': bool,
            'size_mb': float,
            'image_id': str
        }
    """
    sandbox_path = get_user_sandbox_path(username, image_id)
    viz_node = get_assigned_viz_node(username)

    exists = os.path.exists(sandbox_path)
    size_mb = 0.0

    if exists:
        # 샌드박스 크기 계산
        try:
            result = subprocess.run(
                [DU, "-sm", sandbox_path],
                capture_output=True,
                text=True,
                check=True
            )
            size_mb = float(result.stdout.split()[0])
        except Exception:
            pass

    return {
        'sandbox_path': sandbox_path,
        'viz_node': viz_node,
        'exists': exists,
        'size_mb': size_mb,
        'image_id': image_id
    }


def delete_user_sandbox(username, image_id=None):
    """
    유저 샌드박스 삭제

    Args:
        username: 사용자 이름
        image_id: 특정 이미지 ID만 삭제 (None이면 모든 샌드박스 삭제)

    Returns:
        bool: 삭제 성공 여부
    """
    import shutil

    if image_id:
        # 특정 이미지 샌드박스만 삭제
        sandbox_path = get_user_sandbox_path(username, image_id)
        if os.path.exists(sandbox_path):
            shutil.rmtree(sandbox_path)
            print(f"🗑️  샌드박스 삭제 완료: {sandbox_path}")
            return True
    else:
        # 모든 샌드박스 삭제 (username_* 패턴)
        deleted = False
        import glob
        pattern = f"{USER_SANDBOX_BASE}/{username}_*"
        for sandbox_path in glob.glob(pattern):
            if os.path.exists(sandbox_path):
                shutil.rmtree(sandbox_path)
                print(f"🗑️  샌드박스 삭제 완료: {sandbox_path}")
                deleted = True
        return deleted

    return False


def list_all_sandboxes():
    """
    모든 유저 샌드박스 목록 반환

    Returns:
        list: [
            {
                'username': str,
                'image_id': str,
                'sandbox_path': str,
                'viz_node': str,
                'exists': bool,
                'size_mb': float
            }
        ]
    """
    sandboxes = []

    # /scratch/vnc_sandboxes 디렉토리 스캔
    sandbox_base = Path(USER_SANDBOX_BASE)
    if not sandbox_base.exists():
        return sandboxes

    for sandbox_dir in sandbox_base.iterdir():
        if sandbox_dir.is_dir():
            # 디렉토리 이름에서 username_image_id 파싱
            dir_name = sandbox_dir.name
            if '_' in dir_name:
                # username_image_id 형식
                parts = dir_name.rsplit('_', 1)
                if len(parts) == 2:
                    username, image_id = parts
                    info = get_sandbox_info(username, image_id)
                    if info['exists']:
                        sandboxes.append({
                            'username': username,
                            **info
                        })

    return sandboxes


if __name__ == "__main__":
    # 테스트
    import sys

    if len(sys.argv) < 2:
        print("Usage: python3 vnc_sandbox_manager.py <username> [image_id]")
        print("       image_id: xfce4, gnome, gnome_lsprepost (default: xfce4)")
        sys.exit(1)

    username = sys.argv[1]
    image_id = sys.argv[2] if len(sys.argv) > 2 else 'xfce4'

    print(f"\n=== VNC 샌드박스 관리 테스트 ===")
    print(f"사용자: {username}")
    print(f"이미지: {image_id}")
    print(f"VIZ_NODES: {VIZ_NODES}")
    print(f"BASE_VNC_IMAGE: {BASE_VNC_IMAGE}")
    print(f"USER_SANDBOX_BASE: {USER_SANDBOX_BASE}")
    print()

    # 정보 확인
    info = get_sandbox_info(username, image_id)
    print(f"할당된 viz-node: {info['viz_node']}")
    print(f"샌드박스 경로: {info['sandbox_path']}")
    print(f"존재 여부: {info['exists']}")

    # 샌드박스 생성 (테스트 시 주석 해제)
    # if not info['exists']:
    #     print("\n샌드박스 생성 중...")
    #     create_user_sandbox(username, image_id)
    # else:
    #     print(f"\n기존 샌드박스 크기: {info['size_mb']:.1f} MB")

    # 전체 목록
    print("\n=== 전체 샌드박스 목록 ===")
    for sb in list_all_sandboxes():
        print(f"  {sb['username']}_{sb['image_id']}: {sb['viz_node']} ({sb['size_mb']:.1f} MB)")
