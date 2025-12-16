import React from 'react';
export interface LsdynaJobConfig {
    key: string;
    filename: string;
    file: File;
    cores: number;
    precision: 'single' | 'double';
    version: 'R15' | 'R14';
    mode: 'SMP' | 'MPP';
}
interface Props {
    data: LsdynaJobConfig[];
    onUpdateAll: <K extends keyof LsdynaJobConfig>(field: K, value: LsdynaJobConfig[K]) => void;
    onUpdateRow: <K extends keyof LsdynaJobConfig>(key: string, field: K, value: LsdynaJobConfig[K]) => void;
    onDeleteRow: (key: string) => void;
}
declare const LsdynaOptionTable: React.FC<Props>;
export default LsdynaOptionTable;
