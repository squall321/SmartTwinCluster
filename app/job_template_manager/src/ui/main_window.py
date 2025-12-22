"""
Main Window - Job Template Manager

좌측: 템플릿 라이브러리 (QTreeWidget)
우측: 템플릿 에디터 (폼 + 파일 업로드 + 스크립트 미리보기)
"""

import logging
from PyQt5.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QSplitter, QMenuBar, QMenu, QAction, QStatusBar,
    QLabel, QMessageBox, QFileDialog, QInputDialog
)
from PyQt5.QtCore import Qt, QSettings
from PyQt5.QtGui import QIcon
from pathlib import Path

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

        new_action = QAction('📄 &New Template', self)
        new_action.setShortcut('Ctrl+N')
        new_action.setStatusTip('Create a new job template')
        new_action.triggered.connect(self.new_template)
        file_menu.addAction(new_action)

        open_action = QAction('📂 &Open Template...', self)
        open_action.setShortcut('Ctrl+O')
        open_action.setStatusTip('Open an existing template')
        open_action.triggered.connect(self.open_template)
        file_menu.addAction(open_action)

        save_action = QAction('💾 &Save Template', self)
        save_action.setShortcut('Ctrl+S')
        save_action.setStatusTip('Save current template')
        save_action.triggered.connect(self.save_template)
        file_menu.addAction(save_action)

        file_menu.addSeparator()

        import_action = QAction('📥 &Import Template...', self)
        import_action.setStatusTip('Import template from YAML file')
        import_action.triggered.connect(self.import_template)
        file_menu.addAction(import_action)

        export_action = QAction('📤 &Export Template...', self)
        export_action.setStatusTip('Export current template to YAML file')
        export_action.triggered.connect(self.export_template)
        file_menu.addAction(export_action)

        file_menu.addSeparator()

        exit_action = QAction('🚪 E&xit', self)
        exit_action.setShortcut('Ctrl+Q')
        exit_action.setStatusTip('Exit application')
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

        # Edit 메뉴
        edit_menu = menubar.addMenu('&Edit')

        edit_template_action = QAction('✏️ &Edit Template', self)
        edit_template_action.setShortcut('Ctrl+E')
        edit_template_action.setStatusTip('Edit selected template')
        edit_template_action.triggered.connect(self.edit_template)
        edit_menu.addAction(edit_template_action)

        duplicate_action = QAction('📋 &Duplicate Template', self)
        duplicate_action.setShortcut('Ctrl+D')
        duplicate_action.setStatusTip('Duplicate selected template')
        duplicate_action.triggered.connect(self.duplicate_template)
        edit_menu.addAction(duplicate_action)

        edit_menu.addSeparator()

        delete_action = QAction('🗑️ &Delete Template', self)
        delete_action.setShortcut('Delete')
        delete_action.setStatusTip('Delete selected template')
        delete_action.triggered.connect(self.delete_template)
        edit_menu.addAction(delete_action)

        # View 메뉴
        view_menu = menubar.addMenu('&View')

        refresh_action = QAction('🔄 &Refresh Templates', self)
        refresh_action.setShortcut('F5')
        refresh_action.setStatusTip('Reload template library')
        refresh_action.triggered.connect(self.refresh_templates)
        view_menu.addAction(refresh_action)

        view_menu.addSeparator()

        # 테마 서브메뉴
        theme_menu = view_menu.addMenu('🎨 &Theme')

        dark_theme_action = QAction('🌙 Dark Mode', self)
        dark_theme_action.setCheckable(True)
        dark_theme_action.triggered.connect(lambda: self.change_theme('dark'))
        theme_menu.addAction(dark_theme_action)

        light_theme_action = QAction('☀️ Light Mode', self)
        light_theme_action.setCheckable(True)
        light_theme_action.triggered.connect(lambda: self.change_theme('light'))
        theme_menu.addAction(light_theme_action)

        # 현재 테마 체크
        current_theme = self.settings.value("appearance/theme", "dark")
        if current_theme == "dark":
            dark_theme_action.setChecked(True)
        else:
            light_theme_action.setChecked(True)

        # 테마 액션 그룹 (한 번에 하나만 선택)
        from PyQt5.QtWidgets import QActionGroup
        theme_group = QActionGroup(self)
        theme_group.addAction(dark_theme_action)
        theme_group.addAction(light_theme_action)

        # Help 메뉴
        help_menu = menubar.addMenu('&Help')

        about_action = QAction('ℹ️ &About', self)
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

        try:
            from ui.template_creator_dialog import TemplateCreatorDialog

            # 템플릿 생성 다이얼로그 표시
            dialog = TemplateCreatorDialog(self)

            if dialog.exec_() == QMessageBox.Accepted:
                template = dialog.get_template()

                if template:
                    # 템플릿 저장
                    from utils.template_manager import TemplateManager
                    manager = TemplateManager()

                    success, error, file_path = manager.save_template(template, overwrite=False)

                    if success:
                        QMessageBox.information(
                            self,
                            "Template Created",
                            f"Template '{template.template.name}' has been created successfully!\n\n"
                            f"File: {file_path.name}"
                        )
                        # 템플릿 라이브러리 새로고침
                        self.refresh_templates()
                        logger.info(f"Template created: {template.template.id}")
                    else:
                        QMessageBox.critical(
                            self,
                            "Create Failed",
                            f"Failed to create template:\n{error}"
                        )

        except Exception as e:
            logger.error(f"Failed to create new template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to create template:\n{str(e)}"
            )

    def open_template(self):
        """템플릿 열기 (YAML 파일에서)"""
        logger.info("Open template action triggered")

        try:
            # 파일 선택 다이얼로그
            file_path, _ = QFileDialog.getOpenFileName(
                self,
                "Open Template",
                str(Path.home()),
                "YAML Files (*.yaml *.yml);;All Files (*.*)"
            )

            if not file_path:
                return

            # 템플릿 로드
            from utils.yaml_loader import YAMLLoader
            loader = YAMLLoader()
            template = loader.load_template_from_file(Path(file_path))

            if template:
                # 에디터에 로드
                if self.template_editor:
                    self.template_editor.load_template(template)
                    self.statusBar().showMessage(f"Template loaded from {Path(file_path).name}")
                    logger.info(f"Template opened: {file_path}")
            else:
                QMessageBox.warning(
                    self,
                    "Load Failed",
                    f"Failed to load template from:\n{file_path}"
                )

        except Exception as e:
            logger.error(f"Failed to open template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to open template:\n{str(e)}"
            )

    def save_template(self):
        """현재 편집 중인 템플릿 저장"""
        logger.info("Save template action triggered")

        # 현재 편집 중인 템플릿 가져오기
        if not self.template_editor:
            QMessageBox.warning(self, "Save Template", "No template editor available")
            return

        current_template = self.template_editor.current_template

        if not current_template:
            QMessageBox.warning(self, "Save Template", "No template is currently loaded")
            return

        try:
            from utils.template_manager import TemplateManager
            manager = TemplateManager()

            # 확인 다이얼로그
            reply = QMessageBox.question(
                self,
                "Save Template",
                f"Save changes to '{current_template.template.name}'?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.Yes
            )

            if reply == QMessageBox.Yes:
                # 템플릿 업데이트
                success, error = manager.update_template(current_template)

                if success:
                    QMessageBox.information(
                        self,
                        "Saved",
                        f"Template '{current_template.template.name}' has been saved."
                    )
                    # 템플릿 라이브러리 새로고침
                    self.refresh_templates()
                    logger.info(f"Template saved: {current_template.template.id}")
                else:
                    QMessageBox.critical(
                        self,
                        "Save Failed",
                        f"Failed to save template:\n{error}"
                    )

        except Exception as e:
            logger.error(f"Failed to save template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to save template:\n{str(e)}"
            )

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

    def edit_template(self):
        """선택된 템플릿 편집"""
        logger.info("Edit template action triggered")

        # 현재 선택된 템플릿 가져오기
        if not self.template_editor or not self.template_editor.current_template:
            QMessageBox.warning(
                self,
                "❌ No Template Selected",
                "Please select a template from the library on the left side before editing."
            )
            return

        try:
            from ui.template_creator_dialog import TemplateCreatorDialog

            current_template = self.template_editor.current_template

            # 편집 다이얼로그 표시
            dialog = TemplateCreatorDialog(self, template=current_template)

            if dialog.exec_() == QMessageBox.Accepted:
                updated_template = dialog.get_template()

                if updated_template:
                    # 템플릿 저장
                    from utils.template_manager import TemplateManager
                    manager = TemplateManager()

                    success, error = manager.update_template(updated_template)

                    if success:
                        QMessageBox.information(
                            self,
                            "Template Updated",
                            f"Template '{updated_template.template.name}' has been updated successfully!"
                        )
                        # 새로고침
                        self.refresh_templates()
                        # 에디터에 업데이트된 템플릿 로드
                        self.template_editor.load_template(updated_template)
                        logger.info(f"Template updated: {updated_template.template.id}")
                    else:
                        QMessageBox.critical(
                            self,
                            "Update Failed",
                            f"Failed to update template:\n{error}"
                        )

        except Exception as e:
            logger.error(f"Failed to edit template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to edit template:\n{str(e)}"
            )

    def duplicate_template(self):
        """선택된 템플릿 복제"""
        logger.info("Duplicate template action triggered")

        # 현재 선택된 템플릿 가져오기
        if not self.template_editor or not self.template_editor.current_template:
            QMessageBox.warning(
                self,
                "❌ No Template Selected",
                "Please select a template from the library before duplicating."
            )
            return

        try:
            current_template = self.template_editor.current_template

            # 새 템플릿 ID 입력
            new_id, ok = QInputDialog.getText(
                self,
                "Duplicate Template",
                f"Enter new template ID for duplicate of '{current_template.template.name}':",
                text=f"{current_template.template.id}-copy"
            )

            if not ok or not new_id.strip():
                return

            new_id = new_id.strip()

            # 템플릿 복제
            from utils.template_manager import TemplateManager
            manager = TemplateManager()

            success, error, duplicated_template = manager.duplicate_template(
                current_template.template.id,
                new_id,
                new_name=f"Copy of {current_template.template.name}"
            )

            if success:
                QMessageBox.information(
                    self,
                    "Template Duplicated",
                    f"Template duplicated successfully!\n\n"
                    f"New template ID: {new_id}"
                )
                # 새로고침
                self.refresh_templates()
                # 복제된 템플릿 로드
                if duplicated_template:
                    self.template_editor.load_template(duplicated_template)
                logger.info(f"Template duplicated: {current_template.template.id} -> {new_id}")
            else:
                QMessageBox.critical(
                    self,
                    "Duplicate Failed",
                    f"Failed to duplicate template:\n{error}"
                )

        except Exception as e:
            logger.error(f"Failed to duplicate template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to duplicate template:\n{str(e)}"
            )

    def delete_template(self):
        """선택된 템플릿 삭제"""
        logger.info("Delete template action triggered")

        # 현재 선택된 템플릿 가져오기
        if not self.template_editor or not self.template_editor.current_template:
            QMessageBox.warning(
                self,
                "❌ No Template Selected",
                "Please select a template from the library before deleting."
            )
            return

        try:
            current_template = self.template_editor.current_template

            # 확인 다이얼로그
            reply = QMessageBox.question(
                self,
                "Delete Template",
                f"Are you sure you want to delete template '{current_template.template.name}'?\n\n"
                f"The template will be moved to the archived folder.",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No
            )

            if reply == QMessageBox.Yes:
                # 템플릿 삭제
                from utils.template_manager import TemplateManager
                manager = TemplateManager()

                success, error = manager.delete_template(current_template.template.id, permanent=False)

                if success:
                    QMessageBox.information(
                        self,
                        "Template Deleted",
                        f"Template '{current_template.template.name}' has been archived."
                    )
                    # 새로고침
                    self.refresh_templates()
                    # 에디터 클리어
                    self.template_editor.clear()
                    logger.info(f"Template deleted: {current_template.template.id}")
                else:
                    QMessageBox.critical(
                        self,
                        "Delete Failed",
                        f"Failed to delete template:\n{error}"
                    )

        except Exception as e:
            logger.error(f"Failed to delete template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to delete template:\n{str(e)}"
            )

    def import_template(self):
        """템플릿 가져오기"""
        logger.info("Import template action triggered")

        try:
            # 파일 선택 다이얼로그
            file_path, _ = QFileDialog.getOpenFileName(
                self,
                "Import Template",
                str(Path.home()),
                "YAML Files (*.yaml *.yml);;All Files (*.*)"
            )

            if not file_path:
                return

            # 템플릿 가져오기
            from utils.template_manager import TemplateManager
            manager = TemplateManager()

            success, error, template = manager.import_template(Path(file_path), overwrite=False)

            if success:
                QMessageBox.information(
                    self,
                    "Template Imported",
                    f"Template '{template.template.name}' has been imported successfully!"
                )
                # 새로고침
                self.refresh_templates()
                # 가져온 템플릿 로드
                if template:
                    self.template_editor.load_template(template)
                logger.info(f"Template imported: {file_path}")
            else:
                QMessageBox.critical(
                    self,
                    "Import Failed",
                    f"Failed to import template:\n{error}"
                )

        except Exception as e:
            logger.error(f"Failed to import template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to import template:\n{str(e)}"
            )

    def export_template(self):
        """현재 템플릿 내보내기"""
        logger.info("Export template action triggered")

        # 현재 선택된 템플릿 가져오기
        if not self.template_editor or not self.template_editor.current_template:
            QMessageBox.warning(self, "Export Template", "No template selected")
            return

        try:
            current_template = self.template_editor.current_template

            # 저장 위치 선택
            default_filename = f"{current_template.template.id}.yaml"
            file_path, _ = QFileDialog.getSaveFileName(
                self,
                "Export Template",
                str(Path.home() / default_filename),
                "YAML Files (*.yaml *.yml);;All Files (*.*)"
            )

            if not file_path:
                return

            # 템플릿 내보내기
            from utils.template_manager import TemplateManager
            manager = TemplateManager()

            success, error = manager.export_template(current_template.template.id, Path(file_path))

            if success:
                QMessageBox.information(
                    self,
                    "Template Exported",
                    f"Template exported successfully to:\n{file_path}"
                )
                logger.info(f"Template exported: {current_template.template.id} -> {file_path}")
            else:
                QMessageBox.critical(
                    self,
                    "Export Failed",
                    f"Failed to export template:\n{error}"
                )

        except Exception as e:
            logger.error(f"Failed to export template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Error",
                f"Failed to export template:\n{str(e)}"
            )

    def refresh_templates(self):
        """템플릿 라이브러리 새로고침"""
        logger.info("Refresh templates action triggered")

        try:
            if self.template_library:
                self.template_library.load_templates()
                self.statusBar().showMessage("Templates refreshed")
                logger.info("Templates refreshed")

        except Exception as e:
            logger.error(f"Failed to refresh templates: {e}", exc_info=True)
            QMessageBox.warning(
                self,
                "Refresh Failed",
                f"Failed to refresh templates:\n{str(e)}"
            )

    def change_theme(self, theme: str):
        """
        테마 변경

        Args:
            theme: 'dark' 또는 'light'
        """
        logger.info(f"Changing theme to: {theme}")

        # 설정 저장
        self.settings.setValue("appearance/theme", theme)

        # 스타일시트 로드
        stylesheet_path = Path(__file__).parent.parent / 'resources' / 'styles' / f'{theme}_theme.qss'

        try:
            with open(stylesheet_path, 'r', encoding='utf-8') as f:
                stylesheet = f.read()

            # 앱에 스타일시트 적용
            from PyQt5.QtWidgets import QApplication
            QApplication.instance().setStyleSheet(stylesheet)

            self.statusBar().showMessage(f"Theme changed to {theme} mode", 2000)
            logger.info(f"Theme changed to {theme}")

        except FileNotFoundError:
            logger.error(f"Theme file not found: {stylesheet_path}")
            QMessageBox.warning(
                self,
                "Theme Error",
                f"Theme file not found:\n{stylesheet_path}"
            )
        except Exception as e:
            logger.error(f"Failed to change theme: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Theme Error",
                f"Failed to change theme:\n{str(e)}"
            )

    def closeEvent(self, event):
        """윈도우 종료 이벤트"""
        # 윈도우 크기/위치 저장
        self.settings.setValue("mainwindow/geometry", self.saveGeometry())

        logger.info("Application closing")
        event.accept()
