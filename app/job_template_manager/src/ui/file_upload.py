"""
File Upload Widget - 파일 업로드

파일 Drag & Drop, 검증, 상태 표시
"""

import logging
from pathlib import Path
from typing import Optional, Dict, List

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QGroupBox,
    QListWidget, QListWidgetItem, QPushButton, QLabel,
    QFileDialog, QMessageBox
)
from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QColor, QDragEnterEvent, QDropEvent

logger = logging.getLogger(__name__)


class FileUploadWidget(QWidget):
    """파일 업로드 위젯"""

    # 시그널 정의
    files_changed = pyqtSignal()  # 파일 목록 변경 시 발생

    def __init__(self, parent=None):
        super().__init__(parent)

        self.file_schema = None  # FileSchema 객체
        self.uploaded_files = {}  # {file_key: file_path}
        self.file_status = {}  # {file_key: 'valid'|'invalid'|'missing'}

        self.init_ui()

        logger.info("FileUploadWidget initialized")

    def init_ui(self):
        """UI 초기화"""
        layout = QVBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0)

        # 타이틀
        title_label = QLabel("파일 업로드")
        title_label.setStyleSheet("font-weight: bold; font-size: 11pt;")
        layout.addWidget(title_label)

        # Drag & Drop 영역
        self.create_drop_zone(layout)

        # 파일 목록
        self.create_file_list(layout)

        # 액션 버튼
        self.create_action_buttons(layout)

        # 상태 레이블
        self.status_label = QLabel("파일을 드래그하거나 '찾아보기' 버튼을 클릭하세요")
        self.status_label.setStyleSheet("color: gray; font-size: 9pt;")
        layout.addWidget(self.status_label)

        self.setLayout(layout)

        # Drag & Drop 활성화
        self.setAcceptDrops(True)

    def create_drop_zone(self, parent_layout):
        """Drag & Drop 영역 생성"""
        drop_zone = QGroupBox()
        drop_zone.setStyleSheet("""
            QGroupBox {
                border: 2px dashed #999;
                border-radius: 5px;
                background-color: #f9f9f9;
                min-height: 100px;
            }
        """)

        zone_layout = QVBoxLayout()
        zone_layout.setAlignment(Qt.AlignCenter)

        icon_label = QLabel("📁")
        icon_label.setStyleSheet("font-size: 32pt;")
        icon_label.setAlignment(Qt.AlignCenter)
        zone_layout.addWidget(icon_label)

        text_label = QLabel("파일을 여기에 드래그하세요")
        text_label.setStyleSheet("font-size: 10pt; color: #666;")
        text_label.setAlignment(Qt.AlignCenter)
        zone_layout.addWidget(text_label)

        drop_zone.setLayout(zone_layout)
        parent_layout.addWidget(drop_zone)

        self.drop_zone = drop_zone

    def create_file_list(self, parent_layout):
        """파일 목록 리스트"""
        list_label = QLabel("업로드된 파일:")
        list_label.setStyleSheet("font-weight: bold; margin-top: 10px;")
        parent_layout.addWidget(list_label)

        self.file_list = QListWidget()
        self.file_list.setMaximumHeight(200)
        self.file_list.setStyleSheet("""
            QListWidget::item {
                padding: 5px;
                border-bottom: 1px solid #eee;
            }
        """)
        parent_layout.addWidget(self.file_list)

    def create_action_buttons(self, parent_layout):
        """액션 버튼"""
        button_layout = QHBoxLayout()

        self.browse_button = QPushButton("📂 찾아보기")
        self.browse_button.clicked.connect(self.browse_files)
        button_layout.addWidget(self.browse_button)

        self.clear_button = QPushButton("🗑️ 전체 삭제")
        self.clear_button.clicked.connect(self.clear_all_files)
        self.clear_button.setEnabled(False)
        button_layout.addWidget(self.clear_button)

        button_layout.addStretch()

        parent_layout.addLayout(button_layout)

    def dragEnterEvent(self, event: QDragEnterEvent):
        """Drag Enter 이벤트"""
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self.drop_zone.setStyleSheet("""
                QGroupBox {
                    border: 2px dashed #4CAF50;
                    border-radius: 5px;
                    background-color: #e8f5e9;
                    min-height: 100px;
                }
            """)
            logger.debug("Drag entered")

    def dragLeaveEvent(self, event):
        """Drag Leave 이벤트"""
        self.drop_zone.setStyleSheet("""
            QGroupBox {
                border: 2px dashed #999;
                border-radius: 5px;
                background-color: #f9f9f9;
                min-height: 100px;
            }
        """)
        logger.debug("Drag left")

    def dropEvent(self, event: QDropEvent):
        """Drop 이벤트"""
        self.drop_zone.setStyleSheet("""
            QGroupBox {
                border: 2px dashed #999;
                border-radius: 5px;
                background-color: #f9f9f9;
                min-height: 100px;
            }
        """)

        urls = event.mimeData().urls()
        file_paths = [Path(url.toLocalFile()) for url in urls if url.isLocalFile()]

        logger.info(f"Dropped {len(file_paths)} files")

        for file_path in file_paths:
            if file_path.is_file():
                self.add_file(file_path)

        event.acceptProposedAction()

    def browse_files(self):
        """파일 찾아보기 다이얼로그"""
        file_paths, _ = QFileDialog.getOpenFileNames(
            self,
            "파일 선택",
            str(Path.home()),
            "All Files (*.*)"
        )

        for file_path_str in file_paths:
            file_path = Path(file_path_str)
            self.add_file(file_path)

        logger.info(f"Selected {len(file_paths)} files from browser")

    def add_file(self, file_path: Path):
        """
        파일 추가 및 검증

        Args:
            file_path: 파일 경로
        """
        if not file_path.exists():
            logger.warning(f"File does not exist: {file_path}")
            return

        # 파일 스키마가 없으면 자동 매핑
        if not self.file_schema:
            file_key = self.generate_file_key(file_path)
            self.uploaded_files[file_key] = file_path
            self.file_status[file_key] = 'valid'
            self.update_file_list()
            logger.info(f"File added without schema: {file_path.name} -> {file_key}")
            return

        # 파일 스키마가 있으면 검증
        validation_result = self.validate_file(file_path)

        if validation_result['valid']:
            file_key = validation_result['file_key']
            self.uploaded_files[file_key] = file_path
            self.file_status[file_key] = 'valid'
            logger.info(f"File added: {file_path.name} -> {file_key}")
        else:
            # 검증 실패 시 임시 키로 추가 (사용자가 수동 매핑 가능하도록)
            file_key = self.generate_file_key(file_path)
            self.uploaded_files[file_key] = file_path
            self.file_status[file_key] = 'invalid'
            logger.warning(f"File validation failed: {file_path.name} - {validation_result['reason']}")

        self.update_file_list()
        self.files_changed.emit()

    def generate_file_key(self, file_path: Path) -> str:
        """
        파일 키 자동 생성

        Args:
            file_path: 파일 경로

        Returns:
            file_key (예: 'training_script', 'dataset', 'config')
        """
        # 파일명을 스네이크케이스로 변환
        name = file_path.stem.lower().replace(' ', '_').replace('-', '_')
        return name

    def validate_file(self, file_path: Path) -> Dict:
        """
        파일 검증

        Args:
            file_path: 파일 경로

        Returns:
            {
                'valid': bool,
                'file_key': str,
                'reason': str (실패 시)
            }
        """
        if not self.file_schema:
            return {'valid': True, 'file_key': self.generate_file_key(file_path)}

        # Required files 검사
        for file_def in self.file_schema.required:
            if self.matches_file_definition(file_path, file_def):
                return {'valid': True, 'file_key': file_def.file_key}

        # Optional files 검사
        for file_def in self.file_schema.optional:
            if self.matches_file_definition(file_path, file_def):
                return {'valid': True, 'file_key': file_def.file_key}

        # 매칭 실패
        return {
            'valid': False,
            'file_key': self.generate_file_key(file_path),
            'reason': '템플릿 스키마와 일치하는 파일 정의를 찾을 수 없습니다.'
        }

    def matches_file_definition(self, file_path: Path, file_def) -> bool:
        """
        파일이 FileDefinition과 일치하는지 확인

        Args:
            file_path: 파일 경로
            file_def: FileDefinition 객체

        Returns:
            일치 여부
        """
        # 확장자 검사
        extensions = file_def.validation.get('extensions', [])
        if extensions:
            if file_path.suffix not in extensions:
                return False

        # 파일 크기 검사
        if file_def.max_size:
            max_bytes = self.parse_file_size(file_def.max_size)
            actual_bytes = file_path.stat().st_size
            if actual_bytes > max_bytes:
                return False

        return True

    def parse_file_size(self, size_str: str) -> int:
        """
        파일 크기 문자열을 바이트로 변환

        Args:
            size_str: "10MB", "1GB" 등

        Returns:
            바이트 수
        """
        size_str = size_str.upper().strip()
        units = {
            'B': 1,
            'KB': 1024,
            'MB': 1024 ** 2,
            'GB': 1024 ** 3,
            'TB': 1024 ** 4,
        }

        for unit, multiplier in units.items():
            if size_str.endswith(unit):
                number = float(size_str[:-len(unit)])
                return int(number * multiplier)

        # 단위 없으면 바이트로 가정
        return int(size_str)

    def update_file_list(self):
        """파일 목록 UI 업데이트"""
        self.file_list.clear()

        # 업로드된 파일 표시
        for file_key, file_path in self.uploaded_files.items():
            status = self.file_status.get(file_key, 'unknown')

            if status == 'valid':
                icon = "✓"
                color = QColor(76, 175, 80)  # Green
                status_text = "유효"
            elif status == 'invalid':
                icon = "✗"
                color = QColor(244, 67, 54)  # Red
                status_text = "검증 실패"
            else:
                icon = "?"
                color = QColor(158, 158, 158)  # Gray
                status_text = "알 수 없음"

            item = QListWidgetItem(f"{icon} [{file_key}] {file_path.name} ({status_text})")
            item.setForeground(color)
            item.setData(Qt.UserRole, file_key)
            self.file_list.addItem(item)

        # 버튼 상태 업데이트
        self.clear_button.setEnabled(len(self.uploaded_files) > 0)

        # 상태 레이블 업데이트
        if len(self.uploaded_files) == 0:
            self.status_label.setText("파일을 드래그하거나 '찾아보기' 버튼을 클릭하세요")
            self.status_label.setStyleSheet("color: gray; font-size: 9pt;")
        else:
            valid_count = sum(1 for s in self.file_status.values() if s == 'valid')
            total_count = len(self.uploaded_files)
            self.status_label.setText(f"{valid_count}/{total_count} 파일 유효")

            if valid_count == total_count:
                self.status_label.setStyleSheet("color: green; font-size: 9pt;")
            else:
                self.status_label.setStyleSheet("color: orange; font-size: 9pt;")

    def clear_all_files(self):
        """모든 파일 삭제"""
        reply = QMessageBox.question(
            self,
            "파일 삭제",
            "모든 파일을 삭제하시겠습니까?",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )

        if reply == QMessageBox.Yes:
            self.uploaded_files.clear()
            self.file_status.clear()
            self.update_file_list()
            self.files_changed.emit()
            logger.info("All files cleared")

    def set_file_schema(self, file_schema):
        """
        파일 스키마 설정

        Args:
            file_schema: FileSchema 객체
        """
        self.file_schema = file_schema
        logger.info(f"File schema set: {len(file_schema.required)} required, {len(file_schema.optional)} optional")

        # 기존 파일 재검증
        if self.uploaded_files:
            for file_key in list(self.uploaded_files.keys()):
                file_path = self.uploaded_files[file_key]
                validation_result = self.validate_file(file_path)
                self.file_status[file_key] = 'valid' if validation_result['valid'] else 'invalid'

            self.update_file_list()

    def get_uploaded_files(self) -> Dict[str, Path]:
        """
        업로드된 파일 반환

        Returns:
            {file_key: file_path}
        """
        return self.uploaded_files.copy()

    def get_file_variables(self) -> Dict[str, str]:
        """
        파일 환경 변수 생성

        Returns:
            {
                'FILE_TRAINING_SCRIPT': '/path/to/script.py',
                'FILE_DATASET': '/path/to/dataset.tar.gz',
                ...
            }
        """
        file_vars = {}

        for file_key, file_path in self.uploaded_files.items():
            # 파일 키를 환경 변수명으로 변환 (FILE_TRAINING_SCRIPT)
            var_name = f"FILE_{file_key.upper()}"
            file_vars[var_name] = str(file_path.absolute())

        return file_vars

    def check_required_files(self) -> bool:
        """
        필수 파일이 모두 업로드되었는지 확인

        Returns:
            모든 필수 파일이 업로드되었으면 True
        """
        if not self.file_schema:
            return True

        for file_def in self.file_schema.required:
            if file_def.file_key not in self.uploaded_files:
                logger.warning(f"Required file missing: {file_def.file_key}")
                return False

            if self.file_status.get(file_def.file_key) != 'valid':
                logger.warning(f"Required file invalid: {file_def.file_key}")
                return False

        return True
