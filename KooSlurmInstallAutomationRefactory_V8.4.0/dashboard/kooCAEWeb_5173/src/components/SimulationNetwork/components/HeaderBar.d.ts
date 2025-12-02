import React from 'react';
interface HeaderBarProps {
    onExport?: () => void;
    onRefresh?: () => void;
    showAnalysisPanel?: boolean;
    onToggleAnalysisPanel?: () => void;
}
declare const HeaderBar: React.FC<HeaderBarProps>;
export default HeaderBar;
