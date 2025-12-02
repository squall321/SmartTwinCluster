/**
 * CommandTemplateModal Component
 *
 * Displays available command templates for a selected Apptainer image
 * and allows users to select one to insert into their job script.
 *
 * Features:
 * - List all command templates for the selected image
 * - Display template details (description, variables, I/O requirements)
 * - Preview generated command
 * - "Insert into Script" functionality
 * - Handle required vs optional variables
 * - Show MPI requirements
 */
import React from 'react';
interface CommandTemplate {
    template_id: string;
    display_name: string;
    description: string;
    category: 'solver' | 'post-processing' | 'preprocessing';
    command: {
        executable: string;
        format: string;
        requires_mpi: boolean;
    };
    variables: {
        dynamic?: Record<string, {
            source: string;
            transform?: string;
            description: string;
            required: boolean;
        }>;
        input_files?: Record<string, {
            description: string;
            pattern: string;
            required: boolean;
            file_key: string;
        }>;
        output_files?: Record<string, {
            pattern: string;
            description: string;
            collect: boolean;
        }>;
        input_dependencies?: Record<string, {
            pattern: string;
            auto_detect?: boolean;
            auto_generate?: boolean;
            source_dir?: string;
            generate_rule?: string;
        }>;
        computed?: Record<string, {
            source: string;
            transform: string;
            description: string;
        }>;
    };
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
interface CommandTemplateModalProps {
    open: boolean;
    onClose: () => void;
    image: ApptainerImage | null;
    onSelectTemplate: (template: CommandTemplate, customValues?: Record<string, string>) => void;
}
declare const CommandTemplateModal: React.FC<CommandTemplateModalProps>;
export default CommandTemplateModal;
