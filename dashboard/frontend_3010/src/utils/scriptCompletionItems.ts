/**
 * Script Completion Items Generator
 *
 * Generates dynamic autocomplete suggestions for Monaco Editor
 * based on Slurm configuration, file schema, and common patterns
 */

import { languages } from 'monaco-editor';
import type { SlurmConfig } from '../types/template';

export interface CompletionItem {
  label: string;
  kind: languages.CompletionItemKind;
  insertText: string;
  documentation?: string;
  detail?: string;
}

/**
 * Extended FileRequirement type with file_key
 * (Used in TemplateEditor - actual structure has file_key)
 */
export interface FileSchemaWithKey {
  name?: string;
  file_key: string;
  description: string;
  pattern?: string;
  type?: 'file' | 'directory';
  required?: boolean;
  max_size?: string;
}

/**
 * Slurm Environment Variables (Fixed List)
 */
export const SLURM_VARIABLES: CompletionItem[] = [
  {
    label: 'SLURM_JOB_ID',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_JOB_ID',
    documentation: 'The job ID assigned by Slurm',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_JOB_NAME',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_JOB_NAME',
    documentation: 'The name of the job',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_NTASKS',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_NTASKS',
    documentation: 'Total number of tasks in the job',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_NNODES',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_NNODES',
    documentation: 'Number of nodes allocated to the job',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_CPUS_PER_TASK',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_CPUS_PER_TASK',
    documentation: 'Number of CPUs per task',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_MEM_PER_NODE',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_MEM_PER_NODE',
    documentation: 'Memory per node in MB',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_SUBMIT_DIR',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_SUBMIT_DIR',
    documentation: 'Directory from which sbatch was invoked',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_ARRAY_TASK_ID',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_ARRAY_TASK_ID',
    documentation: 'Job array task ID',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_PROCID',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_PROCID',
    documentation: 'MPI rank (process ID)',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_LOCALID',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_LOCALID',
    documentation: 'Node local task ID',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_NODELIST',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_NODELIST',
    documentation: 'List of nodes allocated to the job',
    detail: 'Slurm variable',
  },
  {
    label: 'SLURM_TASKS_PER_NODE',
    kind: languages.CompletionItemKind.Variable,
    insertText: '$SLURM_TASKS_PER_NODE',
    documentation: 'Number of tasks per node',
    detail: 'Slurm variable',
  },
];

/**
 * Generate JOB_* Variables based on Slurm Config
 */
export function generateJobVariables(slurmConfig: SlurmConfig): CompletionItem[] {
  const items: CompletionItem[] = [];

  if (slurmConfig.partition) {
    items.push({
      label: 'JOB_PARTITION',
      kind: languages.CompletionItemKind.Variable,
      insertText: '$JOB_PARTITION',
      documentation: `Partition: ${slurmConfig.partition}`,
      detail: `Auto-injected from Slurm config`,
    });
  }

  if (slurmConfig.nodes) {
    items.push({
      label: 'JOB_NODES',
      kind: languages.CompletionItemKind.Variable,
      insertText: '$JOB_NODES',
      documentation: `Number of nodes: ${slurmConfig.nodes}`,
      detail: `Auto-injected from Slurm config`,
    });
  }

  if (slurmConfig.ntasks) {
    items.push({
      label: 'JOB_NTASKS',
      kind: languages.CompletionItemKind.Variable,
      insertText: '$JOB_NTASKS',
      documentation: `Number of tasks: ${slurmConfig.ntasks}`,
      detail: `Auto-injected from Slurm config`,
    });
  }

  if (slurmConfig.cpus_per_task) {
    items.push({
      label: 'JOB_CPUS_PER_TASK',
      kind: languages.CompletionItemKind.Variable,
      insertText: '$JOB_CPUS_PER_TASK',
      documentation: `CPUs per task: ${slurmConfig.cpus_per_task}`,
      detail: `Auto-injected from Slurm config`,
    });
  }

  if (slurmConfig.mem) {
    items.push({
      label: 'JOB_MEMORY',
      kind: languages.CompletionItemKind.Variable,
      insertText: '$JOB_MEMORY',
      documentation: `Memory: ${slurmConfig.mem}`,
      detail: `Auto-injected from Slurm config`,
    });
  }

  if (slurmConfig.time) {
    items.push({
      label: 'JOB_TIME_LIMIT',
      kind: languages.CompletionItemKind.Variable,
      insertText: '$JOB_TIME_LIMIT',
      documentation: `Time limit: ${slurmConfig.time}`,
      detail: `Auto-injected from Slurm config`,
    });
  }

  return items;
}

