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

        # 우측: 템플릿 에디터
        try:
            from ui.template_editor import TemplateEditorWidget
            self.template_editor = TemplateEditorWidget()
            self.template_editor.preview_requested.connect(self.on_preview_requested)
            self.template_editor.submit_requested.connect(self.on_submit_requested)
            right_widget = self.template_editor
        except ImportError as e:
            logger.warning(f"Failed to import TemplateEditorWidget: {e}")
            right_widget = QWidget()
            right_layout = QVBoxLayout()
            right_label = QLabel("템플릿 에디터\n(TemplateEditorWidget 로드 실패)")
            right_label.setAlignment(Qt.AlignCenter)
            right_layout.addWidget(right_label)
            right_widget.setLayout(right_layout)
            self.template_editor = None

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

        # Template 객체가 있으면 에디터에 로드
        if self.template_editor and '_template_obj' in template_data:
            template_obj = template_data['_template_obj']
            self.template_editor.load_template(template_obj)
            self.statusBar().showMessage(f"Template loaded: {template_data['name']}")

    def on_template_double_clicked(self, template_data: dict):
        """템플릿 더블클릭 이벤트 (로드 및 편집 모드)"""
        logger.info(f"Template double-clicked: {template_data['name']}")

        # 단일 클릭과 동일하게 처리 (현재는 편집 모드 구분 없음)
        self.on_template_selected(template_data)

    def on_preview_requested(self):
        """스크립트 미리보기 요청"""
        logger.info("Script preview requested")

        if not self.template_editor:
            QMessageBox.warning(self, "Preview", "No template editor available")
            return

        # 현재 템플릿 및 설정 가져오기
        current_template = self.template_editor.current_template
        if not current_template:
            QMessageBox.warning(self, "Preview", "No template selected")
            return

        slurm_config = self.template_editor.get_current_slurm_config()
        uploaded_files = self.template_editor.get_uploaded_files()

        # 필수 파일 체크
        if current_template.files:
            if not self.template_editor.file_upload.check_required_files():
                QMessageBox.warning(
                    self,
                    "Missing Files",
                    "Please upload all required files before preview."
                )
                return

        # 스크립트 생성
        try:
            from utils.script_generator import ScriptGenerator

            generator = ScriptGenerator()
            script = generator.generate(
                template_obj=current_template,
                slurm_config=slurm_config,
                uploaded_files=uploaded_files or {},
                job_name=None,  # 사용자가 다이얼로그에서 지정 가능하도록
                apptainer_image_path=None  # Template 기본값 사용
            )

            # 미리보기 다이얼로그 표시
            from ui.script_preview_dialog import ScriptPreviewDialog

            dialog = ScriptPreviewDialog(script, self)
            result = dialog.exec_()

            if result == QMessageBox.Accepted:
                # 사용자가 Submit 버튼을 누른 경우
                self.submit_job(dialog.get_script_content())

        except Exception as e:
            logger.error(f"Failed to generate script: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Script Generation Failed",
                f"Failed to generate script:\n{str(e)}"
            )

    def on_submit_requested(self):
        """Job 제출 요청 (Preview 없이 바로 제출)"""
        logger.info("Job submit requested")

        # Preview를 먼저 보여주도록 유도
        reply = QMessageBox.question(
            self,
            "Submit Job",
            "Do you want to preview the script before submission?",
            QMessageBox.Yes | QMessageBox.No | QMessageBox.Cancel,
            QMessageBox.Yes
        )

        if reply == QMessageBox.Yes:
            self.on_preview_requested()
        elif reply == QMessageBox.No:
            # Preview 없이 바로 제출
            self.direct_submit()

    def direct_submit(self):
        """Preview 없이 바로 제출"""
        if not self.template_editor:
            return

        current_template = self.template_editor.current_template
        if not current_template:
            QMessageBox.warning(self, "Submit", "No template selected")
            return

        slurm_config = self.template_editor.get_current_slurm_config()
        uploaded_files = self.template_editor.get_uploaded_files()

        # 필수 파일 체크
        if current_template.files:
            if not self.template_editor.file_upload.check_required_files():
                QMessageBox.warning(
                    self,
                    "Missing Files",
                    "Please upload all required files before submission."
                )
                return

        # 스크립트 생성
        try:
            from utils.script_generator import ScriptGenerator

            generator = ScriptGenerator()
            script = generator.generate(
                template_obj=current_template,
                slurm_config=slurm_config,
                uploaded_files=uploaded_files or {},
                job_name=current_template.template.name,
                apptainer_image_path=None
            )

            self.submit_job(script)

        except Exception as e:
            logger.error(f"Failed to generate script: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Script Generation Failed",
                f"Failed to generate script:\n{str(e)}"
            )

    def submit_job(self, script_content: str):
        """
        Job 제출 실행

        Args:
            script_content: 스크립트 내용
        """
        logger.info("Submitting job to Slurm")

        try:
            from utils.job_submitter import JobSubmitter

            submitter = JobSubmitter()

            # Slurm 사용 가능 여부 확인
            available, error_msg = submitter.check_slurm_available()
            if not available:
                QMessageBox.warning(
                    self,
                    "Slurm Not Available",
                    f"Slurm is not available:\n{error_msg}\n\n"
                    "The script has been generated but cannot be submitted."
                )
                return

            # Job 제출
            success, job_id, error = submitter.submit_job(script_content, dry_run=False)

            if success and job_id:
                # 성공
                QMessageBox.information(
                    self,
                    "Job Submitted",
                    f"Job submitted successfully!\n\n"
                    f"Job ID: {job_id}\n\n"
                    f"You can monitor the job with:\n"
                    f"  squeue -j {job_id}\n"
                    f"  scontrol show job {job_id}"
                )

                self.statusBar().showMessage(f"Job {job_id} submitted successfully", 5000)
                logger.info(f"Job submitted: {job_id}")

            elif success and not job_id:
                # 제출 성공했지만 Job ID 추출 실패
                QMessageBox.warning(
                    self,
                    "Job Submitted",
                    "Job submitted successfully, but Job ID could not be extracted.\n"
                    "Check 'squeue' to see your job."
                )

            else:
                # 실패
                QMessageBox.critical(
                    self,
                    "Submission Failed",
                    f"Job submission failed:\n{error}"
                )
                logger.error(f"Job submission failed: {error}")

        except Exception as e:
            logger.error(f"Job submission error: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Submission Error",
                f"An error occurred during submission:\n{str(e)}"
            )

    def closeEvent(self, event):
        """윈도우 종료 이벤트"""
        # 윈도우 크기/위치 저장
        self.settings.setValue("mainwindow/geometry", self.saveGeometry())

        logger.info("Application closing")
        event.accept()
