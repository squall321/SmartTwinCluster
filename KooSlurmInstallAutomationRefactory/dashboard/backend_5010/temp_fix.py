def run_slurm_command(command, mock_response=None, use_sudo=False):
    """
    Slurm 명령어 실행 (Mock 모드 지원)
    
    Args:
        command: 실행할 명령어 리스트
        mock_response: Mock 모드에서 반환할 응답
        use_sudo: sudo 권한으로 실행 여부
    """
    if MOCK_MODE and mock_response is not None:
        logger.info(f"🎭 Mock mode: {' '.join(command)}")
        return True, mock_response, ""
    
    try:
        # sudo 권한이 필요한 경우
        if use_sudo:
            command = ['sudo'] + command
            logger.info(f"Running with sudo: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timeout"
    except Exception as e:
        return False, "", str(e)
