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
import { CommandTemplate, ApptainerImage } from '../types/apptainer';
interface ApptainerImageSelectorProps {
    onSelectImage: (image: ApptainerImage) => void;
    onSelectTemplate?: (image: ApptainerImage, template: CommandTemplate) => void;
    selectedImageId?: string;
    partition?: 'compute' | 'viz' | 'shared' | null;
}
declare const ApptainerImageSelector: React.FC<ApptainerImageSelectorProps>;
export default ApptainerImageSelector;
