"""
Main Window - Job Template Manager

좌측: 템플릿 라이브러리 (QTreeWidget)
우측: 템플릿 에디터 (폼 + 파일 업로드 + 스크립트 미리보기)
"""

import logging
from PyQt5.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QSplitter, QMenuBar, QMenu, QAction, QStatusBar,
    QLabel, QMessageBox
)
from PyQt5.QtCore import Qt, QSettings
from PyQt5.QtGui import QIcon

logger = logging.getLogger(__name__)


class MainWindow(QMainWindow):
    """메인 윈도우 클래스"""

    def __init__(self):
        super().__init__()

        self.settings = QSettings()

        self.init_ui()
        self.restore_geometry()

        logger.info("MainWindow initialized")

    def init_ui(self):
        """UI 초기화"""
        self.setWindowTitle("Job Template Manager")
        self.setGeometry(100, 100, 1200, 800)

        # 메뉴바 생성
        self.create_menu_bar()

        # 중앙 위젯 (QSplitter)
        self.create_central_widget()

        # 상태바 생성
        self.create_status_bar()

    def create_menu_bar(self):
        """메뉴바 생성"""
        menubar = self.menuBar()

        # File 메뉴
        file_menu = menubar.addMenu('&File')

        new_action = QAction('&New Template', self)
        new_action.setShortcut('Ctrl+N')
        new_action.setStatusTip('Create a new job template')
        new_action.triggered.connect(self.new_template)
        file_menu.addAction(new_action)

        open_action = QAction('&Open Template...', self)
        open_action.setShortcut('Ctrl+O')
        open_action.setStatusTip('Open an existing template')
        open_action.triggered.connect(self.open_template)
        file_menu.addAction(open_action)

        save_action = QAction('&Save Template', self)
        save_action.setShortcut('Ctrl+S')
        save_action.setStatusTip('Save current template')
        save_action.triggered.connect(self.save_template)
        file_menu.addAction(save_action)

        file_menu.addSeparator()

        exit_action = QAction('E&xit', self)
        exit_action.setShortcut('Ctrl+Q')
        exit_action.setStatusTip('Exit application')
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

        # Edit 메뉴
        edit_menu = menubar.addMenu('&Edit')

        # View 메뉴
        view_menu = menubar.addMenu('&View')

        # Help 메뉴
        help_menu = menubar.addMenu('&Help')

        about_action = QAction('&About', self)
        about_action.setStatusTip('About Job Template Manager')
        about_action.triggered.connect(self.show_about)
        help_menu.addAction(about_action)

    def create_central_widget(self):
        """중앙 위젯 생성 (QSplitter)"""
        # QSplitter: 좌측 템플릿 라이브러리 + 우측 에디터
        splitter = QSplitter(Qt.Horizontal)

        # 좌측: 템플릿 라이브러리
        try:
            from ui.template_library import TemplateLibraryWidget
            self.template_library = TemplateLibraryWidget()
            self.template_library.template_selected.connect(self.on_template_selected)
            self.template_library.template_double_clicked.connect(self.on_template_double_clicked)
            left_widget = self.template_library
        except ImportError as e:
            logger.warning(f"Failed to import TemplateLibraryWidget: {e}")
            left_widget = QWidget()
            left_layout = QVBoxLayout()
            left_label = QLabel("템플릿 라이브러리\n(TemplateLibraryWidget 로드 실패)")
            left_label.setAlignment(Qt.AlignCenter)
            left_layout.addWidget(left_label)
            left_widget.setLayout(left_layout)

        # 우측: 템플릿 에디터 (나중에 TemplateEditorWidget으로 교체)
        right_widget = QWidget()
        right_layout = QVBoxLayout()
        right_label = QLabel("템플릿 에디터\n(TemplateEditorWidget 구현 예정)")
        right_label.setAlignment(Qt.AlignCenter)
        right_layout.addWidget(right_label)
        right_widget.setLayout(right_layout)

        # Splitter에 위젯 추가
        splitter.addWidget(left_widget)
        splitter.addWidget(right_widget)

        # 초기 비율 설정 (좌측 30%, 우측 70%)
        splitter.setSizes([300, 700])

        # 중앙 위젯 설정
        self.setCentralWidget(splitter)

    def create_status_bar(self):
        """상태바 생성"""
        status_bar = self.statusBar()

        # 연결 상태 표시
        self.connection_label = QLabel("● Offline")
        self.connection_label.setStyleSheet("color: orange;")
        status_bar.addPermanentWidget(self.connection_label)

        status_bar.showMessage("Ready")

    def new_template(self):
        """새 템플릿 생성"""
        logger.info("New template action triggered")
        QMessageBox.information(self, "New Template", "새 템플릿 생성 기능은 구현 예정입니다.")

    def open_template(self):
        """템플릿 열기"""
        logger.info("Open template action triggered")
        QMessageBox.information(self, "Open Template", "템플릿 열기 기능은 구현 예정입니다.")

    def save_template(self):
        """템플릿 저장"""
        logger.info("Save template action triggered")
        QMessageBox.information(self, "Save Template", "템플릿 저장 기능은 구현 예정입니다.")

    def show_about(self):
        """About 다이얼로그"""
        QMessageBox.about(
            self,
            "About Job Template Manager",
            "<h3>Job Template Manager</h3>"
            "<p>HPC Slurm Job Template 생성 및 관리 도구</p>"
            "<p>Version: 1.0.0</p>"
            "<p>Built with PyQt5</p>"
        )

    def restore_geometry(self):
        """윈도우 크기/위치 복원"""
        geometry = self.settings.value("mainwindow/geometry")
        if geometry:
            self.restoreGeometry(geometry)

    def on_template_selected(self, template_data: dict):
        """템플릿 선택 이벤트 (단일 클릭)"""
        logger.info(f"Template selected: {template_data['name']}")
        # TODO: 우측 에디터에 템플릿 정보 표시

    def on_template_double_clicked(self, template_data: dict):
        """템플릿 더블클릭 이벤트 (로드)"""
        logger.info(f"Template double-clicked: {template_data['name']}")
        # TODO: 우측 에디터에 템플릿 로드 및 편집 모드

    def closeEvent(self, event):
        """윈도우 종료 이벤트"""
        # 윈도우 크기/위치 저장
        self.settings.setValue("mainwindow/geometry", self.saveGeometry())

        logger.info("Application closing")
        event.accept()
