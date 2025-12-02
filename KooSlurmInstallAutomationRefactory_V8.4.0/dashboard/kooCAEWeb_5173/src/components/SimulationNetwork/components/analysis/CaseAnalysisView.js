import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import { Card, Alert, Button, Space, Spin, Typography } from 'antd';
import { simulationAnalysisService } from '../../services/analysisService';
const { Text } = Typography;
const CaseAnalysisView = ({ selectedCases, analysisMode }) => {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [result, setResult] = useState(null);
    const handleRunAnalysis = async () => {
        if (!selectedCases || selectedCases.length === 0)
            return;
        setLoading(true);
        setError(null);
        setResult(null);
        try {
            if (analysisMode === 'single') {
                const res = await simulationAnalysisService.analyzeSingleCase(selectedCases[0]);
                setResult(res);
            }
            else {
                const res = await simulationAnalysisService.analyzeBatch({ case_ids: selectedCases, include_summary: true });
                setResult(res);
            }
        }
        catch (e) {
            setError(e?.message || '분석에 실패했습니다.');
        }
        finally {
            setLoading(false);
        }
    };
    return (_jsx(Card, { children: !selectedCases || selectedCases.length === 0 ? (_jsx(Alert, { type: "info", message: "\uCF00\uC774\uC2A4\uB97C \uC120\uD0DD\uD574\uC8FC\uC138\uC694.", showIcon: true })) : (_jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsxs(Text, { children: ["\uC120\uD0DD\uB41C \uCF00\uC774\uC2A4: ", selectedCases.join(', '), " (", analysisMode === 'single' ? '단일' : '일괄', ")"] }), _jsx(Button, { type: "primary", onClick: handleRunAnalysis, loading: loading, children: "\uBD84\uC11D \uC2E4\uD589" }), error && _jsx(Alert, { type: "error", message: error, showIcon: true }), _jsx(Spin, { spinning: loading, children: result && (_jsx(Card, { size: "small", title: "\uBD84\uC11D \uACB0\uACFC", children: _jsx("pre", { style: { margin: 0, whiteSpace: 'pre-wrap' }, children: JSON.stringify(result, null, 2) }) })) })] })) }));
};
export default CaseAnalysisView;
