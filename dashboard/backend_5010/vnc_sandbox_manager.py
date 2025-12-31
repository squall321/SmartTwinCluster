#!/usr/bin/env python3
"""
VNC 샌드박스 관리자
- 유저별 개인 VNC 샌드박스 생성
- viz-node sticky assignment
- 권한 관리
"""

import os
import subprocess
import hashlib
from pathlib import Path

# 시스템 명령어 절대 경로 (systemd 환경에서 PATH 제한)
APPTAINER = '/usr/bin/apptainer'
DU = '/usr/bin/du'

# 기본 이미지 경로
BASE_VNC_IMAGE = "/scratch/apptainers/visualization/vnc_desktop"

# 유저 샌드박스 베이스 경로
USER_SANDBOX_BASE = "/home/{username}/.vnc_sandboxes"

# viz-node 리스트 (프로덕션: 10개, 개발: 1개)
VIZ_NODES = ["viz-node001"]  # 프로덕션: viz-node[001-010]


def get_assigned_viz_node(username):
    """
    유저에게 고정된 viz-node 할당 (sticky assignment)
    해시 기반으로 항상 같은 노드 반환
    """
    # 유저명 해시로 노드 선택
    hash_value = int(hashlib.md5(username.encode()).hexdigest(), 16)
    node_index = hash_value % len(VIZ_NODES)
    return VIZ_NODES[node_index]


def get_user_sandbox_path(username):
    """유저 샌드박스 경로 반환"""
    return USER_SANDBOX_BASE.format(username=username)


def create_user_sandbox(username):
    """
    유저 전용 VNC 샌드박스 생성

    Returns:
        tuple: (sandbox_path, created_new)
    """
    sandbox_base = get_user_sandbox_path(username)
    sandbox_path = f"{sandbox_base}/my_desktop"

    # 이미 존재하면 재사용
    if os.path.exists(sandbox_path):
        print(f"✅ 기존 샌드박스 재사용: {sandbox_path}")
        return (sandbox_path, False)

    # 디렉토리 생성
    os.makedirs(sandbox_base, mode=0o700, exist_ok=True)

    # 기본 이미지에서 복사 (writable sandbox)
    print(f"📦 새 샌드박스 생성 중: {sandbox_path}")

    cmd = [
        APPTAINER, "build", "--sandbox",
        sandbox_path,
        BASE_VNC_IMAGE
    ]

    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(f"✅ 샌드박스 생성 완료: {sandbox_path}")

        # 권한 설정 (본인만 접근)
        os.chmod(sandbox_base, 0o700)
        os.chmod(sandbox_path, 0o700)

        return (sandbox_path, True)

    except subprocess.CalledProcessError as e:
        print(f"❌ 샌드박스 생성 실패: {e.stderr}")
        raise


def get_sandbox_info(username):
    """
    유저의 VNC 샌드박스 정보 반환

    Returns:
        dict: {
            'sandbox_path': str,
            'viz_node': str,
            'exists': bool,
            'size_mb': float
        }
    """
    sandbox_path = f"{get_user_sandbox_path(username)}/my_desktop"
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
        'size_mb': size_mb
    }


def delete_user_sandbox(username):
    """유저 샌드박스 삭제"""
    sandbox_base = get_user_sandbox_path(username)

    if os.path.exists(sandbox_base):
        import shutil
        shutil.rmtree(sandbox_base)
        print(f"🗑️  샌드박스 삭제 완료: {sandbox_base}")
        return True

    return False


def list_all_sandboxes():
    """모든 유저 샌드박스 목록 반환"""
    sandboxes = []

    home_dir = Path("/home")
    for user_dir in home_dir.iterdir():
        if user_dir.is_dir():
            sandbox_dir = user_dir / ".vnc_sandboxes"
            if sandbox_dir.exists():
                username = user_dir.name
                info = get_sandbox_info(username)
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
        print("Usage: python3 vnc_sandbox_manager.py <username>")
        sys.exit(1)

    username = sys.argv[1]

    print(f"\n=== VNC 샌드박스 관리 테스트: {username} ===\n")

    # 정보 확인
    info = get_sandbox_info(username)
    print(f"할당된 viz-node: {info['viz_node']}")
    print(f"샌드박스 경로: {info['sandbox_path']}")
    print(f"존재 여부: {info['exists']}")

    # 샌드박스 생성
    if not info['exists']:
        print("\n샌드박스 생성 중...")
        create_user_sandbox(username)
    else:
        print(f"\n기존 샌드박스 크기: {info['size_mb']:.1f} MB")

    # 전체 목록
    print("\n=== 전체 샌드박스 목록 ===")
    for sb in list_all_sandboxes():
        print(f"  {sb['username']}: {sb['viz_node']} ({sb['size_mb']:.1f} MB)")
