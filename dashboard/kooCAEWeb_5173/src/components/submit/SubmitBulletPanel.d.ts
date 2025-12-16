import React from 'react';
export type SubmitBulletPanelProps = {
    csvData?: (string | number)[][];
    csvPath?: string;
    objPath?: string;
    defaultTimestep?: number;
    defaultWriteTime?: number;
    defaultThreads?: number;
    solverEntry?: string;
};
declare const SubmitBulletPanel: React.FC<SubmitBulletPanelProps>;
export default SubmitBulletPanel;
