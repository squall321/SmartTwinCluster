/**
 * Command Template Generator
 *
 * CommandTemplate을 기반으로 완전한 Slurm 스크립트를 생성
 */

import { CommandTemplate } from '../types/apptainer';
import {
  SlurmConfig,
  UploadedFiles,
  generateCommandFromTemplate,
  resolveAllVariables,
  substituteVariables,
} from './variableResolver';

/**
 * 스크립트 생성 옵션
 */
export interface ScriptGenerationOptions {
  template: CommandTemplate;
  slurmConfig: SlurmConfig;
  uploadedFiles: UploadedFiles;
  apptainerImagePath: string;
  jobName?: string;
  workDir?: string;
  outputFile?: string;
  errorFile?: string;
}

/**
 * 생성된 스크립트 결과
 */
export interface GeneratedScript {
  fullScript: string;
  sections: {
    slurmDirectives: string;
    preCommands: string;
    mainCommand: string;
    postCommands: string;
  };
  variables: Record<string, any>;
}

/**
 * Slurm directive 생성
 */
function generateSlurmDirectives(
  slurmConfig: SlurmConfig,
  options: ScriptGenerationOptions
): string {
  const lines: string[] = [];

  lines.push('#!/bin/bash');
  lines.push('');
  lines.push(`#SBATCH --job-name=${options.jobName || 'job'}`);
  lines.push(`#SBATCH --partition=${slurmConfig.partition}`);
  lines.push(`#SBATCH --nodes=${slurmConfig.nodes}`);
  lines.push(`#SBATCH --ntasks=${slurmConfig.ntasks}`);
  lines.push(`#SBATCH --cpus-per-task=${slurmConfig.cpus_per_task}`);
  lines.push(`#SBATCH --mem=${slurmConfig.mem}`);
  lines.push(`#SBATCH --time=${slurmConfig.time}`);

  if (slurmConfig.gpu && slurmConfig.gpu > 0) {
    lines.push(`#SBATCH --gres=gpu:${slurmConfig.gpu}`);
  }

  if (options.outputFile) {
    lines.push(`#SBATCH --output=${options.outputFile}`);
  } else {
    lines.push('#SBATCH --output=%x_%j.out');
  }

  if (options.errorFile) {
    lines.push(`#SBATCH --error=${options.errorFile}`);
  } else {
    lines.push('#SBATCH --error=%x_%j.err');
  }

  lines.push('');

  return lines.join('\n');
}

/**
 * 환경 변수 export 문 생성
 */
function generateEnvironmentVariables(variables: Record<string, any>): string {
  const lines: string[] = [];

  lines.push('# Environment Variables');

  // FILE_* 변수 먼저 export
  const fileVars = Object.entries(variables).filter(([name]) => name.startsWith('FILE_'));
  if (fileVars.length > 0) {
    lines.push('# Uploaded Files');
    for (const [name, value] of fileVars) {
      if (typeof value === 'string') {
        lines.push(`export ${name}="${value}"`);
      } else {
        lines.push(`export ${name}=${value}`);
      }
    }
    lines.push('');
  }

  // 기타 변수들
  const otherVars = Object.entries(variables).filter(([name]) => !name.startsWith('FILE_'));
  if (otherVars.length > 0) {
    lines.push('# Dynamic Variables');
    for (const [name, value] of otherVars) {
      if (typeof value === 'string') {
        lines.push(`export ${name}="${value}"`);
      } else {
        lines.push(`export ${name}=${value}`);
      }
    }
    lines.push('');
  }

  return lines.join('\n');
}

/**
 * Pre-commands 섹션 생성
 */
function generatePreCommands(
  template: CommandTemplate,
  variables: Record<string, any>
): string {
  if (template.pre_commands.length === 0) {
    return '';
  }

  const lines: string[] = [];
  lines.push('# Pre-execution Commands');

  for (const cmd of template.pre_commands) {
    const substituted = substituteVariables(cmd, variables);
    lines.push(substituted);
  }

  lines.push('');

  return lines.join('\n');
}

/**
 * Main command 섹션 생성
 */
function generateMainCommand(
  template: CommandTemplate,
  slurmConfig: SlurmConfig,
  uploadedFiles: UploadedFiles,
  apptainerImagePath: string
): string {
  const lines: string[] = [];

  lines.push('# Main Execution');

  // MPI 사용 여부에 따라 명령어 접두사 추가
  let commandPrefix = '';
  if (template.command.requires_mpi && slurmConfig.ntasks > 1) {
    commandPrefix = `mpirun -np ${slurmConfig.ntasks} `;
  }

  const command = generateCommandFromTemplate(
    template,
    slurmConfig,
    uploadedFiles,
    apptainerImagePath
  );

  lines.push(commandPrefix + command);
  lines.push('');

  return lines.join('\n');
}

/**
 * Post-commands 섹션 생성
 */
