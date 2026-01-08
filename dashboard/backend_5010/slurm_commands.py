"""
Slurm 명령어 경로 설정 모듈
모든 Slurm 명령어에 대한 경로를 중앙에서 관리

IMPORTANT: systemd/gunicorn 환경에서는 PATH가 제한적이므로
반드시 절대 경로를 사용해야 함
"""

import os
import subprocess
from typing import List, Optional

# Slurm 설치 경로 (환경변수로 override 가능)
# 기본값: /usr/bin (apt/yum 패키지 설치 환경)
# 소스 빌드: /usr/local/slurm/bin
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')

# 시스템 명령어 경로 (절대 경로 필수 - systemd 환경에서 PATH 제한)
SUDO = '/usr/bin/sudo'
SSH = '/usr/bin/ssh'
KILL = '/bin/kill'
RM = '/bin/rm'
DF = '/bin/df'
LS = '/bin/ls'

# SSH 키 설정 (웹 서비스가 다른 사용자로 실행될 때를 위해)
def get_ssh_key_path():
    """SSH 키 경로 자동 탐지"""
    import pwd

    # 1. 환경변수로 명시적 지정
    env_key = os.getenv('SSH_KEY_FILE') or os.getenv('SSH_KEY_PATH')
    if env_key and os.path.exists(env_key):
        return env_key

    # 2. SUDO_USER가 있으면 그 사용자의 키 사용
    sudo_user = os.getenv('SUDO_USER')
    if sudo_user:
        try:
            user_home = pwd.getpwnam(sudo_user).pw_dir
            key_path = os.path.join(user_home, '.ssh', 'id_rsa')
            if os.path.exists(key_path):
                return key_path
        except KeyError:
            pass

    # 3. 현재 사용자의 홈 디렉토리에서 탐색
    home = os.path.expanduser('~')
    key_path = os.path.join(home, '.ssh', 'id_rsa')
    if os.path.exists(key_path):
        return key_path

    # 4. 일반적인 서비스 계정 경로
    for user in ['koopark', 'hpcadmin', 'slurm']:
        try:
            user_home = pwd.getpwnam(user).pw_dir
            key_path = os.path.join(user_home, '.ssh', 'id_rsa')
            if os.path.exists(key_path):
                return key_path
        except KeyError:
            continue

    return None

# SSH 키 경로 (모듈 로드 시 한 번만 탐지)
SSH_KEY_PATH = get_ssh_key_path()

def get_ssh_opts(include_key=True):
    """SSH 공통 옵션 반환"""
    opts = [
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', 'LogLevel=ERROR',
        '-o', 'BatchMode=yes',
    ]
    if include_key and SSH_KEY_PATH:
        opts = ['-i', SSH_KEY_PATH] + opts
    return opts

def run_ssh_command(node: str, remote_cmd: str, timeout: int = 30,
                    connect_timeout: int = 5) -> subprocess.CompletedProcess:
    """
    SSH 명령어 실행 헬퍼 함수

    Args:
        node: 대상 노드 (호스트명 또는 IP)
        remote_cmd: 원격에서 실행할 명령어
        timeout: 전체 타임아웃 (초)
        connect_timeout: SSH 연결 타임아웃 (초)

    Returns:
        subprocess.CompletedProcess
    """
    cmd = [SSH] + get_ssh_opts() + [
        '-o', f'ConnectTimeout={connect_timeout}',
        node,
        remote_cmd
    ]

    try:
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
    except subprocess.TimeoutExpired:
        print(f"⚠️  SSH timeout: {node}")
        raise
    except Exception as e:
        print(f"❌ SSH failed to {node}: {e}")
        raise

# 명령어 경로
SINFO = os.path.join(SLURM_BIN_DIR, 'sinfo')
SQUEUE = os.path.join(SLURM_BIN_DIR, 'squeue')
SACCT = os.path.join(SLURM_BIN_DIR, 'sacct')
SCONTROL = os.path.join(SLURM_BIN_DIR, 'scontrol')
SACCTMGR = os.path.join(SLURM_BIN_DIR, 'sacctmgr')
SBATCH = os.path.join(SLURM_BIN_DIR, 'sbatch')
SCANCEL = os.path.join(SLURM_BIN_DIR, 'scancel')
SREPORT = os.path.join(SLURM_BIN_DIR, 'sreport')
SRUN = os.path.join(SLURM_BIN_DIR, 'srun')

