/**
 * Template Engine for Command Template System
 *
 * Provides variable substitution and script generation functionality
 * for Apptainer command templates.
 *
 * Features:
 * - Variable substitution with ${VAR} syntax
 * - Transform functions (memory_to_kb, basename, dirname, time_to_seconds)
 * - Dynamic variable resolution from Slurm job config
 * - Script generation with pre/post commands
 */
import { CommandTemplate } from '../types/apptainer';
/**
 * Convert memory string to kilobytes
 * Examples: "16G" → 16777216, "512M" → 524288, "1024K" → 1024
 */
export declare function memory_to_kb(memoryStr: string): number;
/**
 * Convert time string to seconds
 * Formats: "HH:MM:SS", "MM:SS", "DD-HH:MM:SS"
 * Examples: "1:30:00" → 5400, "2-12:00:00" → 216000
 */
export declare function time_to_seconds(timeStr: string): number;
/**
 * Extract filename from path
 * Example: "/path/to/file.k" → "file.k"
 */
export declare function basename(path: string): string;
/**
 * Extract directory from path
 * Example: "/path/to/file.k" → "/path/to"
 */
export declare function dirname(path: string): string;
/**
 * Extract filename without extension
 * Example: "file.txt" → "file"
 */
export declare function filename_without_ext(path: string): string;
/**
 * Get file extension
 * Example: "file.txt" → "txt"
 */
export declare function file_extension(path: string): string;
interface SlurmJobConfig {
    partition?: string;
    nodes?: number;
    ntasks?: number;
    'ntasks-per-node'?: number;
    cpus?: number;
    'cpus-per-task'?: number;
    mem?: string;
    'mem-per-cpu'?: string;
    time?: string;
    qos?: string;
    [key: string]: any;
}
interface TemplateContext {
    slurmConfig: SlurmJobConfig;
    inputFiles: Record<string, string>;
    apptainerImage: string;
    customValues?: Record<string, string>;
}
/**
 * Generate Slurm script from command template
 */
export declare function generateScript(template: CommandTemplate, context: TemplateContext): string;
/**
 * Validate that all required variables can be resolved
 */
export declare function validateTemplate(template: CommandTemplate, context: TemplateContext): {
    valid: boolean;
    errors: string[];
};
/**
 * Get required input files for a template
 */
export declare function getRequiredInputFiles(template: CommandTemplate): string[];
/**
 * Get required Slurm config fields for a template
 */
export declare function getRequiredSlurmFields(template: CommandTemplate): string[];
declare const _default: {
    generateScript: typeof generateScript;
    validateTemplate: typeof validateTemplate;
    getRequiredInputFiles: typeof getRequiredInputFiles;
    getRequiredSlurmFields: typeof getRequiredSlurmFields;
    transforms: Record<string, (value: any) => any>;
};
export default _default;
