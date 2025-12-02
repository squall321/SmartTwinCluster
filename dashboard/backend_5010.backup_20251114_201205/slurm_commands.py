"""
Slurm 명령어 경로 설정 모듈
모든 Slurm 명령어에 대한 경로를 중앙에서 관리
"""

import os
import subprocess
from typing import List, Optional

# Slurm 설치 경로 (환경변수로 override 가능)
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')

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
        command = ['sudo'] + command
    
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
            raise
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