def run_slurm_command(command: List[str], timeout: int = 10, 
                      use_sudo: bool = False, check: bool = True) -> subprocess.CompletedProcess:
    """
    Slurm 명령어 실행 헬퍼 함수
    
    Args:
        command: 명령어 리스트 (첫 번째는 명령어 경로)
        timeout: 타임아웃 (초)
        use_sudo: sudo 사용 여부
        check: 실패 시 예외 발생 여부
        
    Returns:
        subprocess.CompletedProcess
    """
    if use_sudo:
        command = [SUDO, '-n'] + command
    
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=check
        )
        return result
    except subprocess.TimeoutExpired:
        print(f"⚠️  Command timeout: {' '.join(command)}")
        raise
    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed: {' '.join(command)}")
        print(f"   Return code: {e.returncode}")
        print(f"   Stderr: {e.stderr}")
        if check:
            # stderr를 포함한 더 명확한 에러 메시지
            error_msg = f"Command failed (exit {e.returncode})"
            if e.stderr:
                error_msg += f": {e.stderr.strip()}"
            raise RuntimeError(error_msg) from None
        return e
    except FileNotFoundError:
        print(f"❌ Command not found: {command[0]}")
        print(f"   Make sure Slurm is installed at {SLURM_BIN_DIR}")
        raise


def check_slurm_installation() -> bool:
    """
    Slurm 설치 여부 확인
    
    Returns:
        설치되어 있으면 True
    """
    try:
        result = run_slurm_command([SINFO, '--version'], timeout=5, check=False)
        if result.returncode == 0:
            print(f"✅ Slurm found: {result.stdout.strip()}")
            return True
        else:
            print(f"❌ Slurm check failed: {result.stderr}")
            return False
    except Exception as e:
        print(f"❌ Slurm not found at {SLURM_BIN_DIR}: {e}")
        return False


def get_sinfo(*args, **kwargs) -> subprocess.CompletedProcess:
    """sinfo 실행"""
    return run_slurm_command([SINFO] + list(args), **kwargs)


def get_squeue(*args, **kwargs) -> subprocess.CompletedProcess:
    """squeue 실행"""
    return run_slurm_command([SQUEUE] + list(args), **kwargs)


def get_sacct(*args, **kwargs) -> subprocess.CompletedProcess:
    """sacct 실행"""
    return run_slurm_command([SACCT] + list(args), **kwargs)


def get_scontrol(*args, **kwargs) -> subprocess.CompletedProcess:
    """scontrol 실행"""
    return run_slurm_command([SCONTROL] + list(args), **kwargs)


def get_sacctmgr(*args, use_sudo: bool = True, **kwargs) -> subprocess.CompletedProcess:
    """sacctmgr 실행 (기본적으로 sudo 사용)"""
    return run_slurm_command([SACCTMGR] + list(args), use_sudo=use_sudo, **kwargs)


def get_sreport(*args, **kwargs) -> subprocess.CompletedProcess:
    """sreport 실행"""
    return run_slurm_command([SREPORT] + list(args), **kwargs)


# 테스트 코드
if __name__ == '__main__':
    print("Testing Slurm command paths...")
    print(f"SLURM_BIN_DIR: {SLURM_BIN_DIR}")
    print()
    
    # 설치 확인
    if check_slurm_installation():
        print("\n✅ All checks passed!")
        
        # 간단한 명령어 테스트
        print("\nTesting basic commands:")
        
        try:
            result = get_sinfo('--version')
            print(f"sinfo version: {result.stdout.strip()}")
        except Exception as e:
            print(f"❌ sinfo failed: {e}")
        
        try:
            result = get_squeue('--version')
            print(f"squeue version: {result.stdout.strip()}")
        except Exception as e:
            print(f"❌ squeue failed: {e}")
    else:
        print("\n❌ Slurm installation check failed!")
