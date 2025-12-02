import React from 'react';
import { LsdynaJobConfig } from './LsdynaOptionTable';
interface LsdynaFileUploaderProps {
    onDataUpdate?: (data: LsdynaJobConfig[]) => void;
    initialData?: LsdynaJobConfig[];
}
declare const LsdynaFileUploader: React.FC<LsdynaFileUploaderProps>;
export default LsdynaFileUploader;
