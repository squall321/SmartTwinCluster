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
// ============================================
// Transform Functions
// ============================================
/**
 * Convert memory string to kilobytes
 * Examples: "16G" → 16777216, "512M" → 524288, "1024K" → 1024
 */
export function memory_to_kb(memoryStr) {
    const match = memoryStr.match(/^(\d+(?:\.\d+)?)\s*([KMGT])?B?$/i);
    if (!match) {
        throw new Error(`Invalid memory format: ${memoryStr}`);
    }
    const value = parseFloat(match[1]);
    const unit = (match[2] || 'K').toUpperCase();
    const multipliers = {
        K: 1,
        M: 1024,
        G: 1024 * 1024,
        T: 1024 * 1024 * 1024,
    };
    return Math.floor(value * multipliers[unit]);
}
/**
 * Convert time string to seconds
 * Formats: "HH:MM:SS", "MM:SS", "DD-HH:MM:SS"
 * Examples: "1:30:00" → 5400, "2-12:00:00" → 216000
 */
export function time_to_seconds(timeStr) {
    // Format: DD-HH:MM:SS
    const dayMatch = timeStr.match(/^(\d+)-(\d+):(\d+):(\d+)$/);
    if (dayMatch) {
        const [, days, hours, minutes, seconds] = dayMatch;
        return (parseInt(days) * 86400 +
            parseInt(hours) * 3600 +
            parseInt(minutes) * 60 +
            parseInt(seconds));
    }
    // Format: HH:MM:SS or MM:SS
    const parts = timeStr.split(':').map((p) => parseInt(p));
    if (parts.length === 3) {
        // HH:MM:SS
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    else if (parts.length === 2) {
        // MM:SS
        return parts[0] * 60 + parts[1];
    }
    else if (parts.length === 1) {
        // SS
        return parts[0];
    }
    throw new Error(`Invalid time format: ${timeStr}`);
}
/**
 * Extract filename from path
 * Example: "/path/to/file.k" → "file.k"
 */
export function basename(path) {
    return path.split('/').pop() || path;
}
/**
 * Extract directory from path
 * Example: "/path/to/file.k" → "/path/to"
 */
export function dirname(path) {
    const parts = path.split('/');
    parts.pop();
    return parts.join('/') || '/';
}
/**
 * Extract filename without extension
 * Example: "file.txt" → "file"
 */
export function filename_without_ext(path) {
    const base = basename(path);
    const dotIndex = base.lastIndexOf('.');
    return dotIndex > 0 ? base.substring(0, dotIndex) : base;
}
/**
 * Get file extension
 * Example: "file.txt" → "txt"
 */
export function file_extension(path) {
    const base = basename(path);
    const dotIndex = base.lastIndexOf('.');
    return dotIndex > 0 ? base.substring(dotIndex + 1) : '';
}
// Registry of transform functions
const TRANSFORM_FUNCTIONS = {
    memory_to_kb,
    time_to_seconds,
    basename,
    dirname,
    filename_without_ext,
    file_extension,
};
/**
 * Apply transform function to a value
 */
function applyTransform(value, transformName) {
    const transformFn = TRANSFORM_FUNCTIONS[transformName];
    if (!transformFn) {
        throw new Error(`Unknown transform function: ${transformName}`);
    }
    return transformFn(value);
}
/**
 * Resolve dynamic variable from Slurm config
 * Source format: "slurm.ntasks" → slurmConfig.ntasks
 */
function resolveDynamicVariable(source, transform, context) {
    // Parse source (e.g., "slurm.ntasks")
    if (!source.startsWith('slurm.')) {
        throw new Error(`Invalid variable source: ${source}. Must start with "slurm."`);
    }
    const field = source.substring(6); // Remove "slurm." prefix
    let value = context.slurmConfig[field];
    if (value === undefined) {
        throw new Error(`Slurm config field not found: ${field}`);
    }
    // Apply transform if specified
    if (transform) {
        value = applyTransform(value, transform);
    }
    return value;
}
/**
 * Resolve computed variable
 * Example: computed var "K_FILE_BASENAME" with source "K_FILE" and transform "basename"
 */
function resolveComputedVariable(source, transform, variableMap) {
    const sourceValue = variableMap[source];
    if (sourceValue === undefined) {
        throw new Error(`Source variable not found: ${source}`);
    }
    return applyTransform(sourceValue, transform);
}
/**
 * Build variable map from template and context
 */
function buildVariableMap(template, context) {
    const variables = {};
    // 1. Add APPTAINER_IMAGE
    variables.APPTAINER_IMAGE = context.apptainerImage;
    // 2. Add dynamic variables (from Slurm config)
    if (template.variables.dynamic) {
        for (const [varName, varDef] of Object.entries(template.variables.dynamic)) {
            try {
                variables[varName] = resolveDynamicVariable(varDef.source, varDef.transform, context);
            }
            catch (error) {
                if (varDef.required) {
                    throw error;
                }
                // Optional variable, skip if not available
                console.warn(`Optional variable ${varName} could not be resolved:`, error);
            }
        }
    }
    // 3. Add input file variables
    if (template.variables.input_files) {
        for (const [varName, varDef] of Object.entries(template.variables.input_files)) {
            const fileValue = context.inputFiles[varDef.file_key];
            if (!fileValue && varDef.required) {
                throw new Error(`Required input file not provided: ${varName} (file_key: ${varDef.file_key})`);
            }
            if (fileValue) {
                variables[varName] = fileValue;
            }
        }
    }
    // 4. Add computed variables (derived from other variables)
    if (template.variables.computed) {
        for (const [varName, varDef] of Object.entries(template.variables.computed)) {
            variables[varName] = resolveComputedVariable(varDef.source, varDef.transform, variables);
        }
    }
    // 5. Add custom values
    if (context.customValues) {
        Object.assign(variables, context.customValues);
    }
    return variables;
}
/**
 * Substitute variables in a string
 * Replaces ${VAR_NAME} with actual values
 */
function substituteVariables(text, variables) {
    return text.replace(/\$\{([A-Z_][A-Z0-9_]*)\}/g, (match, varName) => {
        if (!(varName in variables)) {
            console.warn(`Variable ${varName} not found in context, keeping placeholder`);
            return match;
        }
        return String(variables[varName]);
    });
}
/**
 * Generate Slurm script from command template
 */
export function generateScript(template, context) {
    // Build variable map
    const variables = buildVariableMap(template, context);
    const lines = [];
    // Shebang
    lines.push('#!/bin/bash');
    lines.push('');
    // Slurm directives
    lines.push('# Slurm Job Configuration');
    if (context.slurmConfig.partition) {
        lines.push(`#SBATCH --partition=${context.slurmConfig.partition}`);
    }
    if (context.slurmConfig.nodes) {
        lines.push(`#SBATCH --nodes=${context.slurmConfig.nodes}`);
    }
    if (context.slurmConfig.ntasks) {
        lines.push(`#SBATCH --ntasks=${context.slurmConfig.ntasks}`);
    }
    if (context.slurmConfig['cpus-per-task']) {
        lines.push(`#SBATCH --cpus-per-task=${context.slurmConfig['cpus-per-task']}`);
    }
    if (context.slurmConfig.mem) {
        lines.push(`#SBATCH --mem=${context.slurmConfig.mem}`);
    }
    if (context.slurmConfig.time) {
        lines.push(`#SBATCH --time=${context.slurmConfig.time}`);
    }
    if (context.slurmConfig.qos) {
        lines.push(`#SBATCH --qos=${context.slurmConfig.qos}`);
    }
    lines.push('');
    // Pre-commands
    if (template.pre_commands && template.pre_commands.length > 0) {
        lines.push('# Pre-execution commands');
        for (const cmd of template.pre_commands) {
            lines.push(substituteVariables(cmd, variables));
        }
        lines.push('');
    }
    // Main command
    lines.push('# Main command');
    const mainCommand = substituteVariables(template.command.format, variables);
    lines.push(mainCommand);
    lines.push('');
    // Post-commands
    if (template.post_commands && template.post_commands.length > 0) {
        lines.push('# Post-execution commands');
        for (const cmd of template.post_commands) {
            lines.push(substituteVariables(cmd, variables));
        }
        lines.push('');
    }
    return lines.join('\n');
}
/**
 * Validate that all required variables can be resolved
 */
export function validateTemplate(template, context) {
    const errors = [];
    try {
        buildVariableMap(template, context);
    }
    catch (error) {
        errors.push(error instanceof Error ? error.message : String(error));
    }
    return {
        valid: errors.length === 0,
        errors,
    };
}
/**
 * Get required input files for a template
 */
export function getRequiredInputFiles(template) {
    const required = [];
    if (template.variables.input_files) {
        for (const [varName, varDef] of Object.entries(template.variables.input_files)) {
            if (varDef.required) {
                required.push(varDef.file_key);
            }
        }
    }
    return required;
}
/**
 * Get required Slurm config fields for a template
 */
export function getRequiredSlurmFields(template) {
    const required = [];
    if (template.variables.dynamic) {
        for (const [varName, varDef] of Object.entries(template.variables.dynamic)) {
            if (varDef.required && varDef.source.startsWith('slurm.')) {
                const field = varDef.source.substring(6);
                required.push(field);
            }
        }
    }
    return required;
}
export default {
    generateScript,
    validateTemplate,
    getRequiredInputFiles,
    getRequiredSlurmFields,
    // Export transform functions for external use
    transforms: TRANSFORM_FUNCTIONS,
};