/**
 * Generate FILE_* Variables based on File Schema
 */
export function generateFileVariables(
  requiredFiles: FileSchemaWithKey[],
  optionalFiles: FileSchemaWithKey[]
): CompletionItem[] {
  const allFiles = [...requiredFiles, ...optionalFiles];

  return allFiles
    .filter((file) => file.file_key) // Only process files with file_key
    .map((file) => {
      const varName = `FILE_${file.file_key.toUpperCase()}`;
      return {
        label: varName,
        kind: languages.CompletionItemKind.Variable,
        insertText: `$${varName}`,
        documentation: `${file.description}\n\nPattern: ${file.pattern || '*'}\nType: ${file.type || 'file'}`,
        detail: file.required ? 'Required file' : 'Optional file',
      };
    });
}

/**
 * Apptainer Command Snippets
 */
export const APPTAINER_SNIPPETS: CompletionItem[] = [
  {
    label: 'apptainer exec',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'apptainer exec ${1:$APPTAINER_IMAGE} ${2:command}',
    documentation: 'Execute a command inside an Apptainer container',
    detail: 'Apptainer snippet',
  },
  {
    label: 'apptainer exec with binds',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'apptainer exec --bind ${1:/host/path}:${2:/container/path} ${3:$APPTAINER_IMAGE} ${4:command}',
    documentation: 'Execute with directory bindings',
    detail: 'Apptainer snippet',
  },
  {
    label: 'mpirun apptainer',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'mpirun -np ${1:$SLURM_NTASKS} apptainer exec ${2:$APPTAINER_IMAGE} ${3:command}',
    documentation: 'Run MPI job with Apptainer',
    detail: 'Apptainer snippet',
  },
  {
    label: 'apptainer exec with env',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'apptainer exec --env ${1:VAR_NAME}=${2:value} ${3:$APPTAINER_IMAGE} ${4:command}',
    documentation: 'Execute with environment variable',
    detail: 'Apptainer snippet',
  },
  {
    label: 'apptainer run',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'apptainer run ${1:$APPTAINER_IMAGE}',
    documentation: 'Run the default runscript of a container',
    detail: 'Apptainer snippet',
  },
];

/**
 * Common Bash Command Snippets
 */
export const BASH_SNIPPETS: CompletionItem[] = [
  {
    label: 'echo to stdout',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'echo "${1:message}"',
    documentation: 'Print message to stdout',
    detail: 'Bash snippet',
  },
  {
    label: 'check if file exists',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'if [ -f "${1:filename}" ]; then\n  ${2:# do something}\nfi',
    documentation: 'Check if file exists',
    detail: 'Bash snippet',
  },
  {
    label: 'for loop',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'for ${1:item} in ${2:list}; do\n  ${3:# do something}\ndone',
    documentation: 'For loop',
    detail: 'Bash snippet',
  },
  {
    label: 'export variable',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'export ${1:VAR_NAME}="${2:value}"',
    documentation: 'Export environment variable',
    detail: 'Bash snippet',
  },
  {
    label: 'mkdir -p',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'mkdir -p "${1:directory}"',
    documentation: 'Create directory (including parents)',
    detail: 'Bash snippet',
  },
  {
    label: 'cd to directory',
    kind: languages.CompletionItemKind.Snippet,
    insertText: 'cd "${1:directory}" || exit 1',
    documentation: 'Change directory with error handling',
    detail: 'Bash snippet',
  },
];

/**
 * Generate all completion items
 */
export function generateAllCompletionItems(
  slurmConfig: SlurmConfig,
  requiredFiles: FileSchemaWithKey[],
  optionalFiles: FileSchemaWithKey[]
): CompletionItem[] {
  return [
    ...SLURM_VARIABLES,
    ...generateJobVariables(slurmConfig),
    ...generateFileVariables(requiredFiles, optionalFiles),
    ...APPTAINER_SNIPPETS,
    ...BASH_SNIPPETS,
  ];
}

/**
 * Convert CompletionItem to Monaco CompletionItem
 */
export function toMonacoCompletionItem(
  item: CompletionItem,
  range: any
): languages.CompletionItem {
  return {
    label: item.label,
    kind: item.kind,
    insertText: item.insertText,
    documentation: item.documentation,
    detail: item.detail,
    range: range,
  };
}
