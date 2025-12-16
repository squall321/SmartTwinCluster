import React from 'react';
interface Props {
    selectedDate?: string;
    selectedMode?: string;
    prefix?: string;
    onDateChange: (date?: string) => void;
    onModeChange: (mode?: string) => void;
    onPrefixChange: (prefix?: string) => void;
    onLoad: () => void;
    allDates: string[];
    allModes: string[];
}
declare const FileFilterPanel: React.FC<Props>;
export default FileFilterPanel;
