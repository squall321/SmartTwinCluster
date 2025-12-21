"""
Script Preview Dialog - 스크립트 미리보기

생성된 Slurm 배치 스크립트를 미리보기하고 편집/복사 가능
"""

import logging
from pathlib import Path
from typing import Optional

from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QTextEdit,
    QPushButton, QLabel, QFileDialog, QMessageBox
)
from PyQt5.QtCore import Qt, QSize
from PyQt5.QtGui import QFont, QTextCursor, QClipboard
from PyQt5.QtWidgets import QApplication

logger = logging.getLogger(__name__)


class ScriptPreviewDialog(QDialog):
    """스크립트 미리보기 다이얼로그"""

    def __init__(self, script_content: str, parent=None):
        """
        초기화

        Args:
            script_content: 스크립트 내용
            parent: 부모 위젯
        """
        super().__init__(parent)

        self.script_content = script_content
        self.is_modified = False

        self.init_ui()
        self.load_script()

        logger.info("ScriptPreviewDialog initialized")

    def init_ui(self):
        """UI 초기화"""
        self.setWindowTitle("Slurm Script Preview")
        self.setMinimumSize(QSize(800, 600))

        layout = QVBoxLayout()

        # 타이틀
        title_layout = QHBoxLayout()
        title_label = QLabel("📄 Slurm Batch Script")
        title_label.setStyleSheet("font-size: 14pt; font-weight: bold;")
        title_layout.addWidget(title_label)

        # 스크립트 크기 표시
        self.size_label = QLabel()
        self.size_label.setStyleSheet("color: gray; font-size: 9pt;")
        title_layout.addWidget(self.size_label)

        title_layout.addStretch()
        layout.addLayout(title_layout)

        # 스크립트 편집기
        self.script_editor = QTextEdit()
        self.script_editor.setFont(QFont("Courier New", 10))
        self.script_editor.setLineWrapMode(QTextEdit.NoWrap)
        self.script_editor.textChanged.connect(self.on_script_modified)

        layout.addWidget(self.script_editor)

        # 하단 버튼
        button_layout = QHBoxLayout()

        # 왼쪽: 유틸리티 버튼
        self.copy_button = QPushButton("📋 Copy to Clipboard")
        self.copy_button.clicked.connect(self.copy_to_clipboard)
        button_layout.addWidget(self.copy_button)

        self.save_button = QPushButton("💾 Save As...")
        self.save_button.clicked.connect(self.save_script)
        button_layout.addWidget(self.save_button)

        button_layout.addStretch()

        # 오른쪽: 액션 버튼
        self.close_button = QPushButton("Close")
        self.close_button.clicked.connect(self.reject)
        button_layout.addWidget(self.close_button)

        self.submit_button = QPushButton("✓ Submit Job")
        self.submit_button.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold;")
        self.submit_button.clicked.connect(self.accept)
        button_layout.addWidget(self.submit_button)

        layout.addLayout(button_layout)

        # 상태 레이블
        self.status_label = QLabel("Ready to submit")
        self.status_label.setStyleSheet("color: gray; font-size: 9pt;")
        layout.addWidget(self.status_label)

        self.setLayout(layout)

    def load_script(self):
        """스크립트 로드"""
        self.script_editor.setPlainText(self.script_content)

        # 스크립트 크기 표시
        size_bytes = len(self.script_content.encode('utf-8'))
        lines = self.script_content.count('\n') + 1
        self.size_label.setText(f"{size_bytes} bytes, {lines} lines")

        # 커서를 맨 위로
        cursor = self.script_editor.textCursor()
        cursor.movePosition(QTextCursor.Start)
        self.script_editor.setTextCursor(cursor)

        logger.debug(f"Script loaded: {size_bytes} bytes, {lines} lines")

    def on_script_modified(self):
        """스크립트 수정 이벤트"""
        if not self.is_modified:
            self.is_modified = True
            self.setWindowTitle("Slurm Script Preview *")
            self.status_label.setText("Script modified (changes will be submitted)")
            self.status_label.setStyleSheet("color: orange; font-size: 9pt;")
            logger.debug("Script modified by user")

    def copy_to_clipboard(self):
        """클립보드에 복사"""
        clipboard = QApplication.clipboard()
        current_script = self.script_editor.toPlainText()
        clipboard.setText(current_script)

        self.status_label.setText("✓ Script copied to clipboard")
        self.status_label.setStyleSheet("color: green; font-size: 9pt;")

        logger.info("Script copied to clipboard")

        # 2초 후 상태 메시지 복원
        from PyQt5.QtCore import QTimer
        QTimer.singleShot(2000, lambda: self.status_label.setText("Ready to submit"))

    def save_script(self):
        """스크립트 파일로 저장"""
        file_path, _ = QFileDialog.getSaveFileName(
            self,
            "Save Slurm Script",
            str(Path.home() / "job_script.sh"),
            "Shell Scripts (*.sh);;All Files (*.*)"
        )

        if not file_path:
            return

        try:
            current_script = self.script_editor.toPlainText()

            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(current_script)

            # 실행 권한 부여
            Path(file_path).chmod(0o755)

            self.status_label.setText(f"✓ Script saved to {Path(file_path).name}")
            self.status_label.setStyleSheet("color: green; font-size: 9pt;")

            logger.info(f"Script saved to: {file_path}")

            QMessageBox.information(
                self,
                "Save Successful",
                f"Script saved to:\n{file_path}\n\nExecution permission (755) has been set."
            )

        except Exception as e:
            logger.error(f"Failed to save script: {e}")
            QMessageBox.critical(
                self,
                "Save Failed",
                f"Failed to save script:\n{str(e)}"
            )

    def get_script_content(self) -> str:
        """
        현재 스크립트 내용 반환

        Returns:
            스크립트 내용 (수정된 내용 포함)
        """
        return self.script_editor.toPlainText()

    def is_script_modified(self) -> bool:
        """
        스크립트 수정 여부 반환

        Returns:
            수정 여부
        """
        return self.is_modified
