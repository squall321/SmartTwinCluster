#!/usr/bin/env python3
"""
Job Template Manager - Main Entry Point

HPC Slurm Job Template 생성 및 관리를 위한 PyQt5 데스크톱 애플리케이션
"""

import sys
import logging
from pathlib import Path

from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import Qt

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('job_template_manager.log')
    ]
)

logger = logging.getLogger(__name__)


def main():
    """애플리케이션 메인 함수"""
    logger.info("Job Template Manager starting...")

    # QApplication 생성
    app = QApplication(sys.argv)
    app.setApplicationName("Job Template Manager")
    app.setOrganizationName("HPC Cluster")
    app.setOrganizationDomain("hpc.local")

    # High DPI 지원
    app.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    app.setAttribute(Qt.AA_UseHighDpiPixmaps, True)

    # MainWindow import (나중에 구현)
    try:
        from ui.main_window import MainWindow

        # 메인 윈도우 생성 및 표시
        window = MainWindow()
        window.show()

        logger.info("Application window shown")

    except ImportError as e:
        logger.error(f"Failed to import MainWindow: {e}")
        logger.info("Creating minimal test window...")

        # 임시 테스트 윈도우
        from PyQt5.QtWidgets import QMainWindow, QLabel
        window = QMainWindow()
        window.setWindowTitle("Job Template Manager (Dev)")
        window.setGeometry(100, 100, 800, 600)

        label = QLabel("Job Template Manager\n\nMainWindow 구현 대기 중...")
        label.setAlignment(Qt.AlignCenter)
        window.setCentralWidget(label)
        window.show()

    # 이벤트 루프 실행
    sys.exit(app.exec_())


if __name__ == '__main__':
    main()
