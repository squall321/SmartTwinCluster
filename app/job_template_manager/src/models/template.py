"""
Template 데이터 모델

YAML 템플릿 구조를 Python 클래스로 표현
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional
from pathlib import Path


@dataclass
class TemplateMetadata:
    """템플릿 메타데이터"""
    id: str
    name: str
    description: str = ""
    category: str = "custom"
    version: str = "1.0.0"
    source: str = "custom"  # official, community, private:username, custom
    tags: List[str] = field(default_factory=list)
    is_public: bool = False
    author: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


@dataclass
class SlurmConfig:
    """Slurm 작업 설정"""
    partition: str
    nodes: int
    ntasks: int
    mem: str
    time: str
    cpus_per_task: Optional[int] = None
    gpus: Optional[int] = None
    account: Optional[str] = None
    qos: Optional[str] = None

    def to_dict(self) -> dict:
        """딕셔너리로 변환"""
        result = {
            'partition': self.partition,
            'nodes': self.nodes,
            'ntasks': self.ntasks,
            'mem': self.mem,
            'time': self.time,
        }

        if self.cpus_per_task:
            result['cpus_per_task'] = self.cpus_per_task
        if self.gpus:
            result['gpus'] = self.gpus
        if self.account:
            result['account'] = self.account
        if self.qos:
            result['qos'] = self.qos

        return result


@dataclass
class ApptainerConfig:
    """Apptainer 컨테이너 설정"""
    image_name: str
    mode: str = "partition"  # partition, specific, any, fixed
    bind: List[str] = field(default_factory=list)
    env: Dict[str, str] = field(default_factory=dict)

    def __post_init__(self):
        """초기화 후 유효성 검증"""
        valid_modes = ['fixed', 'partition', 'specific', 'any']
        if self.mode not in valid_modes:
            raise ValueError(
                f"Invalid Apptainer mode: '{self.mode}'. "
                f"Must be one of: {', '.join(valid_modes)}"
            )

    def to_dict(self) -> dict:
        """딕셔너리로 변환"""
        return {
            'image_name': self.image_name,
            'mode': self.mode,
            'bind': self.bind,
            'env': self.env,
        }


@dataclass
class FileDefinition:
    """파일 정의"""
    file_key: str
    name: str
    description: str = ""
    pattern: str = "*"  # 웹 대시보드 호환: 파일 패턴 (예: "*.dat", "*.txt")
    type: str = "file"  # 웹 대시보드 호환: "file" 또는 "directory"
    validation: Dict = field(default_factory=dict)  # 추가 검증 규칙 (선택)
    max_size: Optional[str] = None

    def to_dict(self) -> dict:
        """딕셔너리로 변환"""
        result = {
            'file_key': self.file_key,
            'name': self.name,
            'description': self.description,
            'pattern': self.pattern,
            'type': self.type,
        }

        if self.validation:
            result['validation'] = self.validation
        if self.max_size:
            result['max_size'] = self.max_size

        return result


@dataclass
class FileSchema:
    """파일 스키마"""
    required: List[FileDefinition] = field(default_factory=list)
    optional: List[FileDefinition] = field(default_factory=list)

    def to_dict(self) -> dict:
        """딕셔너리로 변환"""
        return {
            'required': [f.to_dict() for f in self.required],
            'optional': [f.to_dict() for f in self.optional],
        }


@dataclass
class ScriptBlocks:
    """스크립트 블록"""
    pre_exec: str = ""
    main_exec: str = ""
    post_exec: str = ""

    def to_dict(self) -> dict:
        """딕셔너리로 변환"""
        return {
            'pre_exec': self.pre_exec,
            'main_exec': self.main_exec,
            'post_exec': self.post_exec,
        }


@dataclass
class Template:
    """Job Template 전체 구조"""
    template: TemplateMetadata
    slurm: SlurmConfig
    script: ScriptBlocks
    apptainer: Optional[ApptainerConfig] = None
    files: Optional[FileSchema] = None
    file_path: Optional[Path] = None  # YAML 파일 경로

    def to_dict(self) -> dict:
        """딕셔너리로 변환 (YAML 저장용)"""
        result = {
            'template': {
                'id': self.template.id,
                'name': self.template.name,
                'description': self.template.description,
                'category': self.template.category,
                'version': self.template.version,
                'source': self.template.source,
                'tags': self.template.tags,
                'is_public': self.template.is_public,
            },
            'slurm': self.slurm.to_dict(),
            'script': self.script.to_dict(),
        }

        if self.template.author:
            result['template']['author'] = self.template.author
        if self.template.created_at:
            result['template']['created_at'] = self.template.created_at
        if self.template.updated_at:
            result['template']['updated_at'] = self.template.updated_at

        if self.apptainer:
            result['apptainer'] = self.apptainer.to_dict()

        if self.files:
            result['files'] = {'input_schema': self.files.to_dict()}

        return result

    @staticmethod
    def from_dict(data: dict, file_path: Optional[Path] = None) -> 'Template':
        """딕셔너리에서 Template 생성"""
        # Template 메타데이터
        template_data = data.get('template', {})
        template_meta = TemplateMetadata(
            id=template_data['id'],
            name=template_data['name'],
            description=template_data.get('description', ''),
            category=template_data.get('category', 'custom'),
            version=template_data.get('version', '1.0.0'),
            source=template_data.get('source', 'custom'),
            tags=template_data.get('tags', []),
            is_public=template_data.get('is_public', False),
            author=template_data.get('author'),
            created_at=template_data.get('created_at'),
            updated_at=template_data.get('updated_at'),
        )

        # Slurm 설정
        slurm_data = data.get('slurm', {})
        slurm_config = SlurmConfig(
            partition=slurm_data['partition'],
            nodes=slurm_data['nodes'],
            ntasks=slurm_data['ntasks'],
            mem=slurm_data['mem'],
            time=slurm_data['time'],
            cpus_per_task=slurm_data.get('cpus_per_task'),
            gpus=slurm_data.get('gpus'),
            account=slurm_data.get('account'),
            qos=slurm_data.get('qos'),
        )

        # Script 블록
        script_data = data.get('script', {})
        script_blocks = ScriptBlocks(
            pre_exec=script_data.get('pre_exec', ''),
            main_exec=script_data.get('main_exec', ''),
            post_exec=script_data.get('post_exec', ''),
        )

        # Apptainer 설정 (선택)
        apptainer_config = None
        if 'apptainer' in data:
            apptainer_data = data['apptainer']
            apptainer_config = ApptainerConfig(
                image_name=apptainer_data['image_name'],
                mode=apptainer_data.get('mode', 'partition'),
                bind=apptainer_data.get('bind', []),
                env=apptainer_data.get('env', {}),
            )

        # 파일 스키마 (선택)
        file_schema = None
        if 'files' in data and 'input_schema' in data['files']:
            schema_data = data['files']['input_schema']

            required_files = []
            for file_def in schema_data.get('required', []):
                required_files.append(FileDefinition(
                    file_key=file_def['file_key'],
                    name=file_def['name'],
                    description=file_def.get('description', ''),
                    pattern=file_def.get('pattern', '*'),
                    type=file_def.get('type', 'file'),
                    validation=file_def.get('validation', {}),
                    max_size=file_def.get('max_size'),
                ))

            optional_files = []
            for file_def in schema_data.get('optional', []):
                optional_files.append(FileDefinition(
                    file_key=file_def['file_key'],
                    name=file_def['name'],
                    description=file_def.get('description', ''),
                    pattern=file_def.get('pattern', '*'),
                    type=file_def.get('type', 'file'),
                    validation=file_def.get('validation', {}),
                    max_size=file_def.get('max_size'),
                ))

            file_schema = FileSchema(
                required=required_files,
                optional=optional_files,
            )

        return Template(
            template=template_meta,
            slurm=slurm_config,
            script=script_blocks,
            apptainer=apptainer_config,
            files=file_schema,
            file_path=file_path,
        )

    def get_display_info(self) -> dict:
        """TemplateLibraryWidget 표시용 정보"""
        return {
            'id': self.template.id,
            'name': self.template.name,
            'description': self.template.description,
            'category': self.template.category,
            'source': self.template.source,
            'tags': self.template.tags,
            'version': self.template.version,
            'is_public': self.template.is_public,
        }
