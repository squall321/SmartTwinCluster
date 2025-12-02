/**
 * Variable Resolver for Command Templates
 *
 * CommandTemplate의 변수들을 실제 값으로 해석하는 유틸리티
 */

import { CommandTemplate, DynamicVariable } from '../types/apptainer';
import { applyTransform } from './transformFunctions';

/**
 * Slurm 설정 인터페이스
 */
export interface SlurmConfig {
  partition: string;
  nodes: number;
  ntasks: number;
  cpus_per_task: number;
  mem: string;
  time: string;
  gpu?: number;
}

/**
 * 업로드된 파일 매핑
 * file_key -> 파일 경로
 */
export type UploadedFiles = Record<string, string | string[]>;

/**
 * 해석된 변수 매핑
 */
export type ResolvedVariables = Record<string, any>;

/**
 * Source path에서 값 추출
 * @example resolveSourcePath("slurm.ntasks", slurmConfig) -> 4
 */
export function resolveSourcePath(sourcePath: string, slurmConfig: SlurmConfig): any {
  const parts = sourcePath.split('.');

  if (parts[0] === 'slurm') {
    // slurm.ntasks, slurm.mem, slurm.time 등
    const field = parts[1];
    const value = (slurmConfig as any)[field];

    if (value === undefined) {
      throw new Error(`Slurm field not found: ${field}`);
    }

    return value;
  }

  throw new Error(`Unsupported source type: ${parts[0]}`);
}

/**
 * Dynamic Variable을 실제 값으로 해석
 */
export function resolveDynamicVariable(
  varName: string,
  varDef: DynamicVariable,
  slurmConfig: SlurmConfig
): any {
  // 1. Source에서 값 추출
  const sourceValue = resolveSourcePath(varDef.source, slurmConfig);

  // 2. Transform 함수 적용
  const transformedValue = applyTransform(varDef.transform, sourceValue);

  return transformedValue;
}

/**
 * 모든 Dynamic Variables 해석
 */
export function resolveDynamicVariables(
  template: CommandTemplate,
  slurmConfig: SlurmConfig
): ResolvedVariables {
  const resolved: ResolvedVariables = {};

  for (const [varName, varDef] of Object.entries(template.variables.dynamic)) {
    try {
      resolved[varName] = resolveDynamicVariable(varName, varDef, slurmConfig);
    } catch (error) {
      if (varDef.required) {
        throw error;
      }
      // Optional variable이면 에러 무시
      console.warn(`Failed to resolve optional dynamic variable ${varName}:`, error);
    }
  }

  return resolved;
}

/**
 * Input File Variables를 FILE_* 환경변수로 매핑
 *
 * @example
 * Input: { python_script: "/path/to/script.py" }
 * Output: { FILE_PYTHON_SCRIPT: "/path/to/script.py" }
 */
export function resolveInputFileVariables(
  template: CommandTemplate,
  uploadedFiles: UploadedFiles
): ResolvedVariables {
  const resolved: ResolvedVariables = {};

  for (const [varName, varDef] of Object.entries(template.variables.input_files)) {
    const fileKey = varDef.file_key;
    const uploadedFile = uploadedFiles[fileKey];

    // 필수 파일 체크
    if (varDef.required && !uploadedFile) {
      throw new Error(`Required file not uploaded: ${varDef.description} (${fileKey})`);
    }

    if (uploadedFile) {
      // FILE_KEY를 대문자로 변환
      const envVarName = `FILE_${fileKey.toUpperCase()}`;

      if (Array.isArray(uploadedFile)) {
        // 복수 파일: 공백으로 구분된 문자열
        resolved[envVarName] = uploadedFile.join(' ');
        resolved[`${envVarName}_COUNT`] = uploadedFile.length;
      } else {
        // 단일 파일
        resolved[envVarName] = uploadedFile;
      }
    }
  }

  return resolved;
}

/**
 * 모든 변수를 하나의 매핑으로 통합
 */
