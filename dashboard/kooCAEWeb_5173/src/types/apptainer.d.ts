/**
 * Shared type definitions for Apptainer templates system
 */
export interface CommandTemplate {
    template_id: string;
    display_name: string;
    description: string;
    category: 'solver' | 'post-processing' | 'preprocessing';
    command: {
        executable: string;
        format: string;
        requires_mpi: boolean;
    };
    variables?: {
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
export interface ApptainerImage {
    id: string;
    name: string;
    path: string;
    node?: string;
    partition: string | 'compute' | 'viz' | 'shared';
    type?: 'viz' | 'compute' | 'shared' | 'custom';
    size?: number;
    version?: string;
    description?: string;
    labels?: Record<string, string>;
    apps?: string[];
    command_templates: CommandTemplate[];
    created_at?: string;
    updated_at?: string;
    last_scanned?: string;
    is_active?: boolean;
}
