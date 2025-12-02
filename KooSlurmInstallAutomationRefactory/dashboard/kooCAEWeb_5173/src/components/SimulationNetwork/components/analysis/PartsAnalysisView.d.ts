/**
 * 부품 분석 뷰 컴포넌트
 * 부품 카테고리, 연결성, 고립된 부품을 분석
 */
import React from 'react';
interface PartsAnalysisViewProps {
    selectedCases: string[];
}
declare const PartsAnalysisView: React.FC<PartsAnalysisViewProps>;
export default PartsAnalysisView;
