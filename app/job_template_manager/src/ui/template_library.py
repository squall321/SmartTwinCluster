"""
Template Library Widget - 템플릿 라이브러리

좌측 패널: 카테고리별 템플릿 트리 + 검색 기능
"""

import logging
from pathlib import Path
from typing import Optional, List, Dict

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QTreeWidget, QTreeWidgetItem,
    QLineEdit, QPushButton, QLabel, QMenu, QAction
)
from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QIcon

logger = logging.getLogger(__name__)


class TemplateLibraryWidget(QWidget):
    """템플릿 라이브러리 위젯"""

    # 시그널 정의
    template_selected = pyqtSignal(dict)  # 템플릿 선택 시 발생
    template_double_clicked = pyqtSignal(dict)  # 템플릿 더블클릭 시 발생

    def __init__(self, parent=None):
        super().__init__(parent)

        self.templates = {}  # {template_id: template_data}
        self.filtered_templates = {}  # 검색 필터링된 템플릿

        self.init_ui()
        self.load_templates()

        logger.info("TemplateLibraryWidget initialized")

    def init_ui(self):
        """UI 초기화"""
        layout = QVBoxLayout()
        layout.setContentsMargins(5, 5, 5, 5)

        # 타이틀
        title_label = QLabel("템플릿 라이브러리")
        title_label.setStyleSheet("font-size: 14pt; font-weight: bold;")
        layout.addWidget(title_label)

        # 검색 바
        search_layout = QHBoxLayout()
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("🔍 템플릿 검색...")
        self.search_input.textChanged.connect(self.filter_templates)
        search_layout.addWidget(self.search_input)

        # 새 템플릿 버튼
        new_button = QPushButton("+ New")
        new_button.setMaximumWidth(60)
        new_button.clicked.connect(self.create_new_template)
        search_layout.addWidget(new_button)

        layout.addLayout(search_layout)

        # 템플릿 트리
        self.tree = QTreeWidget()
        self.tree.setHeaderLabel("Templates")
        self.tree.setContextMenuPolicy(Qt.CustomContextMenu)
        self.tree.customContextMenuRequested.connect(self.show_context_menu)
        self.tree.itemClicked.connect(self.on_item_clicked)
        self.tree.itemDoubleClicked.connect(self.on_item_double_clicked)
        layout.addWidget(self.tree)

        # 상태 레이블
        self.status_label = QLabel("0 templates")
        self.status_label.setStyleSheet("color: gray; font-size: 9pt;")
        layout.addWidget(self.status_label)

        self.setLayout(layout)

    def load_templates(self):
        """템플릿 로드"""
        # TODO: 실제로는 resources/templates/ 디렉토리에서 YAML 파일 로드
        # 지금은 샘플 데이터로 테스트

        sample_templates = [
            {
                'id': 'pytorch-gpu-training',
                'name': 'PyTorch GPU Training',
                'description': 'GPU 기반 딥러닝 학습',
                'category': 'ml',
                'source': 'official',
                'tags': ['pytorch', 'gpu', 'deep-learning']
            },
            {
                'id': 'tensorflow-distributed',
                'name': 'TensorFlow Distributed',
                'description': '분산 TensorFlow 학습',
                'category': 'ml',
                'source': 'official',
                'tags': ['tensorflow', 'distributed']
            },
            {
                'id': 'openfoam-cfd',
                'name': 'OpenFOAM CFD Simulation',
                'description': '유체 역학 시뮬레이션',
                'category': 'simulation',
                'source': 'official',
                'tags': ['openfoam', 'cfd', 'simulation']
            },
            {
                'id': 'gromacs-md',
                'name': 'GROMACS Molecular Dynamics',
                'description': '분자 동역학 시뮬레이션',
                'category': 'simulation',
                'source': 'official',
                'tags': ['gromacs', 'molecular-dynamics']
            },
            {
                'id': 'lsdyna-crash',
                'name': 'LS-DYNA Crash Analysis',
                'description': '충돌 해석',
                'category': 'simulation',
                'source': 'official',
                'tags': ['lsdyna', 'crash', 'analysis']
            },
            {
                'id': 'python-data-processing',
                'name': 'Python Data Processing',
                'description': '대용량 데이터 처리',
                'category': 'data',
                'source': 'official',
                'tags': ['python', 'data']
            },
            {
                'id': 'jupyter-notebook',
                'name': 'Jupyter Notebook',
                'description': 'Jupyter 노트북 실행',
                'category': 'data',
                'source': 'community',
                'tags': ['jupyter', 'python']
            },
        ]

        for template_data in sample_templates:
            self.templates[template_data['id']] = template_data

        self.filtered_templates = self.templates.copy()
        self.populate_tree()

        logger.info(f"Loaded {len(self.templates)} templates")

    def populate_tree(self):
        """트리 위젯 채우기"""
        self.tree.clear()

        # 카테고리별로 그룹화
        categories = {
            'ml': 'Machine Learning',
            'simulation': 'Simulation',
            'data': 'Data Processing',
            'compute': 'Compute',
            'container': 'Container',
            'custom': 'Custom Templates'
        }

        category_items = {}

        # 카테고리 아이템 생성
        for cat_id, cat_name in categories.items():
            item = QTreeWidgetItem([cat_name])
            item.setData(0, Qt.UserRole, {'type': 'category', 'id': cat_id})
            self.tree.addTopLevelItem(item)
            category_items[cat_id] = item

        # 템플릿 추가
        for template_id, template_data in self.filtered_templates.items():
            category = template_data.get('category', 'custom')
            parent_item = category_items.get(category)

            if parent_item:
                template_item = QTreeWidgetItem([template_data['name']])
                template_item.setData(0, Qt.UserRole, {
                    'type': 'template',
                    'id': template_id,
                    'data': template_data
                })
                template_item.setToolTip(0, template_data.get('description', ''))
                parent_item.addChild(template_item)

        # 카테고리 확장
        for item in category_items.values():
            item.setExpanded(True)

        # 상태 업데이트
        self.status_label.setText(f"{len(self.filtered_templates)} templates")

    def filter_templates(self, search_text: str):
        """템플릿 필터링"""
        search_text = search_text.lower().strip()

        if not search_text:
            self.filtered_templates = self.templates.copy()
        else:
            self.filtered_templates = {
                tid: tdata for tid, tdata in self.templates.items()
                if (search_text in tdata['name'].lower() or
                    search_text in tdata.get('description', '').lower() or
                    any(search_text in tag for tag in tdata.get('tags', [])))
            }

        self.populate_tree()
        logger.debug(f"Filtered templates: {len(self.filtered_templates)}/{len(self.templates)}")

    def on_item_clicked(self, item: QTreeWidgetItem, column: int):
        """아이템 클릭 이벤트"""
        item_data = item.data(0, Qt.UserRole)

        if item_data and item_data.get('type') == 'template':
            template_data = item_data['data']
            self.template_selected.emit(template_data)
            logger.debug(f"Template selected: {template_data['id']}")

    def on_item_double_clicked(self, item: QTreeWidgetItem, column: int):
        """아이템 더블클릭 이벤트"""
        item_data = item.data(0, Qt.UserRole)

        if item_data and item_data.get('type') == 'template':
            template_data = item_data['data']
            self.template_double_clicked.emit(template_data)
            logger.info(f"Template double-clicked: {template_data['id']}")

    def show_context_menu(self, position):
        """컨텍스트 메뉴 표시"""
        item = self.tree.itemAt(position)
        if not item:
            return

        item_data = item.data(0, Qt.UserRole)
        if not item_data or item_data.get('type') != 'template':
            return

        menu = QMenu()

        # 템플릿 사용
        use_action = QAction("Use Template", self)
        use_action.triggered.connect(lambda: self.on_item_double_clicked(item, 0))
        menu.addAction(use_action)

        menu.addSeparator()

        # 템플릿 편집
        edit_action = QAction("Edit Template", self)
        edit_action.triggered.connect(lambda: self.edit_template(item_data['data']))
        menu.addAction(edit_action)

        # 템플릿 복제
        duplicate_action = QAction("Duplicate Template", self)
        duplicate_action.triggered.connect(lambda: self.duplicate_template(item_data['data']))
        menu.addAction(duplicate_action)

        # 템플릿 내보내기
        export_action = QAction("Export as YAML", self)
        export_action.triggered.connect(lambda: self.export_template(item_data['data']))
        menu.addAction(export_action)

        menu.addSeparator()

        # 템플릿 삭제 (Custom만)
        if item_data['data'].get('source') == 'custom':
            delete_action = QAction("Delete Template", self)
            delete_action.triggered.connect(lambda: self.delete_template(item_data['data']))
            menu.addAction(delete_action)

        menu.exec_(self.tree.viewport().mapToGlobal(position))

    def create_new_template(self):
        """새 템플릿 생성"""
        logger.info("Create new template clicked")
        # TODO: 새 템플릿 다이얼로그 표시

    def edit_template(self, template_data: dict):
        """템플릿 편집"""
        logger.info(f"Edit template: {template_data['id']}")
        # TODO: 템플릿 에디터에서 열기

    def duplicate_template(self, template_data: dict):
        """템플릿 복제"""
        logger.info(f"Duplicate template: {template_data['id']}")
        # TODO: 템플릿 복제 로직

    def export_template(self, template_data: dict):
        """템플릿 YAML로 내보내기"""
        logger.info(f"Export template: {template_data['id']}")
        # TODO: 파일 저장 다이얼로그

    def delete_template(self, template_data: dict):
        """템플릿 삭제"""
        logger.info(f"Delete template: {template_data['id']}")
        # TODO: 확인 다이얼로그 + 삭제

    def get_selected_template(self) -> Optional[dict]:
        """선택된 템플릿 반환"""
        current_item = self.tree.currentItem()
        if not current_item:
            return None

        item_data = current_item.data(0, Qt.UserRole)
        if item_data and item_data.get('type') == 'template':
            return item_data['data']

        return None
