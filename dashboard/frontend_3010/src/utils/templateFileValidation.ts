/**
 * Template File Validation
 * 템플릿이 요구하는 파일 스키마와 실제 업로드된 파일을 검증
 */

import { ClassifiedFiles } from '../types/upload';

export interface FileSchema {
  type: 'data' | 'config' | 'script' | 'model' | 'mesh' | 'result' | 'document';
  required: boolean;
  description?: string;
  examples?: string[];
  extensions?: string[];
  minCount?: number;
  maxCount?: number;
}

export interface TemplateFileSchema {
  [key: string]: FileSchema;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  missingRequired: string[];
  suggestions: string[];
}

/**
 * 템플릿 파일 스키마 검증
 */
export const validateFilesAgainstTemplate = (
  classifiedFiles: ClassifiedFiles,
  templateSchema: TemplateFileSchema
): ValidationResult => {
  const errors: string[] = [];
  const warnings: string[] = [];
  const missingRequired: string[] = [];
  const suggestions: string[] = [];

  // 템플릿 스키마가 없으면 검증 통과
  if (!templateSchema || Object.keys(templateSchema).length === 0) {
    return {
      valid: true,
      errors,
      warnings,
      missingRequired,
      suggestions
    };
  }

  // 각 파일 타입 요구사항 검증
  Object.entries(templateSchema).forEach(([typeName, schema]) => {
    const files = classifiedFiles[schema.type as keyof ClassifiedFiles] || [];
    const fileCount = files.length;

    // 필수 파일 확인
    if (schema.required && fileCount === 0) {
      missingRequired.push(typeName);
      errors.push(`필수 파일 누락: ${typeName} (${schema.type})`);

      if (schema.examples && schema.examples.length > 0) {
        suggestions.push(`${typeName}: ${schema.examples.join(', ')}`);
      }
    }

    // 최소 파일 수 확인
    if (schema.minCount && fileCount < schema.minCount) {
      errors.push(
        `${typeName}: 최소 ${schema.minCount}개 필요 (현재 ${fileCount}개)`
      );
    }

    // 최대 파일 수 확인
    if (schema.maxCount && fileCount > schema.maxCount) {
      warnings.push(
        `${typeName}: 최대 ${schema.maxCount}개 권장 (현재 ${fileCount}개)`
      );
    }

    // 파일 확장자 확인
    if (schema.extensions && schema.extensions.length > 0 && fileCount > 0) {
      files.forEach(file => {
        const ext = file.name.split('.').pop()?.toLowerCase();
        if (ext && !schema.extensions!.includes(`.${ext}`)) {
          warnings.push(
            `${file.name}: 권장 확장자가 아닙니다 (${schema.extensions.join(', ')})`
          );
        }
      });
    }
  });

  return {
    valid: errors.length === 0,
    errors,
    warnings,
    missingRequired,
    suggestions
  };
};

/**
 * 템플릿에서 허용된 파일 타입 목록 추출
 */
export const getAllowedFileTypes = (
  templateSchema: TemplateFileSchema
): string[] => {
  const types = new Set<string>();

  Object.values(templateSchema).forEach(schema => {
    if (schema.extensions) {
      schema.extensions.forEach(ext => types.add(ext));
    }
  });

  return Array.from(types);
};

/**
 * 템플릿 파일 요구사항 요약
 */
export const getTemplateRequirementsSummary = (
  templateSchema: TemplateFileSchema
): string => {
  if (!templateSchema || Object.keys(templateSchema).length === 0) {
    return '파일 요구사항 없음';
  }

  const required = Object.entries(templateSchema)
    .filter(([_, schema]) => schema.required)
    .map(([name, schema]) => `${name} (${schema.type})`)
    .join(', ');

  const optional = Object.entries(templateSchema)
    .filter(([_, schema]) => !schema.required)
    .map(([name, schema]) => `${name} (${schema.type})`)
    .join(', ');

  let summary = '';

  if (required) {
    summary += `필수: ${required}`;
  }

  if (optional) {
    if (summary) summary += ' | ';
    summary += `선택: ${optional}`;
  }

  return summary || '파일 요구사항 없음';
};

/**
 * 예제 템플릿 스키마 (PyTorch Training)
 */
export const EXAMPLE_PYTORCH_SCHEMA: TemplateFileSchema = {
  'Training Data': {
    type: 'data',
    required: true,
    description: '학습 데이터셋',
    examples: ['train.tar.gz', 'dataset.zip'],
    extensions: ['.tar.gz', '.zip', '.hdf5'],
    minCount: 1,
    maxCount: 1
  },
  'Config File': {
    type: 'config',
    required: true,
    description: '학습 설정 파일',
    examples: ['config.yaml', 'hyperparams.json'],
    extensions: ['.yaml', '.yml', '.json'],
    minCount: 1,
    maxCount: 1
  },
  'Training Script': {
    type: 'script',
    required: false,
    description: '커스텀 학습 스크립트 (선택)',
    examples: ['train.py'],
    extensions: ['.py']
  },
  'Pre-trained Model': {
    type: 'model',
    required: false,
    description: '사전 학습된 모델 (선택)',
    examples: ['pretrained.pth'],
    extensions: ['.pth', '.pt', '.ckpt']
  }
};

/**
 * 예제 템플릿 스키마 (OpenFOAM CFD)
 */
export const EXAMPLE_OPENFOAM_SCHEMA: TemplateFileSchema = {
  'Mesh File': {
    type: 'mesh',
    required: true,
    description: '메쉬 파일',
    examples: ['mesh.msh', 'geometry.stl'],
    extensions: ['.msh', '.stl', '.obj'],
    minCount: 1
  },
  'Case Configuration': {
    type: 'config',
    required: true,
    description: 'OpenFOAM 케이스 설정',
    examples: ['controlDict', 'fvSchemes'],
    minCount: 1
  },
  'Boundary Conditions': {
    type: 'config',
    required: true,
    description: '경계 조건 파일',
    examples: ['boundary', '0/U', '0/p'],
    minCount: 1
  },
  'Solver Script': {
    type: 'script',
    required: false,
    description: '커스텀 솔버 스크립트',
    examples: ['run.sh'],
    extensions: ['.sh']
  }
};
