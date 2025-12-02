import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * 요약 대시보드 컴포넌트
 * 전체적인 분석 통계와 개요를 표시
 */
import { useState, useEffect } from 'react';
import { Card, Row, Col, Statistic, Progress, Table, Tag, Typography, Spin, Empty } from 'antd';
import { ContactsOutlined, BuildOutlined, AlertOutlined, CheckCircleOutlined } from '@ant-design/icons';
import { simulationAnalysisService } from '../../services/analysisService';
const { Title, Text } = Typography;
const SummaryDashboard = ({ selectedCases, systemHealth }) => {
    const [loading, setLoading] = useState(false);
    const [summaryData, setSummaryData] = useState(null);
    const [error, setError] = useState(null);
    // 선택된 케이스들 분석
    useEffect(() => {
        if (selectedCases.length === 0) {
            setSummaryData(null);
            return;
        }
        const analyzeCases = async () => {
            setLoading(true);
            setError(null);
            try {
                const result = await simulationAnalysisService.analyzeBatch({
                    case_ids: selectedCases,
                    include_summary: true
                });
                setSummaryData(result);
            }
            catch (err) {
                setError('분석 중 오류가 발생했습니다.');
                console.error('Dashboard analysis failed:', err);
            }
            finally {
                setLoading(false);
            }
        };
        analyzeCases();
    }, [selectedCases]);
    // 성공률 계산
    const getSuccessRate = () => {
        if (!summaryData)
            return 0;
        return (summaryData.successful_analyses / summaryData.total_cases) * 100;
    };
    // 케이스별 요약 테이블 컬럼
    const caseColumns = [
        {
            title: '케이스 ID',
            dataIndex: 'case_id',
            key: 'case_id',
            render: (text) => _jsx(Text, { code: true, children: text })
        },
        {
            title: '시나리오',
            dataIndex: ['analysis', 'basic_info', 'scenario_mode'],
            key: 'scenario_mode',
            render: (text) => _jsx(Tag, { color: "blue", children: text })
        },
        {
            title: '접촉 수',
            dataIndex: ['analysis', 'contact_analysis', 'total_contacts'],
            key: 'contacts',
            render: (value) => (_jsx(Statistic, { value: value, valueStyle: { fontSize: '14px' }, prefix: _jsx(ContactsOutlined, {}) }))
        },
        {
            title: '부품 수',
            dataIndex: ['analysis', 'parts_analysis', 'total_parts'],
            key: 'parts',
            render: (value) => (_jsx(Statistic, { value: value, valueStyle: { fontSize: '14px' }, prefix: _jsx(BuildOutlined, {}) }))
        },
        {
            title: '연결률',
            key: 'connection_rate',
            render: (record) => {
                const parts = record.analysis.parts_analysis;
                const rate = parts.total_parts > 0
                    ? (parts.parts_with_contacts / parts.total_parts) * 100
                    : 0;
                return (_jsx(Progress, { percent: Math.round(rate), size: "small", status: rate > 80 ? 'success' : rate > 50 ? 'normal' : 'exception' }));
            }
        }
    ];
    if (selectedCases.length === 0) {
        return (_jsx(Card, { children: _jsx(Empty, { description: "\uBD84\uC11D\uD560 \uCF00\uC774\uC2A4\uB97C \uC120\uD0DD\uD574\uC8FC\uC138\uC694", image: Empty.PRESENTED_IMAGE_SIMPLE }) }));
    }
    return (_jsx(Spin, { spinning: loading, children: _jsxs("div", { children: [_jsxs(Row, { gutter: 16, style: { marginBottom: '24px' }, children: [_jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uC120\uD0DD\uB41C \uCF00\uC774\uC2A4", value: selectedCases.length, prefix: _jsx(CheckCircleOutlined, {}), valueStyle: { color: '#1890ff' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uBD84\uC11D \uC131\uACF5\uB960", value: getSuccessRate(), suffix: "%", prefix: _jsx(AlertOutlined, {}), valueStyle: {
                                        color: getSuccessRate() > 80 ? '#52c41a' : '#faad14'
                                    } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uD3C9\uADE0 \uC811\uCD09 \uC218", value: summaryData?.summary_report?.contact_analysis.contact_stats.average || 0, precision: 1, prefix: _jsx(ContactsOutlined, {}), valueStyle: { color: '#722ed1' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uD3C9\uADE0 \uBD80\uD488 \uC218", value: summaryData?.summary_report?.parts_analysis.parts_stats.average || 0, precision: 1, prefix: _jsx(BuildOutlined, {}), valueStyle: { color: '#13c2c2' } }) }) })] }), summaryData?.summary_report && (_jsxs(Row, { gutter: 16, style: { marginBottom: '24px' }, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uC811\uCD09 \uD1B5\uACC4", size: "small", children: _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Statistic, { title: "\uCD5C\uB300", value: summaryData.summary_report.contact_analysis.contact_stats.max }) }), _jsx(Col, { span: 12, children: _jsx(Statistic, { title: "\uCD5C\uC18C", value: summaryData.summary_report.contact_analysis.contact_stats.min }) })] }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "\uBD80\uD488 \uD1B5\uACC4", size: "small", children: _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Statistic, { title: "\uCD5C\uB300", value: summaryData.summary_report.parts_analysis.parts_stats.max }) }), _jsx(Col, { span: 12, children: _jsx(Statistic, { title: "\uCD5C\uC18C", value: summaryData.summary_report.parts_analysis.parts_stats.min }) })] }) }) })] })), summaryData?.summary_report?.summary.scenario_modes && (_jsx(Card, { title: "\uC2DC\uB098\uB9AC\uC624 \uBAA8\uB4DC \uBD84\uD3EC", style: { marginBottom: '24px' }, size: "small", children: _jsx(Row, { gutter: 16, children: Object.entries(summaryData.summary_report.summary.scenario_modes).map(([mode, count]) => (_jsx(Col, { span: 6, children: _jsx(Statistic, { title: mode, value: count, valueStyle: { fontSize: '18px' } }) }, mode))) }) })), _jsx(Card, { title: "\uCF00\uC774\uC2A4\uBCC4 \uC694\uC57D", children: _jsx(Table, { columns: caseColumns, dataSource: summaryData?.analyses || [], rowKey: "case_id", size: "small", pagination: {
                            pageSize: 10,
                            showSizeChanger: true,
                            showQuickJumper: true,
                            showTotal: (total) => `총 ${total}개 케이스`
                        } }) }), summaryData && summaryData.failed_cases.length > 0 && (_jsx(Card, { title: "\uBD84\uC11D \uC2E4\uD328 \uCF00\uC774\uC2A4", style: { marginTop: '16px' }, headStyle: { color: '#ff4d4f' }, children: _jsx("div", { children: summaryData.failed_cases.map(caseId => (_jsx(Tag, { color: "red", style: { marginBottom: '8px' }, children: caseId }, caseId))) }) })), error && (_jsx(Card, { title: "\uC624\uB958", style: { marginTop: '16px' }, headStyle: { color: '#ff4d4f' }, children: _jsx(Text, { type: "danger", children: error }) }))] }) }));
};
export default SummaryDashboard;