export function resolveAllVariables(
  template: CommandTemplate,
  slurmConfig: SlurmConfig,
  uploadedFiles: UploadedFiles
): ResolvedVariables {
  const dynamicVars = resolveDynamicVariables(template, slurmConfig);
  const fileVars = resolveInputFileVariables(template, uploadedFiles);

  return {
    ...dynamicVars,
    ...fileVars,
  };
}

/**
 * 문자열 템플릿에서 변수 치환
 * @example substituteVariables("python3 ${SCRIPT_FILE}", { SCRIPT_FILE: "sim.py" }) -> "python3 sim.py"
 */
export function substituteVariables(template: string, variables: ResolvedVariables): string {
  let result = template;

  // ${VAR_NAME} 형식의 변수 치환
  for (const [varName, value] of Object.entries(variables)) {
    const regex = new RegExp(`\\$\\{${varName}\\}`, 'g');
    result = result.replace(regex, String(value));
  }

  // $VAR_NAME 형식의 변수도 치환 (쉘 스타일)
  for (const [varName, value] of Object.entries(variables)) {
    const regex = new RegExp(`\\$${varName}\\b`, 'g');
    result = result.replace(regex, String(value));
  }

  return result;
}

/**
 * Command format 문자열 생성
 */
export function generateCommandFromTemplate(
  template: CommandTemplate,
  slurmConfig: SlurmConfig,
  uploadedFiles: UploadedFiles,
  apptainerImagePath: string
): string {
  // 1. 모든 변수 해석
  const variables = resolveAllVariables(template, slurmConfig, uploadedFiles);

  // 2. APPTAINER_IMAGE 변수 추가
  const allVariables = {
    ...variables,
    APPTAINER_IMAGE: apptainerImagePath,
  };

  // 3. Command format에 변수 치환
  const command = substituteVariables(template.command.format, allVariables);

  return command;
}

/**
 * 검증: 필수 변수가 모두 해석되었는지 확인
 */
export function validateResolvedVariables(
  template: CommandTemplate,
  variables: ResolvedVariables
): { valid: boolean; missingVars: string[] } {
  const missingVars: string[] = [];

  // Dynamic variables 체크
  for (const [varName, varDef] of Object.entries(template.variables.dynamic)) {
    if (varDef.required && variables[varName] === undefined) {
      missingVars.push(varName);
    }
  }

  // Input file variables 체크
  for (const [varName, varDef] of Object.entries(template.variables.input_files)) {
    if (varDef.required) {
      const envVarName = `FILE_${varDef.file_key.toUpperCase()}`;
      if (variables[envVarName] === undefined) {
        missingVars.push(varName);
      }
    }
  }

  return {
    valid: missingVars.length === 0,
    missingVars,
  };
}

/**
 * 변수 미리보기 생성 (UI 표시용)
 */
export interface VariablePreview {
  name: string;
  value: any;
  source?: string;
  transform?: string;
  type: 'dynamic' | 'file' | 'system';
}

export function generateVariablePreview(
  template: CommandTemplate,
  slurmConfig: SlurmConfig,
  uploadedFiles: UploadedFiles
): VariablePreview[] {
  const preview: VariablePreview[] = [];

  // Dynamic variables
  for (const [varName, varDef] of Object.entries(template.variables.dynamic)) {
    try {
      const value = resolveDynamicVariable(varName, varDef, slurmConfig);
      preview.push({
        name: varName,
        value,
        source: varDef.source,
        transform: varDef.transform,
        type: 'dynamic',
      });
    } catch (error) {
      preview.push({
        name: varName,
        value: `Error: ${error}`,
        source: varDef.source,
        transform: varDef.transform,
        type: 'dynamic',
      });
    }
  }

  // File variables
  for (const [varName, varDef] of Object.entries(template.variables.input_files)) {
    const envVarName = `FILE_${varDef.file_key.toUpperCase()}`;
    const uploadedFile = uploadedFiles[varDef.file_key];

    preview.push({
      name: envVarName,
      value: uploadedFile || '(not uploaded)',
      type: 'file',
    });

    if (Array.isArray(uploadedFile) && uploadedFile.length > 1) {
      preview.push({
        name: `${envVarName}_COUNT`,
        value: uploadedFile.length,
        type: 'file',
      });
    }
  }

  return preview;
}
