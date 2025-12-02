#!/usr/bin/env python3
"""
Template 검증 및 정규화 모듈

핵심 원칙:
- 기존 Template (image_name만 있음) 계속 지원
- 신규 Template (image_selection 있음) 지원
- 하위 호환성 보장
"""

import os
import json
import logging
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class TemplateValidator:
    """Template 유효성 검증 클래스"""

    def __init__(self):
        pass

    def validate_and_normalize(self, template: dict) -> Tuple[bool, dict, List[str]]:
        """
        Template 검증 및 정규화

        Args:
            template: Template YAML 데이터

        Returns:
            (is_valid, normalized_template, errors)
        """
        errors = []

        # 필수 필드 검증
        if 'template' not in template:
            errors.append("Missing 'template' section")
            return False, {}, errors

        if 'slurm' not in template:
            errors.append("Missing 'slurm' section")
            return False, {}, errors

        # Apptainer 설정 검증 및 정규화
        apptainer_valid, apptainer_normalized, apptainer_errors = self.validate_apptainer_config(template)
        if not apptainer_valid:
            errors.extend(apptainer_errors)
            return False, {}, errors

        # 정규화된 Template 생성
        normalized = template.copy()
        normalized['apptainer_normalized'] = apptainer_normalized

        return True, normalized, []

    def validate_apptainer_config(self, template: dict) -> Tuple[bool, dict, List[str]]:
        """
        Apptainer 설정 검증 및 정규화

        Returns:
            (is_valid, normalized_config, errors)
        """
        errors = []
        apptainer = template.get('apptainer', {})

        if not apptainer:
            errors.append("Missing 'apptainer' section")
            return False, {}, errors

        # 방식 1: 기존 방식 (image_name만 있음)
        if 'image_name' in apptainer and 'image_selection' not in apptainer:
            logger.info("Legacy template format detected (image_name only)")
            return True, {
                'mode': 'fixed',
                'image_name': apptainer['image_name'],
                'user_selectable': False,
                'bind': apptainer.get('bind', []),
                'env': apptainer.get('env', {})
            }, []

        # 방식 2: 신규 방식 (image_selection 있음)
        if 'image_selection' in apptainer:
            logger.info("New template format detected (image_selection)")
            selection = apptainer['image_selection']

            # 필수 필드 검증
            mode = selection.get('mode', 'partition')
            if mode not in ['partition', 'specific', 'any']:
                errors.append(f"Invalid image_selection.mode: {mode}")
                return False, {}, errors

            # mode별 검증
            if mode == 'partition':
                partition = selection.get('partition')
                if not partition:
                    errors.append("image_selection.partition required for mode='partition'")
                    return False, {}, errors

                if partition not in ['compute', 'viz', 'shared', 'normal']:
                    errors.append(f"Invalid partition: {partition}")
                    return False, {}, errors

            elif mode == 'specific':
                allowed = selection.get('allowed_images', [])
                if not allowed:
                    errors.append("image_selection.allowed_images required for mode='specific'")
                    return False, {}, errors

            return True, {
                'mode': mode,
                'partition': selection.get('partition'),
                'allowed_images': selection.get('allowed_images', []),
                'default_image': selection.get('default_image'),
                'required': selection.get('required', True),
                'user_selectable': True,
                'bind': apptainer.get('bind', []),
                'env': apptainer.get('env', {})
            }, []

        # 두 가지 다 없음
        errors.append("Apptainer config must have 'image_name' or 'image_selection'")
        return False, {}, errors

    def validate_file_schema(self, template: dict, uploaded_files: dict) -> List[str]:
        """
        업로드된 파일이 스키마를 만족하는지 검증

        Args:
            template: Template 데이터
            uploaded_files: {
                'geometry': {'path': '...', 'filename': '...', 'size': 12345},
                'config': {'path': '...', 'filename': '...', 'size': 678}
            }

        Returns:
            List of error messages
        """
        errors = []
        schema = template.get('files', {}).get('input_schema', {})

        # 필수 파일 체크
        for required_file in schema.get('required', []):
            file_key = required_file['file_key']

            # 파일 존재 확인
            if file_key not in uploaded_files:
                errors.append(f"Required file missing: {required_file['name']} ({file_key})")
                continue

            uploaded = uploaded_files[file_key]

            # 파일 크기 검증
            max_size_str = required_file.get('max_size', '1GB')
            max_size = self._parse_size(max_size_str)

            if uploaded['size'] > max_size:
                errors.append(
                    f"File too large: {required_file['name']} "
                    f"({uploaded['size']} bytes > {max_size} bytes)"
                )

            # 확장자 검증
            validation = required_file.get('validation', {})
            if 'extensions' in validation:
                filename = uploaded['filename']
                ext = os.path.splitext(filename)[1].lower()
                allowed_exts = [e.lower() for e in validation['extensions']]

                if ext not in allowed_exts:
                    errors.append(
                        f"Invalid file extension for {required_file['name']}: "
                        f"{ext} (allowed: {', '.join(validation['extensions'])})"
                    )

            # JSON 스키마 검증 (config 파일인 경우)
            if 'schema' in validation:
                try:
                    with open(uploaded['path'], 'r') as f:
                        data = json.load(f)

                    schema_errors = self._validate_json_schema(data, validation['schema'])
                    if schema_errors:
                        errors.extend([f"{required_file['name']}: {err}" for err in schema_errors])

                except json.JSONDecodeError as e:
                    errors.append(f"{required_file['name']} is not valid JSON: {str(e)}")
                except Exception as e:
                    errors.append(f"Failed to validate {required_file['name']}: {str(e)}")

        return errors

    def _parse_size(self, size_str: str) -> int:
        """
        파일 크기 문자열을 바이트로 변환

        Examples:
            "1KB" -> 1024
            "500MB" -> 524288000
            "1GB" -> 1073741824
        """
        size_str = size_str.upper().strip()

        units = {
            'B': 1,
            'KB': 1024,
            'MB': 1024 * 1024,
            'GB': 1024 * 1024 * 1024,
            'TB': 1024 * 1024 * 1024 * 1024
        }

        for unit, multiplier in units.items():
            if size_str.endswith(unit):
                try:
                    value = float(size_str[:-len(unit)])
                    return int(value * multiplier)
                except ValueError:
                    pass

        # 단위 없으면 바이트로 간주
        try:
            return int(size_str)
        except ValueError:
            return 1024 * 1024 * 1024  # 기본값 1GB

    def _validate_json_schema(self, data: dict, schema: dict) -> List[str]:
        """
        간단한 JSON 스키마 검증

        Args:
            data: 검증할 데이터
            schema: 스키마 정의

        Returns:
            List of error messages
        """
        errors = []

        # type 검증
        expected_type = schema.get('type')
        if expected_type == 'object' and not isinstance(data, dict):
            errors.append(f"Expected object, got {type(data).__name__}")
            return errors

        # required 필드 검증
        required_fields = schema.get('required', [])
        for field in required_fields:
            if field not in data:
                errors.append(f"Required field missing: {field}")

        # properties 검증
        properties = schema.get('properties', {})
        for field, prop_schema in properties.items():
            if field not in data:
                continue

            value = data[field]
            prop_type = prop_schema.get('type')

            # 타입 검증
            if prop_type == 'number':
                if not isinstance(value, (int, float)):
                    errors.append(f"{field}: expected number, got {type(value).__name__}")
                    continue

                # minimum/maximum 검증
                if 'minimum' in prop_schema and value < prop_schema['minimum']:
                    errors.append(f"{field}: {value} < minimum {prop_schema['minimum']}")

                if 'maximum' in prop_schema and value > prop_schema['maximum']:
                    errors.append(f"{field}: {value} > maximum {prop_schema['maximum']}")

            elif prop_type == 'string':
                if not isinstance(value, str):
                    errors.append(f"{field}: expected string, got {type(value).__name__}")

        return errors


# 사용 예시
if __name__ == "__main__":
    import yaml

    # 기존 Template 테스트
    legacy_template = {
        'template': {'id': 'test'},
        'slurm': {'partition': 'compute'},
        'apptainer': {
            'image_name': 'KooSimulationPython313.sif',
            'bind': ['/shared:/shared']
        }
    }

    # 신규 Template 테스트
    new_template = {
        'template': {'id': 'test2'},
        'slurm': {'partition': 'compute'},
        'apptainer': {
            'image_selection': {
                'mode': 'partition',
                'partition': 'compute',
                'default_image': 'KooSimulationPython313.sif'
            },
            'bind': ['/shared:/shared']
        }
    }

    validator = TemplateValidator()

    print("=== Legacy Template ===")
    valid, normalized, errors = validator.validate_and_normalize(legacy_template)
    print(f"Valid: {valid}")
    print(f"Normalized: {json.dumps(normalized['apptainer_normalized'], indent=2)}")
    print(f"Errors: {errors}")

    print("\n=== New Template ===")
    valid, normalized, errors = validator.validate_and_normalize(new_template)
    print(f"Valid: {valid}")
    print(f"Normalized: {json.dumps(normalized['apptainer_normalized'], indent=2)}")
    print(f"Errors: {errors}")
