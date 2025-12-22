"""
Template Creator Dialog - 템플릿 생성/편집 다이얼로그

사용자가 새로운 템플릿을 만들거나 기존 템플릿을 편집할 수 있는 다이얼로그
"""

import logging
from pathlib import Path
from typing import Optional, Dict, List
from datetime import datetime

from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QFormLayout,
    QLineEdit, QTextEdit, QComboBox, QSpinBox, QCheckBox,
    QPushButton, QGroupBox, QTabWidget, QWidget, QLabel,
    QMessageBox, QTableWidget, QTableWidgetItem, QHeaderView
)
from PyQt5.QtCore import Qt, QSize
from PyQt5.QtGui import QFont

from models.template import Template, TemplateMetadata, SlurmConfig, ApptainerConfig, ScriptBlocks, FileSchema, FileDefinition

logger = logging.getLogger(__name__)


class TemplateCreatorDialog(QDialog):
    """템플릿 생성/편집 다이얼로그"""

    def __init__(self, parent=None, template: Optional[Template] = None):
        """
        초기화

        Args:
            parent: 부모 위젯
            template: 편집할 템플릿 (None이면 새 템플릿 생성 모드)
        """
        super().__init__(parent)

        self.template = template
        self.is_edit_mode = template is not None

        self.init_ui()

        if self.is_edit_mode:
            self.load_template(template)

        logger.info(f"TemplateCreatorDialog initialized (edit_mode={self.is_edit_mode})")

    def init_ui(self):
        """UI 초기화"""
        title = "Edit Template" if self.is_edit_mode else "Create New Template"
        self.setWindowTitle(title)
        self.setMinimumSize(QSize(900, 700))

        layout = QVBoxLayout()

        # 타이틀
        title_label = QLabel(f"📝 {title}")
        title_label.setStyleSheet("font-size: 14pt; font-weight: bold;")
        layout.addWidget(title_label)

        # 탭 위젯
        self.tabs = QTabWidget()
        self.tabs.addTab(self.create_basic_info_tab(), "📋 Basic Info")
        self.tabs.addTab(self.create_slurm_config_tab(), "⚙️ Slurm Config")
        self.tabs.addTab(self.create_apptainer_tab(), "📦 Apptainer")
        self.tabs.addTab(self.create_files_tab(), "📁 Files Schema")
        self.tabs.addTab(self.create_script_tab(), "📜 Script Blocks")

        layout.addWidget(self.tabs)

        # 하단 버튼
        button_layout = QHBoxLayout()

        self.validate_button = QPushButton("🔍 Validate")
        self.validate_button.setToolTip("Validate template configuration\n"
                                       "Checks for required fields and correct formats")
        self.validate_button.clicked.connect(self.validate_template)
        button_layout.addWidget(self.validate_button)

        button_layout.addStretch()

        self.cancel_button = QPushButton("Cancel")
        self.cancel_button.setToolTip("Close dialog without saving changes")
        self.cancel_button.clicked.connect(self.reject)
        button_layout.addWidget(self.cancel_button)

        self.save_button = QPushButton("💾 Save Template")
        self.save_button.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold;")
        self.save_button.setToolTip("Save template to YAML file\n"
                                   "Template will be available in the library")
        self.save_button.clicked.connect(self.save_template)
        button_layout.addWidget(self.save_button)

        layout.addLayout(button_layout)

        self.setLayout(layout)

    def create_basic_info_tab(self) -> QWidget:
        """기본 정보 탭"""
        widget = QWidget()
        layout = QFormLayout()

        # Template ID
        self.id_edit = QLineEdit()
        self.id_edit.setPlaceholderText("e.g., my-custom-template")
        self.id_edit.setToolTip("Unique identifier for this template\n"
                               "Use lowercase letters, numbers, and hyphens only\n"
                               "Cannot be changed after creation")
        if self.is_edit_mode:
            self.id_edit.setEnabled(False)  # 편집 모드에서는 ID 변경 불가
        layout.addRow("Template ID *:", self.id_edit)

        # Template Name
        self.name_edit = QLineEdit()
        self.name_edit.setPlaceholderText("e.g., My Custom Template")
        self.name_edit.setToolTip("Display name for this template\n"
                                 "Can contain any characters and spaces")
        layout.addRow("Template Name *:", self.name_edit)

        # Category
        self.category_combo = QComboBox()
        self.category_combo.addItems([
            "ml",           # Machine Learning
            "simulation",   # Simulation
            "data",         # Data Processing
            "custom"        # Custom
        ])
        self.category_combo.setToolTip("Template category for organization\n"
                                       "ml: Machine Learning\n"
                                       "simulation: Simulation jobs\n"
                                       "data: Data processing\n"
                                       "custom: Custom templates")
        layout.addRow("Category *:", self.category_combo)

        # Description
        self.description_edit = QTextEdit()
        self.description_edit.setPlaceholderText("Template description...")
        self.description_edit.setMaximumHeight(100)
        self.description_edit.setToolTip("Detailed description of what this template does\n"
                                        "Include purpose, requirements, and usage notes")
        layout.addRow("Description:", self.description_edit)

        # Version
        self.version_edit = QLineEdit()
        self.version_edit.setText("1.0.0")
        self.version_edit.setToolTip("Template version in semantic versioning format\n"
                                    "Example: 1.0.0, 1.2.3, 2.0.0-beta")
        layout.addRow("Version:", self.version_edit)

        # Source
        self.source_combo = QComboBox()
        self.source_combo.addItems(["custom", "official", "community"])
        self.source_combo.setToolTip("Template source/origin\n"
                                     "custom: User-created template\n"
                                     "official: Official template\n"
                                     "community: Community-contributed")
        layout.addRow("Source:", self.source_combo)

        widget.setLayout(layout)
        return widget

    def create_slurm_config_tab(self) -> QWidget:
        """Slurm 설정 탭"""
        widget = QWidget()
        layout = QFormLayout()

        # Partition
        self.partition_combo = QComboBox()
        self.partition_combo.addItems(["compute", "gpu", "highmem", "debug"])
        layout.addRow("Partition *:", self.partition_combo)

        # Nodes
        self.nodes_spin = QSpinBox()
        self.nodes_spin.setRange(1, 100)
        self.nodes_spin.setValue(1)
        layout.addRow("Nodes *:", self.nodes_spin)

        # Tasks
        self.ntasks_spin = QSpinBox()
        self.ntasks_spin.setRange(1, 1000)
        self.ntasks_spin.setValue(4)
        layout.addRow("Tasks (ntasks) *:", self.ntasks_spin)

        # Memory
        self.mem_edit = QLineEdit()
        self.mem_edit.setText("32G")
        self.mem_edit.setPlaceholderText("e.g., 32G, 64G, 128G")
        layout.addRow("Memory *:", self.mem_edit)

        # Time
        self.time_edit = QLineEdit()
        self.time_edit.setText("02:00:00")
        self.time_edit.setPlaceholderText("HH:MM:SS")
        layout.addRow("Time Limit *:", self.time_edit)

        # GPUs (optional)
        self.gpu_spin = QSpinBox()
        self.gpu_spin.setRange(0, 8)
        self.gpu_spin.setValue(0)
        layout.addRow("GPUs (optional):", self.gpu_spin)

        widget.setLayout(layout)
        return widget

    def create_apptainer_tab(self) -> QWidget:
        """Apptainer 설정 탭"""
        widget = QWidget()
        layout = QVBoxLayout()

        # Enable Apptainer 체크박스
        self.apptainer_enable = QCheckBox("Enable Apptainer Container")
        self.apptainer_enable.setChecked(True)
        self.apptainer_enable.stateChanged.connect(self.on_apptainer_toggled)
        layout.addWidget(self.apptainer_enable)

        # Apptainer 설정 그룹
        self.apptainer_group = QGroupBox("Apptainer Configuration")
        apptainer_layout = QFormLayout()

        # Image Name
        self.image_name_edit = QLineEdit()
        self.image_name_edit.setPlaceholderText("e.g., KooSimulationPython313.sif")
        apptainer_layout.addRow("Image Name *:", self.image_name_edit)

        # Mode
        self.apptainer_mode_combo = QComboBox()
        self.apptainer_mode_combo.addItems(["partition", "custom_path"])
        apptainer_layout.addRow("Mode:", self.apptainer_mode_combo)

        # Bind Paths
        self.bind_edit = QTextEdit()
        self.bind_edit.setPlaceholderText("One bind path per line, e.g.:\n/shared:/shared\n/data:/data")
        self.bind_edit.setMaximumHeight(80)
        apptainer_layout.addRow("Bind Paths:", self.bind_edit)

        # Environment Variables
        self.env_edit = QTextEdit()
        self.env_edit.setPlaceholderText("One env var per line, e.g.:\nPYTHONPATH=/app\nCUDA_VISIBLE_DEVICES=0")
        self.env_edit.setMaximumHeight(80)
        apptainer_layout.addRow("Environment Vars:", self.env_edit)

        self.apptainer_group.setLayout(apptainer_layout)
        layout.addWidget(self.apptainer_group)

        layout.addStretch()
        widget.setLayout(layout)
        return widget

    def create_files_tab(self) -> QWidget:
        """파일 스키마 탭"""
        widget = QWidget()
        layout = QVBoxLayout()

        # 설명
        info_label = QLabel("Define required and optional file inputs for this template.")
        info_label.setStyleSheet("color: gray; font-style: italic;")
        layout.addWidget(info_label)

        # 필수 파일
        required_group = QGroupBox("Required Files")
        required_layout = QVBoxLayout()

        self.required_files_table = QTableWidget(0, 4)
        self.required_files_table.setHorizontalHeaderLabels(["File Key", "Name", "Extensions", ""])
        self.required_files_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        required_layout.addWidget(self.required_files_table)

        add_required_btn = QPushButton("➕ Add Required File")
        add_required_btn.clicked.connect(lambda: self.add_file_row(self.required_files_table))
        required_layout.addWidget(add_required_btn)

        required_group.setLayout(required_layout)
        layout.addWidget(required_group)

        # 선택적 파일
        optional_group = QGroupBox("Optional Files")
        optional_layout = QVBoxLayout()

        self.optional_files_table = QTableWidget(0, 4)
        self.optional_files_table.setHorizontalHeaderLabels(["File Key", "Name", "Extensions", ""])
        self.optional_files_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        optional_layout.addWidget(self.optional_files_table)

        add_optional_btn = QPushButton("➕ Add Optional File")
        add_optional_btn.clicked.connect(lambda: self.add_file_row(self.optional_files_table))
        optional_layout.addWidget(add_optional_btn)

        optional_group.setLayout(optional_layout)
        layout.addWidget(optional_group)

        widget.setLayout(layout)
        return widget

    def create_script_tab(self) -> QWidget:
        """스크립트 블록 탭"""
        widget = QWidget()
        layout = QVBoxLayout()

        # Pre-execution
        pre_exec_group = QGroupBox("Pre-execution Script")
        pre_exec_layout = QVBoxLayout()
        self.pre_exec_edit = QTextEdit()
        self.pre_exec_edit.setFont(QFont("Courier New", 10))
        self.pre_exec_edit.setPlaceholderText("# Commands to run before main execution\necho \"Starting job...\"")
        pre_exec_layout.addWidget(self.pre_exec_edit)
        pre_exec_group.setLayout(pre_exec_layout)
        layout.addWidget(pre_exec_group)

        # Main execution
        main_exec_group = QGroupBox("Main Execution Script *")
        main_exec_layout = QVBoxLayout()
        self.main_exec_edit = QTextEdit()
        self.main_exec_edit.setFont(QFont("Courier New", 10))
        self.main_exec_edit.setPlaceholderText("# Main command to execute\napptainer exec $APPTAINER_IMAGE python script.py")
        main_exec_layout.addWidget(self.main_exec_edit)
        main_exec_group.setLayout(main_exec_layout)
        layout.addWidget(main_exec_group)

        # Post-execution
        post_exec_group = QGroupBox("Post-execution Script")
        post_exec_layout = QVBoxLayout()
        self.post_exec_edit = QTextEdit()
        self.post_exec_edit.setFont(QFont("Courier New", 10))
        self.post_exec_edit.setPlaceholderText("# Commands to run after main execution\necho \"Job completed.\"")
        post_exec_layout.addWidget(self.post_exec_edit)
        post_exec_group.setLayout(post_exec_layout)
        layout.addWidget(post_exec_group)

        widget.setLayout(layout)
        return widget

    def add_file_row(self, table: QTableWidget):
        """파일 테이블에 행 추가"""
        row = table.rowCount()
        table.insertRow(row)

        # File Key
        table.setItem(row, 0, QTableWidgetItem(""))

        # Name
        table.setItem(row, 1, QTableWidgetItem(""))

        # Extensions
        table.setItem(row, 2, QTableWidgetItem(".py,.sh"))

        # Delete button
        delete_btn = QPushButton("🗑️")
        delete_btn.clicked.connect(lambda: table.removeRow(table.indexAt(delete_btn.pos()).row()))
        table.setCellWidget(row, 3, delete_btn)

    def on_apptainer_toggled(self, state):
        """Apptainer 활성화/비활성화 토글"""
        self.apptainer_group.setEnabled(state == Qt.Checked)

    def load_template(self, template: Template):
        """기존 템플릿 데이터 로드"""
        # Basic Info
        self.id_edit.setText(template.template.id)
        self.name_edit.setText(template.template.name)
        self.category_combo.setCurrentText(template.template.category)
        self.description_edit.setPlainText(template.template.description or "")
        self.version_edit.setText(template.template.version)
        self.source_combo.setCurrentText(template.template.source)

        # Slurm Config
        self.partition_combo.setCurrentText(template.slurm.partition)
        self.nodes_spin.setValue(template.slurm.nodes)
        self.ntasks_spin.setValue(template.slurm.ntasks)
        self.mem_edit.setText(template.slurm.mem)
        self.time_edit.setText(template.slurm.time)
        if template.slurm.gpus:
            self.gpu_spin.setValue(template.slurm.gpus)

        # Apptainer
        if template.apptainer:
            self.apptainer_enable.setChecked(True)
            self.image_name_edit.setText(template.apptainer.image_name)
            self.apptainer_mode_combo.setCurrentText(template.apptainer.mode)

            if template.apptainer.bind:
                self.bind_edit.setPlainText("\n".join(template.apptainer.bind))

            if template.apptainer.env:
                env_lines = [f"{k}={v}" for k, v in template.apptainer.env.items()]
                self.env_edit.setPlainText("\n".join(env_lines))
        else:
            self.apptainer_enable.setChecked(False)

        # Files
        if template.files:
            for file_def in template.files.required:
                self.add_file_to_table(self.required_files_table, file_def)

            for file_def in template.files.optional:
                self.add_file_to_table(self.optional_files_table, file_def)

        # Script Blocks
        self.pre_exec_edit.setPlainText(template.script.pre_exec)
        self.main_exec_edit.setPlainText(template.script.main_exec)
        self.post_exec_edit.setPlainText(template.script.post_exec)

        logger.debug(f"Template loaded: {template.template.id}")

    def add_file_to_table(self, table: QTableWidget, file_def: FileDefinition):
        """파일 정의를 테이블에 추가"""
        row = table.rowCount()
        table.insertRow(row)

        table.setItem(row, 0, QTableWidgetItem(file_def.file_key))
        table.setItem(row, 1, QTableWidgetItem(file_def.name))

        extensions = ",".join(file_def.validation.extensions) if file_def.validation and file_def.validation.extensions else ""
        table.setItem(row, 2, QTableWidgetItem(extensions))

        delete_btn = QPushButton("🗑️")
        delete_btn.clicked.connect(lambda: table.removeRow(table.indexAt(delete_btn.pos()).row()))
        table.setCellWidget(row, 3, delete_btn)

    def validate_template(self) -> bool:
        """템플릿 검증"""
        errors = []

        # Basic Info 검증
        if not self.id_edit.text().strip():
            errors.append("Template ID is required")

        if not self.name_edit.text().strip():
            errors.append("Template Name is required")

        # Slurm Config 검증
        if not self.mem_edit.text().strip():
            errors.append("Memory configuration is required")

        if not self.time_edit.text().strip():
            errors.append("Time limit is required")

        # Apptainer 검증
        if self.apptainer_enable.isChecked():
            if not self.image_name_edit.text().strip():
                errors.append("Apptainer Image Name is required when Apptainer is enabled")

        # Script 검증
        if not self.main_exec_edit.toPlainText().strip():
            errors.append("Main execution script is required")

        if errors:
            error_msg = "\n".join([f"• {err}" for err in errors])
            QMessageBox.warning(
                self,
                "Validation Failed",
                f"Please fix the following errors:\n\n{error_msg}"
            )
            return False
        else:
            QMessageBox.information(
                self,
                "Validation Successful",
                "✓ Template is valid and ready to save!"
            )
            return True

    def get_template_data(self) -> Template:
        """입력된 데이터로 Template 객체 생성"""
        # TemplateMetadata
        template_meta = TemplateMetadata(
            id=self.id_edit.text().strip(),
            name=self.name_edit.text().strip(),
            category=self.category_combo.currentText(),
            description=self.description_edit.toPlainText().strip() or None,
            version=self.version_edit.text().strip(),
            source=self.source_combo.currentText(),
            created_at=datetime.now().isoformat() if not self.is_edit_mode else None,
            updated_at=datetime.now().isoformat()
        )

        # SlurmConfig
        slurm_config = SlurmConfig(
            partition=self.partition_combo.currentText(),
            nodes=self.nodes_spin.value(),
            ntasks=self.ntasks_spin.value(),
            mem=self.mem_edit.text().strip(),
            time=self.time_edit.text().strip(),
            gpus=self.gpu_spin.value() if self.gpu_spin.value() > 0 else None
        )

        # ApptainerConfig
        apptainer_config = None
        if self.apptainer_enable.isChecked():
            bind_paths = [line.strip() for line in self.bind_edit.toPlainText().split('\n') if line.strip()]

            env_dict = {}
            for line in self.env_edit.toPlainText().split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    env_dict[key.strip()] = value.strip()

            apptainer_config = ApptainerConfig(
                image_name=self.image_name_edit.text().strip(),
                mode=self.apptainer_mode_combo.currentText(),
                bind=bind_paths if bind_paths else None,
                env=env_dict if env_dict else None
            )

        # FileSchema
        required_files = self.extract_files_from_table(self.required_files_table)
        optional_files = self.extract_files_from_table(self.optional_files_table)

        file_schema = None
        if required_files or optional_files:
            file_schema = FileSchema(
                required=required_files if required_files else [],
                optional=optional_files if optional_files else []
            )

        # ScriptBlocks
        script_blocks = ScriptBlocks(
            pre_exec=self.pre_exec_edit.toPlainText().strip(),
            main_exec=self.main_exec_edit.toPlainText().strip(),
            post_exec=self.post_exec_edit.toPlainText().strip()
        )

        # Template
        template = Template(
            template=template_meta,
            slurm=slurm_config,
            script=script_blocks,
            apptainer=apptainer_config,
            files=file_schema
        )

        return template

    def extract_files_from_table(self, table: QTableWidget) -> List[FileDefinition]:
        """테이블에서 파일 정의 추출"""
        files = []

        for row in range(table.rowCount()):
            file_key_item = table.item(row, 0)
            name_item = table.item(row, 1)
            ext_item = table.item(row, 2)

            if not file_key_item or not name_item:
                continue

            file_key = file_key_item.text().strip()
            name = name_item.text().strip()
            extensions = ext_item.text().strip() if ext_item else ""

            if not file_key or not name:
                continue

            # FileDefinition 생성
            from models.template import FileValidation

            ext_list = [ext.strip() for ext in extensions.split(',') if ext.strip()]

            file_def = FileDefinition(
                file_key=file_key,
                name=name,
                validation=FileValidation(
                    extensions=ext_list if ext_list else None
                ) if ext_list else None
            )

            files.append(file_def)

        return files

    def save_template(self):
        """템플릿 저장"""
        # 검증
        if not self.validate_template():
            return

        try:
            # Template 객체 생성
            template = self.get_template_data()

            # 다이얼로그 성공적으로 닫기
            self.template = template
            self.accept()

            logger.info(f"Template saved: {template.template.id}")

        except Exception as e:
            logger.error(f"Failed to save template: {e}", exc_info=True)
            QMessageBox.critical(
                self,
                "Save Failed",
                f"Failed to save template:\n{str(e)}"
            )

    def get_template(self) -> Optional[Template]:
        """생성/편집된 템플릿 반환"""
        return self.template
