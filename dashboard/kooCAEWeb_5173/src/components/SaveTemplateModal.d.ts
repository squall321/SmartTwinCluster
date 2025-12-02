/**
 * SaveTemplateModal Component
 *
 * Modal for saving current job configuration as a template
 */
import React from 'react';
interface SaveTemplateModalProps {
    open: boolean;
    onClose: () => void;
    onSave: (templateData: SaveTemplateData) => Promise<void>;
    defaultName?: string;
}
export interface SaveTemplateData {
    name: string;
    description: string;
    category: 'simulation' | 'ml' | 'data' | 'custom';
    shared: boolean;
}
declare const SaveTemplateModal: React.FC<SaveTemplateModalProps>;
export default SaveTemplateModal;
