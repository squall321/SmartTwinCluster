/**
 * ApptainerTemplateIntegration Component
 *
 * Unified integration component that wraps ApptainerImageSelector and CommandTemplateModal
 * for easy integration into existing job submission pages.
 *
 * Features:
 * - Single component for complete template selection workflow
 * - Automatic script generation with variable substitution
 * - Integration with existing job configuration structures
 * - Support for both LS-DYNA and general Apptainer workflows
 * - Collapsible panel to save screen space
 */
import React from 'react';
interface CommandTemplate {
    template_id: string;
    display_name: string;
    description: string;
    category: string;
    command: {
        executable: string;
        format: string;
        requires_mpi: boolean;
    };
    variables: any;
    pre_commands?: string[];
    post_commands?: string[];
}
interface ApptainerImage {
    id: string;
    name: string;
    path: string;
    partition: string;
    command_templates: CommandTemplate[];
}
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
interface ApptainerTemplateIntegrationProps {
    /**
     * Callback when template is selected and script is generated
     * @param script - Generated Slurm script
     * @param template - Selected command template
     * @param image - Selected Apptainer image
     */
    onTemplateApply: (script: string, template: CommandTemplate, image: ApptainerImage) => void;
    /**
     * Current Slurm job configuration (will be used for variable substitution)
     */
    slurmConfig?: SlurmJobConfig;
    /**
     * Input files for variable substitution
     * Key should match the file_key in template definition
     */
    inputFiles?: Record<string, string>;
    /**
     * Filter images by partition
     */
    partition?: 'compute' | 'viz' | 'shared' | null;
    /**
     * Whether to show the panel expanded by default
     */
    defaultExpanded?: boolean;
    /**
     * Custom button text for applying template
     */
    applyButtonText?: string;
    /**
     * Show script preview before applying
     */
    showPreview?: boolean;
}
declare const ApptainerTemplateIntegration: React.FC<ApptainerTemplateIntegrationProps>;
export default ApptainerTemplateIntegration;
