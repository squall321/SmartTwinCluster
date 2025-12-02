import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * 접촉 분석 뷰 컴포넌트
 * 접촉 타입, 면적, 통계를 시각화
 */
import { useState, useEffect } from 'react';
import { Card, Row, Col, Table, Tag, Statistic, Progress, Typography, Spin, Empty } from 'antd';
import { Pie, Bar } from '@ant-design/charts';
import { ContactsOutlined, AreaChartOutlined, PieChartOutlined } from '@ant-design/icons';
import { simulationAnalysisService } from '../../services/analysisService';
const { Title, Text } = Typography;
const ContactAnalysisView = ({ selectedCases }) => {
    const [loading, setLoading] = useState(false);
    const [contactData, setContactData] = useState([]);
    const [aggregatedStats, setAggregatedStats] = useState(null);
    useEffect(() => {
        if (selectedCases.length === 0) {
            setContactData([]);
            setAggregatedStats(null);
            return;
        }
        const analyzeContacts = async () => {
            setLoading(true);
            try {
                const results = await Promise.all(selectedCases.map(async (caseId) => {
                    try {
                        const result = await simulationAnalysisService.analyzeSingleCase(caseId);
                        return {
                            caseId,
                            ...result.analysis.contact_analysis
                        };
                    }
                    catch (error) {
                        console.error(`Failed to analyze case ${caseId}:`, error);
                        return null;
                    }
                }));
                const validResults = results.filter(Boolean);
                setContactData(validResults);
                // 집계 통계 계산
                if (validResults.length > 0) {
                    const totalContacts = validResults.reduce((sum, data) => sum + data.total_contacts, 0);
                    const allTypes = {};
                    validResults.forEach(data => {
                        Object.entries(data.contact_types).forEach(([type, count]) => {
                            allTypes[type] = (allTypes[type] || 0) + count;
                        });
                    });
                    setAggregatedStats({
                        totalCases: validResults.length,
                        totalContacts,
                        averageContacts: totalContacts / validResults.length,
                        contactTypes: allTypes
                    });
                }
            }
            catch (error) {
                console.error('Contact analysis failed:', error);
            }
            finally {
                setLoading(false);
            }
        };
        analyzeContacts();
    }, [selectedCases]);
    // 접촉 타입 파이 차트 데이터
    const pieData = aggregatedStats ? Object.entries(aggregatedStats.contactTypes).map(([type, count]) => ({
        type: type.replace('KooContact', '').replace('SurfacetoSurface', 'S2S'),
        value: count,
        percentage: ((count / aggregatedStats.totalContacts) * 100).toFixed(1)
    })) : [];
    // 케이스별 접촉 수 바 차트 데이터
    const barData = contactData.map(data => ({
        case: data.caseId,
        contacts: data.total_contacts
    }));
    // 접촉 타입별 상세 테이블 컬럼
    const contactTypeColumns = [
        {
            title: '접촉 타입',
            dataIndex: 'type',
            key: 'type',
            render: (text) => (_jsx(Tag, { color: "blue", children: text.replace('KooContact', '').replace('SurfacetoSurface', 'S2S') }))
        },
        {
            title: '총 개수',
            dataIndex: 'count',
            key: 'count',
            sorter: (a, b) => a.count - b.count,
            render: (value) => _jsx(Text, { strong: true, children: value })
        },
        {
            title: '비율',
            dataIndex: 'percentage',
            key: 'percentage',
            render: (value) => (_jsx(Progress, { percent: parseFloat(value), size: "small", format: percent => `${percent}%` }))
        }
    ];
    const contactTypeTableData = aggregatedStats ? Object.entries(aggregatedStats.contactTypes).map(([type, count]) => ({
        key: type,
        type,
        count: count,
        percentage: ((count / aggregatedStats.totalContacts) * 100).toFixed(1)
    })) : [];
    // 케이스별 상세 정보 테이블 컬럼
    const caseDetailColumns = [
        {
            title: '케이스 ID',
            dataIndex: 'caseId',
            key: 'caseId',
            render: (text) => _jsx(Text, { code: true, children: text })
        },
        {
            title: '총 접촉 수',
            dataIndex: 'total_contacts',
            key: 'total_contacts',
            sorter: (a, b) => a.total_contacts - b.total_contacts,
            render: (value) => (_jsx(Statistic, { value: value, valueStyle: { fontSize: '14px' }, prefix: _jsx(ContactsOutlined, {}) }))
        },
        {
            title: '총 면적',
            dataIndex: ['area_stats', 'total_area'],
            key: 'total_area',
            render: (value) => value ? `${value.toFixed(1)}` : 'N/A'
        },
        {
            title: '평균 면적',
            dataIndex: ['area_stats', 'average_area'],
            key: 'average_area',
            render: (value) => value ? `${value.toFixed(1)}` : 'N/A'
        },
        {
            title: '최대 접촉',
            dataIndex: ['largest_contact', 'total_area'],
            key: 'largest_contact',
            render: (value) => value ? `${value.toFixed(1)}` : 'N/A'
        }
    ];
    if (selectedCases.length === 0) {
        return (_jsx(Card, { children: _jsx(Empty, { description: "\uBD84\uC11D\uD560 \uCF00\uC774\uC2A4\uB97C \uC120\uD0DD\uD574\uC8FC\uC138\uC694", image: Empty.PRESENTED_IMAGE_SIMPLE }) }));
    }
    return (_jsx(Spin, { spinning: loading, children: _jsxs("div", { children: [aggregatedStats && (_jsxs(Row, { gutter: 16, style: { marginBottom: '24px' }, children: [_jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uCD1D \uCF00\uC774\uC2A4 \uC218", value: aggregatedStats.totalCases, prefix: _jsx(ContactsOutlined, {}) }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uCD1D \uC811\uCD09 \uC218", value: aggregatedStats.totalContacts, prefix: _jsx(ContactsOutlined, {}), valueStyle: { color: '#1890ff' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uD3C9\uADE0 \uC811\uCD09 \uC218", value: aggregatedStats.averageContacts, precision: 1, prefix: _jsx(AreaChartOutlined, {}), valueStyle: { color: '#52c41a' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uC811\uCD09 \uD0C0\uC785 \uC218", value: Object.keys(aggregatedStats.contactTypes).length, prefix: _jsx(PieChartOutlined, {}), valueStyle: { color: '#722ed1' } }) }) })] })), _jsxs(Row, { gutter: 16, style: { marginBottom: '24px' }, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uC811\uCD09 \uD0C0\uC785 \uBD84\uD3EC", size: "small", children: pieData.length > 0 ? (_jsx(Pie, { data: pieData, angleField: "value", colorField: "type", radius: 0.8, label: {
                                        type: 'outer',
                                        content: '{name}: {percentage}%'
                                    }, height: 300 })) : (_jsx(Empty, { description: "\uB370\uC774\uD130 \uC5C6\uC74C" })) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "\uCF00\uC774\uC2A4\uBCC4 \uC811\uCD09 \uC218", size: "small", children: barData.length > 0 ? (_jsx(Bar, { data: barData, xField: "contacts", yField: "case", seriesField: "case", height: 300, color: "#1890ff" })) : (_jsx(Empty, { description: "\uB370\uC774\uD130 \uC5C6\uC74C" })) }) })] }), _jsx(Card, { title: "\uC811\uCD09 \uD0C0\uC785\uBCC4 \uD1B5\uACC4", style: { marginBottom: '24px' }, children: _jsx(Table, { columns: contactTypeColumns, dataSource: contactTypeTableData, size: "small", pagination: false }) }), _jsx(Card, { title: "\uCF00\uC774\uC2A4\uBCC4 \uC811\uCD09 \uBD84\uC11D", children: _jsx(Table, { columns: caseDetailColumns, dataSource: contactData, rowKey: "caseId", size: "small", pagination: {
                            pageSize: 10,
                            showSizeChanger: true
                        } }) })] }) }));
};
export default ContactAnalysisView;
