/**
 * 요약 대시보드 컴포넌트
 * 전체적인 분석 통계와 개요를 표시
 */
import React from 'react';
interface SummaryDashboardProps {
    selectedCases: string[];
    systemHealth?: any;
}
declare const SummaryDashboard: React.FC<SummaryDashboardProps>;
export default SummaryDashboard;
