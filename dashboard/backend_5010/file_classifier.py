"""
File Classifier
업로드된 파일을 타입별로 분류하는 서비스

파일 확장자와 내용을 분석하여 다음과 같이 분류:
- data: 시뮬레이션 데이터 파일
- config: 설정/옵션 파일
- script: 스크립트 파일
- model: 모델 파일
- mesh: 메쉬 파일
- result: 결과 파일
"""

import os
import mimetypes
from pathlib import Path
from typing import Dict, Optional
import logging

logger = logging.getLogger(__name__)


class FileClassifier:
    """
    파일 분류 서비스

    확장자와 MIME 타입을 기반으로 파일을 분류합니다.
    """

    # 파일 타입별 확장자 매핑
    FILE_TYPE_PATTERNS = {
        'data': [
            # 일반 데이터
            '.dat', '.txt', '.csv', '.tsv', '.json', '.xml',
            # 압축 파일
            '.tar', '.gz', '.zip', '.bz2', '.xz', '.7z', '.tar.gz', '.tgz',
            # 이미지 데이터
            '.png', '.jpg', '.jpeg', '.bmp', '.tif', '.tiff',
            # 과학 데이터
            '.hdf5', '.h5', '.nc', '.cdf', '.fits',
            # 바이너리 데이터
            '.bin', '.raw'
        ],
        'config': [
            # 설정 파일
            '.yaml', '.yml', '.json', '.toml', '.ini', '.conf', '.cfg',
            # XML 설정
            '.xml', '.properties',
            # 환경 변수
            '.env', '.envrc'
        ],
        'script': [
            # Python
            '.py', '.pyc', '.pyx',
            # Shell
            '.sh', '.bash', '.zsh', '.fish',
            # 기타 스크립트
            '.js', '.ts', '.lua', '.pl', '.rb',
            # Slurm
            '.sbatch', '.slurm'
        ],
        'model': [
            # 딥러닝 모델
            '.pth', '.pt', '.ckpt', '.pb', '.h5', '.hdf5',
            '.onnx', '.tflite', '.caffemodel',
            # 기타 모델
            '.pkl', '.pickle', '.joblib', '.model'
        ],
        'mesh': [
            # 메쉬 파일
            '.msh', '.mesh', '.ugrid', '.cgns',
            '.stl', '.obj', '.ply', '.vtk', '.vtu',
            # OpenFOAM
            '.foam', '.blockMesh'
        ],
        'result': [
            # 결과 파일
            '.out', '.log', '.res', '.result',
            # VTK 결과
            '.vtk', '.vtu', '.vtp', '.vti',
            # 플롯 데이터
            '.plt', '.dat'
        ],
        'document': [
            # 문서
            '.pdf', '.doc', '.docx', '.txt', '.md', '.rst',
            # 스프레드시트
            '.xls', '.xlsx', '.csv',
            # 프레젠테이션
            '.ppt', '.pptx'
        ],
        'code': [
            # C/C++
            '.c', '.cpp', '.cc', '.cxx', '.h', '.hpp',
            # Fortran
            '.f', '.f90', '.f95', '.for',
            # Python
            '.py', '.pyx',
            # 기타
            '.java', '.cu', '.cuh'
        ]
    }

    def __init__(self):
        """파일 분류기 초기화"""
        # MIME 타입 초기화
        mimetypes.init()

    def classify_file(self, filename: str, file_path: Optional[str] = None) -> Dict:
        """
        파일 분류

        Args:
            filename: 파일명
            file_path: 파일 전체 경로 (선택적, 크기 확인용)

        Returns:
            {
                'type': str,           # 파일 타입
                'extension': str,      # 확장자
                'mime_type': str,      # MIME 타입
                'size': int,           # 파일 크기 (bytes)
                'is_binary': bool,     # 바이너리 파일 여부
                'is_compressed': bool  # 압축 파일 여부
            }
        """
        # 파일명에서 확장자 추출
        file_ext = Path(filename).suffix.lower()

        # 복합 확장자 처리 (.tar.gz 등)
        if filename.endswith('.tar.gz'):
            file_ext = '.tar.gz'
        elif filename.endswith('.tar.bz2'):
            file_ext = '.tar.bz2'

        # 파일 타입 결정
        file_type = self._determine_type(file_ext)

        # MIME 타입
        mime_type, _ = mimetypes.guess_type(filename)

        # 파일 크기
        file_size = 0
        if file_path and os.path.exists(file_path):
            file_size = os.path.getsize(file_path)

        # 바이너리 파일 여부
        is_binary = self._is_binary_file(file_ext, mime_type)

        # 압축 파일 여부
        is_compressed = self._is_compressed_file(file_ext)

        return {
            'type': file_type,
            'extension': file_ext,
            'mime_type': mime_type or 'application/octet-stream',
            'size': file_size,
            'is_binary': is_binary,
            'is_compressed': is_compressed
        }

    def _determine_type(self, extension: str) -> str:
        """
        확장자로부터 파일 타입 결정

        Args:
            extension: 파일 확장자

        Returns:
            파일 타입 문자열
        """
        for file_type, extensions in self.FILE_TYPE_PATTERNS.items():
            if extension in extensions:
                return file_type

        # 기본값
        return 'data'

    def _is_binary_file(self, extension: str, mime_type: Optional[str]) -> bool:
        """
        바이너리 파일 여부 확인

        Args:
            extension: 파일 확장자
            mime_type: MIME 타입

        Returns:
            바이너리 파일 여부
        """
        # 텍스트 확장자
        text_extensions = [
            '.txt', '.csv', '.json', '.xml', '.yaml', '.yml',
            '.py', '.sh', '.bash', '.c', '.cpp', '.h', '.f90',
            '.md', '.rst', '.log', '.conf', '.cfg', '.ini'
        ]

        if extension in text_extensions:
            return False

        # MIME 타입으로 판단
        if mime_type:
            if mime_type.startswith('text/'):
                return False
            if 'json' in mime_type or 'xml' in mime_type:
                return False

        return True

    def _is_compressed_file(self, extension: str) -> bool:
        """
        압축 파일 여부 확인

        Args:
            extension: 파일 확장자

        Returns:
            압축 파일 여부
        """
        compressed_extensions = [
            '.gz', '.zip', '.bz2', '.xz', '.7z', '.tar', '.tgz',
            '.tar.gz', '.tar.bz2', '.rar'
        ]

        return extension in compressed_extensions

    def validate_file(
        self,
        filename: str,
        max_size: Optional[int] = None,
        allowed_types: Optional[list] = None,
        allowed_extensions: Optional[list] = None
    ) -> Dict:
        """
        파일 유효성 검증

        Args:
            filename: 파일명
            max_size: 최대 파일 크기 (bytes)
            allowed_types: 허용된 파일 타입 리스트
            allowed_extensions: 허용된 확장자 리스트

        Returns:
            {
                'valid': bool,
                'message': str,
                'file_info': dict
            }
        """
        file_info = self.classify_file(filename)

        # 확장자 검증
        if allowed_extensions:
            if file_info['extension'] not in allowed_extensions:
                return {
                    'valid': False,
                    'message': f"Extension {file_info['extension']} not allowed",
                    'file_info': file_info
                }

        # 파일 타입 검증
        if allowed_types:
            if file_info['type'] not in allowed_types:
                return {
                    'valid': False,
                    'message': f"File type {file_info['type']} not allowed",
                    'file_info': file_info
                }

        # 파일 크기 검증
        if max_size and file_info['size'] > max_size:
            return {
                'valid': False,
                'message': f"File size {file_info['size']} exceeds max {max_size}",
                'file_info': file_info
            }

        return {
            'valid': True,
            'message': 'File is valid',
            'file_info': file_info
        }

    def get_storage_path(self, file_type: str, user_id: str, job_id: Optional[str] = None) -> str:
        """
        파일 타입과 사용자에 따른 저장 경로 결정

        Args:
            file_type: 파일 타입
            user_id: 사용자 ID
            job_id: 작업 ID (선택적)

        Returns:
            저장 경로
        """
        base_path = "/shared/uploads"

        if job_id:
            # Job별 저장
            storage_path = os.path.join(base_path, "jobs", job_id, file_type)
        else:
            # 사용자별 저장
            storage_path = os.path.join(base_path, "users", user_id, file_type)

        return storage_path

    def parse_size_string(self, size_str: str) -> int:
        """
        크기 문자열을 bytes로 변환

        Args:
            size_str: 크기 문자열 (예: "10MB", "1GB")

        Returns:
            bytes 단위 크기
        """
        size_str = size_str.strip().upper()

        units = {
            'B': 1,
            'KB': 1024,
            'MB': 1024 ** 2,
            'GB': 1024 ** 3,
            'TB': 1024 ** 4
        }

        for unit, multiplier in units.items():
            if size_str.endswith(unit):
                size_value = float(size_str[:-len(unit)])
                return int(size_value * multiplier)

        # 단위가 없으면 bytes로 간주
        return int(size_str)

    def validate_file_security(self, filename: str, file_path: Optional[str] = None) -> Dict:
        """
        파일 보안 검증

        실행 파일, 위험한 스크립트, 의심스러운 파일 등을 차단합니다.

        Args:
            filename: 파일명
            file_path: 파일 전체 경로 (선택적, 내용 검증용)

        Returns:
            {
                'safe': bool,           # 안전 여부
                'reason': str,          # 차단 이유 (안전하지 않을 경우)
                'risk_level': str,      # 위험 수준 ('safe', 'low', 'medium', 'high')
                'recommendations': list # 권장 사항
            }
        """
        file_ext = Path(filename).suffix.lower()

        # 위험 수준별 확장자
        BLOCKED_EXTENSIONS = {
            'high': [
                # 실행 파일
                '.exe', '.dll', '.so', '.dylib', '.app',
                # Windows 위험 스크립트
                '.bat', '.cmd', '.vbs', '.vbe', '.wsf', '.wsh',
                # PowerShell
                '.ps1', '.psm1', '.psd1',
                # 기타 위험 파일
                '.scr', '.com', '.pif', '.msi', '.jar'
            ],
            'medium': [
                # 압축 파일 (내부 검증 필요)
                '.zip', '.rar', '.7z', '.tar.gz', '.tgz',
                # 매크로 포함 문서
                '.docm', '.xlsm', '.pptm'
            ]
        }

        # 허용된 스크립트 확장자 (HPC 환경에서 필요)
        ALLOWED_SCRIPT_EXTENSIONS = [
            '.sh', '.bash', '.zsh', '.fish',  # Shell scripts
            '.py', '.pyc', '.pyx',            # Python
            '.sbatch', '.slurm',              # Slurm
            '.f', '.f90', '.f95',             # Fortran
            '.c', '.cpp', '.cu',              # C/C++/CUDA
            '.lua', '.pl', '.rb', '.js'       # Other scripts
        ]

        recommendations = []

        # HIGH 위험 확장자 차단
        if file_ext in BLOCKED_EXTENSIONS['high']:
            # 단, HPC에서 필요한 스크립트는 허용
            if file_ext not in ALLOWED_SCRIPT_EXTENSIONS:
                return {
                    'safe': False,
                    'reason': f'Blocked file extension: {file_ext}. Executable files and dangerous scripts are not allowed.',
                    'risk_level': 'high',
                    'recommendations': [
                        'If this is a legitimate script, please use an allowed extension (.sh, .py, .sbatch)',
                        'Contact administrator if this file type is required for your workflow'
                    ]
                }

        # MEDIUM 위험 파일 - 경고와 함께 허용
        if file_ext in BLOCKED_EXTENSIONS['medium']:
            recommendations.append(f'Compressed file detected: {file_ext}. Ensure contents are safe.')
            recommendations.append('Avoid uploading archives containing executables or suspicious files.')

            return {
                'safe': True,  # 허용하되 경고
                'reason': '',
                'risk_level': 'medium',
                'recommendations': recommendations
            }

        # 파일명 패턴 검증
        suspicious_patterns = [
            'virus', 'malware', 'trojan', 'backdoor', 'keylog',
            'ransomware', 'rootkit', 'exploit'
        ]

        filename_lower = filename.lower()
        for pattern in suspicious_patterns:
            if pattern in filename_lower:
                return {
                    'safe': False,
                    'reason': f'Suspicious filename pattern detected: {pattern}',
                    'risk_level': 'high',
                    'recommendations': [
                        'Rename the file to remove suspicious keywords',
                        'Ensure the file is legitimate and safe'
                    ]
                }

        # 파일 크기 검증 (비정상적으로 작은 파일 의심)
        if file_path and os.path.exists(file_path):
            file_size = os.path.getsize(file_path)

            # 0 바이트 파일 차단
            if file_size == 0:
                return {
                    'safe': False,
                    'reason': 'Empty file (0 bytes) is not allowed',
                    'risk_level': 'low',
                    'recommendations': ['Ensure the file has valid content']
                }

            # 비정상적으로 큰 파일 경고 (50GB 이상)
            max_size = 50 * 1024 * 1024 * 1024  # 50GB
            if file_size > max_size:
                return {
                    'safe': False,
                    'reason': f'File size ({file_size / (1024**3):.2f} GB) exceeds maximum allowed size (50 GB)',
                    'risk_level': 'medium',
                    'recommendations': [
                        'Split large files into smaller chunks',
                        'Contact administrator for large file transfer alternatives'
                    ]
                }

        # 모든 검증 통과
        return {
            'safe': True,
            'reason': '',
            'risk_level': 'safe',
            'recommendations': []
        }


# 전역 인스턴스
_classifier_instance = None


def get_file_classifier() -> FileClassifier:
    """
    FileClassifier 싱글톤 인스턴스 반환

    Returns:
        FileClassifier 인스턴스
    """
    global _classifier_instance

    if _classifier_instance is None:
        _classifier_instance = FileClassifier()

    return _classifier_instance