function generatePostCommands(
  template: CommandTemplate,
  variables: Record<string, any>
): string {
  if (template.post_commands.length === 0) {
    return '';
  }

  const lines: string[] = [];
  lines.push('# Post-execution Commands');

  for (const cmd of template.post_commands) {
    const substituted = substituteVariables(cmd, variables);
    lines.push(substituted);
  }

  lines.push('');

  return lines.join('\n');
}

/**
 * 완전한 Slurm 스크립트 생성
 */
export function generateSlurmScript(options: ScriptGenerationOptions): GeneratedScript {
  const { template, slurmConfig, uploadedFiles, apptainerImagePath } = options;

  // 1. 모든 변수 해석
  const variables = resolveAllVariables(template, slurmConfig, uploadedFiles);

  // APPTAINER_IMAGE 변수 추가
  const allVariables = {
    ...variables,
    APPTAINER_IMAGE: apptainerImagePath,
  };

  // 2. 각 섹션 생성
  const slurmDirectives = generateSlurmDirectives(slurmConfig, options);
  const envVars = generateEnvironmentVariables(allVariables);
  const preCommands = generatePreCommands(template, allVariables);
  const mainCommand = generateMainCommand(template, slurmConfig, uploadedFiles, apptainerImagePath);
  const postCommands = generatePostCommands(template, allVariables);

  // 3. 전체 스크립트 조합
  const sections = {
    slurmDirectives,
    preCommands,
    mainCommand,
    postCommands,
  };

  const fullScript = [
    slurmDirectives,
    envVars,
    preCommands,
    mainCommand,
    postCommands,
    '# Job completed',
    `echo "Job completed at $(date)"`,
  ].join('\n');

  return {
    fullScript,
    sections,
    variables: allVariables,
  };
}

/**
 * 스크립트를 main_exec 형식으로 생성 (Template Editor용)
 *
 * TemplateEditor의 main_exec 필드에 삽입할 스크립트 생성
 */
export function generateMainExecScript(
  template: CommandTemplate,
  apptainerImagePath: string
): string {
  const lines: string[] = [];

  lines.push('#!/bin/bash');
  lines.push('# =============================================================================');
  lines.push(`# ${template.display_name}`);
  lines.push(`# ${template.description}`);
  lines.push('# =============================================================================');
  lines.push('');

  // Pre-commands
  if (template.pre_commands.length > 0) {
    lines.push('# --- Pre-execution Setup ---');
    for (const cmd of template.pre_commands) {
      lines.push(cmd);
    }
    lines.push('');
  }

  // Main command (템플릿 형식 그대로)
  lines.push('# --- Main Execution ---');
  lines.push('# Command Template:');
  lines.push(`# ${template.command.format}`);
  lines.push('');

  if (template.command.requires_mpi) {
    lines.push('# MPI execution');
    lines.push(`mpirun -np $JOB_NTASKS ${template.command.format}`);
  } else {
    lines.push(template.command.format);
  }
  lines.push('');

  // Post-commands
  if (template.post_commands.length > 0) {
    lines.push('# --- Post-execution Cleanup ---');
    for (const cmd of template.post_commands) {
      lines.push(cmd);
    }
    lines.push('');
  }

  return lines.join('\n');
}

/**
 * 스크립트 미리보기 생성 (UI 표시용)
 */
export interface ScriptPreview {
  valid: boolean;
  errors: string[];
  warnings: string[];
  script: string;
  estimatedRuntime?: string;
  resourceSummary: {
    cores: number;
    memory: string;
    time: string;
    nodes: number;
  };
}

export function generateScriptPreview(options: ScriptGenerationOptions): ScriptPreview {
  const errors: string[] = [];
  const warnings: string[] = [];

  try {
    // 필수 파일 체크
    for (const [varName, varDef] of Object.entries(options.template.variables.input_files)) {
      if (varDef.required && !options.uploadedFiles[varDef.file_key]) {
        errors.push(`Required file missing: ${varDef.description}`);
      }
    }

    // 스크립트 생성
    const generated = generateSlurmScript(options);

    // Resource summary
    const resourceSummary = {
      cores: options.slurmConfig.nodes * options.slurmConfig.ntasks,
      memory: options.slurmConfig.mem,
      time: options.slurmConfig.time,
      nodes: options.slurmConfig.nodes,
    };

    // Warnings
    if (options.slurmConfig.nodes > 1 && !options.template.command.requires_mpi) {
      warnings.push('Multi-node job without MPI: resources may be underutilized');
    }

    return {
      valid: errors.length === 0,
      errors,
      warnings,
      script: generated.fullScript,
      resourceSummary,
    };
  } catch (error: any) {
    errors.push(`Script generation failed: ${error.message}`);

    return {
      valid: false,
      errors,
      warnings,
      script: '',
      resourceSummary: {
        cores: 0,
        memory: '0',
        time: '00:00:00',
        nodes: 0,
      },
    };
  }
}
