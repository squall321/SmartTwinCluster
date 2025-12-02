/**
 * ApptainerImageSelector Component
 *
 * Allows users to browse and select Apptainer container images
 * with their associated command templates.
 *
 * Features:
 * - Display available Apptainer images from the cluster
 * - Show command template count badges
 * - Filter by partition (compute/viz) and type
 * - Search by image name or description
 * - Click to select image and view command templates
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
}
interface ApptainerImage {
    id: string;
    name: string;
    path: string;
    node: string;
    partition: 'compute' | 'viz' | 'shared';
    type: 'viz' | 'compute' | 'shared' | 'custom';
    size: number;
    version: string;
    description: string;
    labels: Record<string, string>;
    apps: string[];
    command_templates: CommandTemplate[];
    created_at: string;
    updated_at: string;
    last_scanned: string;
    is_active: boolean;
}
interface ApptainerImageSelectorProps {
    onSelectImage: (image: ApptainerImage) => void;
    onSelectTemplate?: (image: ApptainerImage, template: CommandTemplate) => void;
    selectedImageId?: string;
    partition?: 'compute' | 'viz' | 'shared' | null;
}
declare const ApptainerImageSelector: React.FC<ApptainerImageSelectorProps>;
export default ApptainerImageSelector;
