/**
 * Enhanced SubmitLsdynaPanel with Apptainer Template Integration
 *
 * This version includes:
 * - Original file upload and configuration functionality
 * - Apptainer command template selection
 * - Automatic script generation from templates
 * - Template-based job parameter population
 */
import React from 'react';
import type { LsdynaJobConfig } from '../uploader/LsdynaOptionTable';
interface SubmitLsdynaPanelWithTemplatesProps {
    initialConfigs?: LsdynaJobConfig[];
    autoSubmit?: boolean;
    onSubmitSuccess?: (submitted: any[]) => void;
}
declare const SubmitLsdynaPanelWithTemplates: React.FC<SubmitLsdynaPanelWithTemplatesProps>;
export default SubmitLsdynaPanelWithTemplates;
