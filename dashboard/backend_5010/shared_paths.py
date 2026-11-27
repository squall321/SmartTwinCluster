# 잡 업로드·로그 위치 — 모든 계산 노드가 보는 곳이어야 한다(SH-01·02). 작업 폴더는 노드 디스크(SH-03)
"""SHARED_BASE(/shared)는 헤드에만 붙은 볼륨이라 계산 노드가 못 본다(운영 11-27 확인).
올린 입력(잡 시작 때 계산 노드가 cp)과 잡 로그(계산 노드가 쓰고 헤드 로그 보기가 읽음)는
모든 노드가 보는 곳(운영은 /data 아래 NFS)에 둔다. 기본값은 예전과 같아 환경값이 없으면 동작이 그대로다.
"""
import os

SHARED_BASE = os.getenv('SHARED_BASE', '/shared')
UPLOAD_BASE = os.getenv('UPLOAD_BASE', SHARED_BASE)                       # SH-01
JOB_LOGS_DIR = os.getenv('JOB_LOGS_DIR', os.path.join(SHARED_BASE, 'logs'))  # SH-02


def ensure_dir(path: str) -> str:
    """폴더를 만들고 쓸 수 있는지 본다. 못 하면 /tmp 로 물러나지 않고 RuntimeError(SH-04) —
    헤드 로컬 /tmp 는 계산 노드가 못 봐서 잡이 결국 복사·로그 단계에서 실패한다."""
    try:
        os.makedirs(path, exist_ok=True)
    except OSError as e:
        raise RuntimeError(f"잡 폴더를 만들 수 없다: {path} — {e}. "
                           f"UPLOAD_BASE·JOB_LOGS_DIR(.env)와 폴더 소유를 확인할 것") from e
    if not os.access(path, os.W_OK | os.X_OK):
        raise RuntimeError(f"잡 폴더에 쓸 수 없다: {path} — 실행 계정의 소유·권한을 확인할 것")
    return path
