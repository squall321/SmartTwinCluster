import React from 'react';
import type { LsdynaJobConfig } from '../uploader/LsdynaOptionTable';
interface SubmitLsdynaPanelProps {
    initialConfigs?: LsdynaJobConfig[];
    autoSubmit?: boolean;
    onSubmitSuccess?: (submitted: any[]) => void;
}
declare const SubmitLsdynaPanel: React.FC<SubmitLsdynaPanelProps>;
export default SubmitLsdynaPanel;
