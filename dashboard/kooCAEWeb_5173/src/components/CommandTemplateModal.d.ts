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
import { CommandTemplate, ApptainerImage } from '../types/apptainer';
interface CommandTemplateModalProps {
    open: boolean;
    onClose: () => void;
    image: ApptainerImage | null;
    onSelectTemplate: (template: CommandTemplate, customValues?: Record<string, string>) => void;
}
declare const CommandTemplateModal: React.FC<CommandTemplateModalProps>;
export default CommandTemplateModal;
