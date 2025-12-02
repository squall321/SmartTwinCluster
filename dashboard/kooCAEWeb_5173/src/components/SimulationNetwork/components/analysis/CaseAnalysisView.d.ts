import React from 'react';
interface CaseAnalysisViewProps {
    selectedCases: string[];
    analysisMode: 'single' | 'batch';
}
declare const CaseAnalysisView: React.FC<CaseAnalysisViewProps>;
export default CaseAnalysisView;
