# services/job_template_manager.py

import os
import json
import yaml
from typing import Dict, List, Any, Optional
from datetime import datetime
from werkzeug.utils import secure_filename

class JobTemplateManager:
    """사용자 정의 SLURM 작업 템플릿 관리"""
    
    def __init__(self, base_dir: str = "job_templates"):
        self.base_dir = base_dir
        self.templates_dir = os.path.join(base_dir, "templates")
        self.examples_dir = os.path.join(base_dir, "examples")
        
        # 디렉토리 생성
        os.makedirs(self.templates_dir, exist_ok=True)
        os.makedirs(self.examples_dir, exist_ok=True)
        
        # 기본 템플릿 생성
        self._create_default_templates()
    
    def _create_default_templates(self):
        """기본 템플릿 파일들 생성"""
        default_templates = {
            "lsdyna_basic.yaml": {
                "name": "LS-DYNA Basic",
                "description": "기본 LS-DYNA 시뮬레이션 템플릿",
                "category": "lsdyna",
                "parameters": {
                    "job_name": {"type": "string", "required": True, "default": "lsdyna_job"},
                    "cores": {"type": "int", "required": True, "default": 16, "options": [16, 32, 64, 128]},
                    "time_limit": {"type": "string", "required": True, "default": "02:00:00"},
                    "partition": {"type": "string", "required": False, "default": "debug"},
                    "version": {"type": "string", "required": True, "default": "R12", "options": ["R11", "R12", "R13"]},
                    "mode": {"type": "string", "required": True, "default": "smp", "options": ["smp", "mpp"]},
                    "precision": {"type": "string", "required": True, "default": "double", "options": ["single", "double"]},
                    "memory": {"type": "string", "required": False, "default": "4GB"}
                },
                "input_files": {
                    "main_input": {"extension": ".k", "required": True, "description": "메인 K 파일"},
                    "include_files": {"extension": ".k", "required": False, "multiple": True, "description": "추가 Include 파일들"}
                },
                "template": """#!/bin/bash
#SBATCH -J {{job_name}}
#SBATCH -n {{cores}}
#SBATCH --time={{time_limit}}
#SBATCH -o {{output_dir}}/{{job_name}}.out
#SBATCH -e {{output_dir}}/{{job_name}}.err
{% if partition %}#SBATCH -p {{partition}}{% endif %}
{% if memory %}#SBATCH --mem={{memory}}{% endif %}

# Job Information
echo "=================================="
echo "Job Name: {{job_name}}"
echo "Cores: {{cores}}"
echo "Started: $(date)"
echo "Node: $SLURM_JOB_NODELIST"
echo "=================================="

# Environment Setup
{% if version %}
module load lsdyna/{{version}}
{% endif %}

# Run LS-DYNA
echo "Starting LS-DYNA simulation..."
lsdyna_{{version|lower}}_{{mode}}_{{precision}} i={{input_files.main_input}} ncpu={{cores}}

echo "Job completed: $(date)"
"""
            }
        }
        
        # YAML 템플릿 파일들 생성
        for filename, template_data in default_templates.items():
            template_path = os.path.join(self.examples_dir, filename)
            if not os.path.exists(template_path):
                with open(template_path, 'w', encoding='utf-8') as f:
                    yaml.dump(template_data, f, default_flow_style=False, allow_unicode=True)
    
    def list_templates(self, category: Optional[str] = None) -> List[Dict[str, Any]]:
        """템플릿 목록 조회"""
        templates = []
        
        # examples와 templates 디렉토리 모두 스캔
        for template_dir in [self.examples_dir, self.templates_dir]:
            if not os.path.exists(template_dir):
                continue
                
            for filename in os.listdir(template_dir):
                if filename.endswith(('.yaml', '.yml')):
                    try:
                        template_path = os.path.join(template_dir, filename)
                        with open(template_path, 'r', encoding='utf-8') as f:
                            template_data = yaml.safe_load(f)
                        
                        template_info = {
                            "filename": filename,
                            "path": template_path,
                            "name": template_data.get("name", filename),
                            "description": template_data.get("description", ""),
                            "category": template_data.get("category", "general"),
                            "parameters": list(template_data.get("parameters", {}).keys()),
                            "input_files": list(template_data.get("input_files", {}).keys()),
                            "is_example": template_dir == self.examples_dir
                        }
                        
                        # 카테고리 필터링
                        if category is None or template_info["category"] == category:
                            templates.append(template_info)
                            
                    except Exception as e:
                        print(f"Warning: Failed to load template {filename}: {e}")
        
        return sorted(templates, key=lambda x: (x["category"], x["name"]))
    
    def get_template(self, template_name: str) -> Optional[Dict[str, Any]]:
        """특정 템플릿 조회"""
        # .yaml 확장자 자동 추가
        if not template_name.endswith(('.yaml', '.yml')):
            template_name += '.yaml'
        
        # templates 디렉토리 먼저 검색, 없으면 examples에서 검색
        for template_dir in [self.templates_dir, self.examples_dir]:
            template_path = os.path.join(template_dir, template_name)
            if os.path.exists(template_path):
                try:
                    with open(template_path, 'r', encoding='utf-8') as f:
                        return yaml.safe_load(f)
                except Exception as e:
                    raise ValueError(f"Failed to load template {template_name}: {e}")
        
        return None
    
    def save_template(self, template_name: str, template_data: Dict[str, Any]) -> bool:
        """새 템플릿 저장"""
        if not template_name.endswith(('.yaml', '.yml')):
            template_name += '.yaml'
        
        template_name = secure_filename(template_name)
        template_path = os.path.join(self.templates_dir, template_name)
        
        try:
            # 템플릿 유효성 검사
            self._validate_template(template_data)
            
            with open(template_path, 'w', encoding='utf-8') as f:
                yaml.dump(template_data, f, default_flow_style=False, allow_unicode=True)
            
            return True
        except Exception as e:
            raise ValueError(f"Failed to save template: {e}")
    
    def delete_template(self, template_name: str) -> bool:
        """템플릿 삭제 (사용자 템플릿만)"""
        if not template_name.endswith(('.yaml', '.yml')):
            template_name += '.yaml'
        
        template_path = os.path.join(self.templates_dir, template_name)
        if os.path.exists(template_path):
            os.remove(template_path)
            return True
        
        return False
    
    def _validate_template(self, template_data: Dict[str, Any]):
        """템플릿 유효성 검사"""
        required_fields = ["name", "template"]
        for field in required_fields:
            if field not in template_data:
                raise ValueError(f"Missing required field: {field}")
        
        # Jinja2 템플릿 구문 간단 검사
        template_content = template_data["template"]
        if "{{" in template_content and "}}" not in template_content:
            raise ValueError("Invalid Jinja2 template syntax")
    
    def render_template(self, template_name: str, parameters: Dict[str, Any], 
                       input_files: Dict[str, str], work_dir: str, output_dir: str) -> str:
        """템플릿 렌더링"""
        from jinja2 import Template, Environment
        
        template_data = self.get_template(template_name)
        if not template_data:
            raise ValueError(f"Template not found: {template_name}")
        
        # 템플릿 파라미터 검증
        self._validate_parameters(template_data, parameters)
        
        # Jinja2 환경 설정
        env = Environment()
        template = env.from_string(template_data["template"])
        
        # 렌더링 컨텍스트 준비
        context = {
            **parameters,
            "input_files": input_files,
            "work_dir": work_dir,
            "output_dir": output_dir,
            "timestamp": datetime.now().strftime("%Y%m%d_%H%M%S")
        }
        
        return template.render(**context)
    
    def _validate_parameters(self, template_data: Dict[str, Any], parameters: Dict[str, Any]):
        """파라미터 유효성 검사"""
        template_params = template_data.get("parameters", {})
        
        for param_name, param_config in template_params.items():
            if param_config.get("required", False) and param_name not in parameters:
                raise ValueError(f"Required parameter missing: {param_name}")
            
            if param_name in parameters:
                param_value = parameters[param_name]
                param_type = param_config.get("type", "string")
                
                # 타입 검사
                if param_type == "int" and not isinstance(param_value, int):
                    try:
                        parameters[param_name] = int(param_value)
                    except ValueError:
                        raise ValueError(f"Invalid integer value for {param_name}: {param_value}")
                
                # 옵션 검사
                if "options" in param_config and param_value not in param_config["options"]:
                    raise ValueError(f"Invalid option for {param_name}: {param_value}. "
                                   f"Available options: {param_config['options']}")
    
    def get_template_schema(self, template_name: str) -> Dict[str, Any]:
        """템플릿 스키마 조회 (프론트엔드 폼 생성용)"""
        template_data = self.get_template(template_name)
        if not template_data:
            raise ValueError(f"Template not found: {template_name}")
        
        return {
            "name": template_data.get("name"),
            "description": template_data.get("description"),
            "category": template_data.get("category"),
            "parameters": template_data.get("parameters", {}),
            "input_files": template_data.get("input_files", {}),
        }
