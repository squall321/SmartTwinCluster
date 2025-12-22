"""
Template Editor Widget - 템플릿 에디터

우측 패널: 템플릿 상세 정보 표시 및 편집
"""

import logging
from typing import Optional
import re

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout, QGroupBox,
    QLineEdit, QTextEdit, QComboBox, QSpinBox, QCheckBox,
    QPushButton, QLabel, QScrollArea, QTableWidget, QTableWidgetItem,
    QHeaderView
)
from PyQt5.QtCore import Qt, pyqtSignal, QRegExp
from PyQt5.QtGui import QFont, QRegExpValidator

logger = logging.getLogger(__name__)


class TemplateEditorWidget(QWidget):
    """템플릿 에디터 위젯"""

    # 시그널 정의
    template_modified = pyqtSignal()  # 템플릿 수정 시 발생
    preview_requested = pyqtSignal()  # 스크립트 미리보기 요청
    submit_requested = pyqtSignal()   # Job 제출 요청

    def __init__(self, parent=None):
        super().__init__(parent)

        self.current_template = None  # 현재 로드된 Template 객체
        self.is_modified = False

        self.init_ui()

        logger.info("TemplateEditorWidget initialized")

    def init_ui(self):
        """UI 초기화"""
        # 메인 레이아웃 (스크롤 가능)
        main_layout = QVBoxLayout()
        main_layout.setContentsMargins(5, 5, 5, 5)

        # 스크롤 영역
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)

        # 스크롤 내용 위젯
        content_widget = QWidget()
        content_layout = QVBoxLayout()
        content_layout.setSpacing(10)

        # 1. Template Info Section
        self.info_group = self.create_info_section()
        content_layout.addWidget(self.info_group)

        # 2. Slurm Config Section
        self.slurm_group = self.create_slurm_section()
        content_layout.addWidget(self.slurm_group)

        # 3. Apptainer Config Section
        self.apptainer_group = self.create_apptainer_section()
        content_layout.addWidget(self.apptainer_group)

        # 4. File Schema Section
        self.files_group = self.create_files_section()
        content_layout.addWidget(self.files_group)

        # 5. File Upload Section
        self.upload_group = self.create_upload_section()
        content_layout.addWidget(self.upload_group)

        # 6. Script Preview Section
        self.script_group = self.create_script_section()
        content_layout.addWidget(self.script_group)

        content_layout.addStretch()
        content_widget.setLayout(content_layout)
        scroll.setWidget(content_widget)

        main_layout.addWidget(scroll)

        # 하단 액션 버튼
        button_layout = QHBoxLayout()
        button_layout.addStretch()

        self.preview_button = QPushButton("Preview Script")
        self.preview_button.setToolTip("Preview the generated Slurm batch script\n"
                                       "Review and edit before submitting")
        self.preview_button.clicked.connect(self.on_preview_clicked)
        button_layout.addWidget(self.preview_button)

        self.submit_button = QPushButton("Submit Job")
        self.submit_button.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold;")
        self.submit_button.setToolTip("Submit job to Slurm scheduler\n"
                                      "Requires all required files to be uploaded")
        self.submit_button.clicked.connect(self.on_submit_clicked)
        button_layout.addWidget(self.submit_button)

        main_layout.addLayout(button_layout)

        self.setLayout(main_layout)

        # 초기 상태: 템플릿 없음
        self.show_empty_state()

    def create_info_section(self) -> QGroupBox:
        """템플릿 정보 섹션"""
        group = QGroupBox("Template Information")
        group.setStyleSheet("QGroupBox { font-weight: bold; }")

        layout = QFormLayout()

        # Name
        self.name_edit = QLineEdit()
        self.name_edit.setReadOnly(True)
        layout.addRow("Name:", self.name_edit)

        # Description
        self.description_edit = QTextEdit()
        self.description_edit.setReadOnly(True)
        self.description_edit.setMaximumHeight(60)
        layout.addRow("Description:", self.description_edit)

        # Category
        self.category_label = QLabel()
        layout.addRow("Category:", self.category_label)

        # Version
        self.version_label = QLabel()
        layout.addRow("Version:", self.version_label)

        # Source
        self.source_label = QLabel()
        layout.addRow("Source:", self.source_label)

        # Tags
        self.tags_label = QLabel()
        self.tags_label.setWordWrap(True)
        layout.addRow("Tags:", self.tags_label)

        group.setLayout(layout)
        return group

    def create_slurm_section(self) -> QGroupBox:
        """Slurm 설정 섹션"""
        group = QGroupBox("Slurm Configuration")
        group.setStyleSheet("QGroupBox { font-weight: bold; }")

        layout = QFormLayout()

        # Partition
        self.partition_combo = QComboBox()
        self.partition_combo.addItems(['compute', 'viz', 'gpu', 'highmem'])
        self.partition_combo.setToolTip("Select the Slurm partition for job execution\n"
                                       "compute: General compute nodes\n"
                                       "viz: Visualization nodes\n"
                                       "gpu: GPU nodes\n"
                                       "highmem: High memory nodes")
        self.partition_combo.currentTextChanged.connect(self.on_config_changed)
        layout.addRow("Partition:", self.partition_combo)

        # Nodes
        self.nodes_spin = QSpinBox()
        self.nodes_spin.setMinimum(1)
        self.nodes_spin.setMaximum(100)
        self.nodes_spin.setToolTip("Number of compute nodes to allocate for this job")
        self.nodes_spin.valueChanged.connect(self.on_config_changed)
        layout.addRow("Nodes:", self.nodes_spin)

        # Tasks (CPUs)
        self.ntasks_spin = QSpinBox()
        self.ntasks_spin.setMinimum(1)
        self.ntasks_spin.setMaximum(256)
        self.ntasks_spin.setToolTip("Number of tasks (CPU cores) to allocate\n"
                                    "Typically equals the number of parallel processes")
        self.ntasks_spin.valueChanged.connect(self.on_config_changed)
        layout.addRow("Tasks (ntasks):", self.ntasks_spin)

        # Memory
        self.memory_edit = QLineEdit()
        self.memory_edit.setPlaceholderText("e.g., 32G, 64GB, 128G")
        self.memory_edit.setToolTip("Memory allocation per node\n"
                                   "Examples: 32G, 64GB, 128G, 256GB")
        # Memory validation: number + G/GB/M/MB
        memory_validator = QRegExpValidator(QRegExp(r'^\d+[GMgm][Bb]?$'))
        self.memory_edit.setValidator(memory_validator)
        self.memory_edit.textChanged.connect(self.on_memory_changed)
        layout.addRow("Memory:", self.memory_edit)

        # Time Limit
        self.time_edit = QLineEdit()
        self.time_edit.setPlaceholderText("HH:MM:SS (e.g., 02:00:00)")
        self.time_edit.setToolTip("Maximum job runtime in HH:MM:SS format\n"
                                 "Job will be terminated after this time\n"
                                 "Examples: 01:00:00 (1 hour), 12:30:00 (12.5 hours)")
        # Time validation: HH:MM:SS format
        time_validator = QRegExpValidator(QRegExp(r'^\d{1,2}:\d{2}:\d{2}$'))
        self.time_edit.setValidator(time_validator)
        self.time_edit.textChanged.connect(self.on_time_changed)
        layout.addRow("Time Limit:", self.time_edit)

        # GPUs (Optional)
        self.gpu_spin = QSpinBox()
        self.gpu_spin.setMinimum(0)
        self.gpu_spin.setMaximum(8)
        self.gpu_spin.setToolTip("Number of GPUs to allocate (0 for CPU-only jobs)\n"
                                "Requires 'gpu' partition")
        self.gpu_spin.valueChanged.connect(self.on_config_changed)
        layout.addRow("GPUs (optional):", self.gpu_spin)

        group.setLayout(layout)
        return group

    def create_apptainer_section(self) -> QGroupBox:
        """Apptainer 설정 섹션"""
        group = QGroupBox("Apptainer Configuration")
        group.setStyleSheet("QGroupBox { font-weight: bold; }")

        layout = QFormLayout()

        # Image Name
        self.image_label = QLabel()
        self.image_label.setWordWrap(True)
        layout.addRow("Image:", self.image_label)

        # Mode
        self.mode_label = QLabel()
        layout.addRow("Mode:", self.mode_label)

        # Bind Paths
        self.bind_text = QTextEdit()
        self.bind_text.setReadOnly(True)
        self.bind_text.setMaximumHeight(60)
        layout.addRow("Bind Paths:", self.bind_text)

        # Environment Variables
        self.env_text = QTextEdit()
        self.env_text.setReadOnly(True)
        self.env_text.setMaximumHeight(60)
        layout.addRow("Environment:", self.env_text)

        group.setLayout(layout)
        return group

    def create_files_section(self) -> QGroupBox:
        """파일 스키마 섹션"""
        group = QGroupBox("File Schema")
        group.setStyleSheet("QGroupBox { font-weight: bold; }")

        layout = QVBoxLayout()

        # 파일 테이블
        self.files_table = QTableWidget()
        self.files_table.setColumnCount(4)
        self.files_table.setHorizontalHeaderLabels(['Required', 'File Key', 'Name', 'Extensions'])
        self.files_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)
        self.files_table.horizontalHeader().setStretchLastSection(True)
        self.files_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.files_table.setMaximumHeight(200)

        layout.addWidget(self.files_table)

        group.setLayout(layout)
        return group

    def create_upload_section(self) -> QGroupBox:
        """파일 업로드 섹션"""
        group = QGroupBox("File Upload")
        group.setStyleSheet("QGroupBox { font-weight: bold; }")

        layout = QVBoxLayout()

        # FileUploadWidget
        from ui.file_upload import FileUploadWidget
        self.file_upload = FileUploadWidget()
        self.file_upload.files_changed.connect(self.on_files_changed)
        layout.addWidget(self.file_upload)

        group.setLayout(layout)
        return group

    def create_script_section(self) -> QGroupBox:
        """스크립트 미리보기 섹션"""
        group = QGroupBox("Script Preview")
        group.setStyleSheet("QGroupBox { font-weight: bold; }")

        layout = QVBoxLayout()

        # Script Tabs
        self.script_text = QTextEdit()
        self.script_text.setReadOnly(True)
        self.script_text.setFont(QFont("Courier New", 9))
        self.script_text.setLineWrapMode(QTextEdit.NoWrap)
        self.script_text.setPlaceholderText("템플릿을 선택하면 스크립트가 표시됩니다...")

        layout.addWidget(self.script_text)

        group.setLayout(layout)
        return group

    def load_template(self, template_obj):
        """
        템플릿 로드 및 표시

        Args:
            template_obj: Template 객체
        """
        self.current_template = template_obj
        self.is_modified = False

        logger.info(f"Loading template: {template_obj.template.name}")

        # 1. Template Info
        self.name_edit.setText(template_obj.template.name)
        self.description_edit.setText(template_obj.template.description)
        self.category_label.setText(template_obj.template.category.upper())
        self.version_label.setText(template_obj.template.version)
        self.source_label.setText(template_obj.template.source)
        self.tags_label.setText(", ".join(template_obj.template.tags))

        # 2. Slurm Config
        self.partition_combo.setCurrentText(template_obj.slurm.partition)
        self.nodes_spin.setValue(template_obj.slurm.nodes)
        self.ntasks_spin.setValue(template_obj.slurm.ntasks)
        self.memory_edit.setText(template_obj.slurm.mem)
        self.time_edit.setText(template_obj.slurm.time)
        self.gpu_spin.setValue(template_obj.slurm.gpus or 0)

        # 3. Apptainer Config
        if template_obj.apptainer:
            self.image_label.setText(template_obj.apptainer.image_name)
            self.mode_label.setText(template_obj.apptainer.mode)
            self.bind_text.setText("\n".join(template_obj.apptainer.bind))
            env_text = "\n".join([f"{k}={v}" for k, v in template_obj.apptainer.env.items()])
            self.env_text.setText(env_text)
        else:
            self.image_label.setText("N/A")
            self.mode_label.setText("N/A")
            self.bind_text.setText("")
            self.env_text.setText("")

        # 4. File Schema
        self.populate_files_table(template_obj.files)

        # 5. File Upload
        if template_obj.files:
            self.file_upload.set_file_schema(template_obj.files)

        # 6. Script Preview
        self.update_script_preview()

        # UI 활성화
        self.enable_ui(True)

    def populate_files_table(self, file_schema):
        """파일 스키마 테이블 채우기"""
        self.files_table.setRowCount(0)

        if not file_schema:
            return

        row = 0

        # Required files
        for file_def in file_schema.required:
            self.files_table.insertRow(row)
            self.files_table.setItem(row, 0, QTableWidgetItem("✓ Yes"))
            self.files_table.setItem(row, 1, QTableWidgetItem(file_def.file_key))
            self.files_table.setItem(row, 2, QTableWidgetItem(file_def.name))
            extensions = ", ".join(file_def.validation.get('extensions', []))
            self.files_table.setItem(row, 3, QTableWidgetItem(extensions))
            row += 1

        # Optional files
        for file_def in file_schema.optional:
            self.files_table.insertRow(row)
            self.files_table.setItem(row, 0, QTableWidgetItem("○ No"))
            self.files_table.setItem(row, 1, QTableWidgetItem(file_def.file_key))
            self.files_table.setItem(row, 2, QTableWidgetItem(file_def.name))
            extensions = ", ".join(file_def.validation.get('extensions', []))
            self.files_table.setItem(row, 3, QTableWidgetItem(extensions))
            row += 1

    def update_script_preview(self):
        """스크립트 미리보기 업데이트"""
        if not self.current_template:
            self.script_text.clear()
            return

        # 스크립트 블록 조합
        script_parts = []

        if self.current_template.script.pre_exec:
            script_parts.append("# === Pre-Execution ===")
            script_parts.append(self.current_template.script.pre_exec)
            script_parts.append("")

        if self.current_template.script.main_exec:
            script_parts.append("# === Main Execution ===")
            script_parts.append(self.current_template.script.main_exec)
            script_parts.append("")

        if self.current_template.script.post_exec:
            script_parts.append("# === Post-Execution ===")
            script_parts.append(self.current_template.script.post_exec)

        self.script_text.setText("\n".join(script_parts))

    def on_config_changed(self):
        """설정 변경 이벤트"""
        if self.current_template:
            self.is_modified = True
            self.template_modified.emit()
            logger.debug("Template configuration modified")

    def on_memory_changed(self, text):
        """메모리 필드 변경 이벤트 (실시간 검증)"""
        # 빈 문자열이면 스타일 초기화
        if not text:
            self.memory_edit.setStyleSheet("")
            return

        # 검증: 숫자 + G/GB/M/MB 형식
        if re.match(r'^\d+[GMgm][Bb]?$', text):
            # 유효한 입력: 초록색 테두리
            self.memory_edit.setStyleSheet("border: 2px solid #4CAF50;")
        else:
            # 무효한 입력: 빨간색 테두리
            self.memory_edit.setStyleSheet("border: 2px solid #f44336;")

        self.on_config_changed()

    def on_time_changed(self, text):
        """시간 필드 변경 이벤트 (실시간 검증)"""
        # 빈 문자열이면 스타일 초기화
        if not text:
            self.time_edit.setStyleSheet("")
            return

        # 검증: HH:MM:SS 형식
        if re.match(r'^\d{1,2}:\d{2}:\d{2}$', text):
            # 추가 검증: 시간/분/초 범위 체크
            try:
                parts = text.split(':')
                hours = int(parts[0])
                minutes = int(parts[1])
                seconds = int(parts[2])

                if 0 <= hours <= 99 and 0 <= minutes <= 59 and 0 <= seconds <= 59:
                    # 유효한 입력: 초록색 테두리
                    self.time_edit.setStyleSheet("border: 2px solid #4CAF50;")
                else:
                    # 범위 초과: 주황색 테두리
                    self.time_edit.setStyleSheet("border: 2px solid #FF9800;")
            except (ValueError, IndexError):
                # 파싱 실패: 빨간색 테두리
                self.time_edit.setStyleSheet("border: 2px solid #f44336;")
        else:
            # 무효한 형식: 빨간색 테두리
            self.time_edit.setStyleSheet("border: 2px solid #f44336;")

        self.on_config_changed()

    def on_preview_clicked(self):
        """미리보기 버튼 클릭"""
        logger.info("Preview button clicked")
        self.preview_requested.emit()

    def on_submit_clicked(self):
        """제출 버튼 클릭"""
        logger.info("Submit button clicked")
        self.submit_requested.emit()

    def on_files_changed(self):
        """파일 업로드 변경 이벤트"""
        logger.debug("Files changed in upload widget")

        # 필수 파일 체크
        if self.current_template and self.file_upload.check_required_files():
            logger.info("All required files uploaded")

        # 템플릿 수정 플래그 설정
        if self.current_template:
            self.is_modified = True
            self.template_modified.emit()

    def show_empty_state(self):
        """빈 상태 표시"""
        self.enable_ui(False)
        self.name_edit.clear()
        self.description_edit.clear()
        self.category_label.setText("N/A")
        self.version_label.setText("N/A")
        self.source_label.setText("N/A")
        self.tags_label.setText("N/A")
        self.script_text.setPlaceholderText("템플릿을 선택하면 스크립트가 표시됩니다...")
        self.files_table.setRowCount(0)

    def enable_ui(self, enabled: bool):
        """UI 활성화/비활성화"""
        self.partition_combo.setEnabled(enabled)
        self.nodes_spin.setEnabled(enabled)
        self.ntasks_spin.setEnabled(enabled)
        self.memory_edit.setEnabled(enabled)
        self.time_edit.setEnabled(enabled)
        self.gpu_spin.setEnabled(enabled)
        self.preview_button.setEnabled(enabled)
        self.submit_button.setEnabled(enabled)

    def get_current_slurm_config(self) -> Optional[dict]:
        """현재 Slurm 설정 반환"""
        if not self.current_template:
            return None

        return {
            'partition': self.partition_combo.currentText(),
            'nodes': self.nodes_spin.value(),
            'ntasks': self.ntasks_spin.value(),
            'mem': self.memory_edit.text(),
            'time': self.time_edit.text(),
            'gpus': self.gpu_spin.value() if self.gpu_spin.value() > 0 else None,
        }

    def get_uploaded_files(self) -> Optional[dict]:
        """
        업로드된 파일 반환

        Returns:
            {file_key: file_path} 또는 None
        """
        if not self.current_template:
            return None

        return self.file_upload.get_uploaded_files()

    def get_file_variables(self) -> Optional[dict]:
        """
        파일 환경 변수 반환

        Returns:
            {'FILE_XXX': '/path/to/file'} 또는 None
        """
        if not self.current_template:
            return None

        return self.file_upload.get_file_variables()

    def clear(self):
        """에디터 초기화 (모든 입력 클리어)"""
        self.current_template = None

        # Template Info 섹션 클리어
        self.template_name_label.setText("No template selected")
        self.template_category_label.setText("")
        self.template_description_label.setText("")
        self.template_version_label.setText("")

        # Slurm Config 섹션 초기화
        self.partition_combo.setCurrentIndex(0)
        self.nodes_spin.setValue(1)
        self.ntasks_spin.setValue(4)
        self.memory_edit.setText("32G")
        self.time_edit.setText("02:00:00")
        self.gpu_spin.setValue(0)

        # 파일 업로드 클리어
        if self.file_upload:
            self.file_upload.clear()

        # 버튼 비활성화
        self.preview_button.setEnabled(False)
        self.submit_button.setEnabled(False)

        logger.debug("Template editor cleared")
