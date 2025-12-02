import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * 부품 분석 뷰 컴포넌트
 * 부품 카테고리, 연결성, 고립된 부품을 분석
 */
import { useState, useEffect } from 'react';
import { Card, Row, Col, Table, Tag, Statistic, List, Typography, Spin, Empty, Progress } from 'antd';
import { Column, Pie } from '@ant-design/charts';
import { BuildOutlined, DisconnectOutlined, NodeIndexOutlined, WarningOutlined } from '@ant-design/icons';
import { simulationAnalysisService } from '../../services/analysisService';
const { Title, Text } = Typography;
const PartsAnalysisView = ({ selectedCases }) => {
    const [loading, setLoading] = useState(false);
    const [partsData, setPartsData] = useState([]);
    const [aggregatedStats, setAggregatedStats] = useState(null);
    useEffect(() => {
        if (selectedCases.length === 0) {
            setPartsData([]);
            setAggregatedStats(null);
            return;
        }
        const analyzeParts = async () => {
            setLoading(true);
            try {
                const results = await Promise.all(selectedCases.map(async (caseId) => {
                    try {
                        const result = await simulationAnalysisService.analyzeSingleCase(caseId);
                        return {
                            caseId,
                            ...result.analysis.parts_analysis
                        };
                    }
                    catch (error) {
                        console.error(`Failed to analyze parts for case ${caseId}:`, error);
                        return null;
                    }
                }));
                const validResults = results.filter(Boolean);
                setPartsData(validResults);
                // 집계 통계 계산
                if (validResults.length > 0) {
                    const totalParts = validResults.reduce((sum, data) => sum + data.total_parts, 0);
                    const totalConnectedParts = validResults.reduce((sum, data) => sum + data.parts_with_contacts, 0);
                    const allCategories = {};
                    const allIsolatedParts = [];
                    validResults.forEach(data => {
                        Object.entries(data.part_categories).forEach(([category, count]) => {
                            allCategories[category] = (allCategories[category] || 0) + count;
                        });
                        allIsolatedParts.push(...data.isolated_parts);
                    });
                    setAggregatedStats({
                        totalCases: validResults.length,
                        totalParts,
                        totalConnectedParts,
                        averageParts: totalParts / validResults.length,
                        connectionRate: totalParts > 0 ? (totalConnectedParts / totalParts) * 100 : 0,
                        partCategories: allCategories,
                        totalIsolatedParts: allIsolatedParts.length
                    });
                }
            }
            catch (error) {
                console.error('Parts analysis failed:', error);
            }
            finally {
                setLoading(false);
            }
        };
        analyzeParts();
    }, [selectedCases]);
    // 부품 카테고리 파이 차트 데이터
    const categoryPieData = aggregatedStats ? Object.entries(aggregatedStats.partCategories).map(([category, count]) => ({
        type: category,
        value: count,
        percentage: ((count / aggregatedStats.totalParts) * 100).toFixed(1)
    })) : [];
    // 케이스별 부품 수 컬럼 차트 데이터
    const partsColumnData = partsData.map(data => ({
        case: data.caseId,
        total: data.total_parts,
        connected: data.parts_with_contacts,
        isolated: data.total_parts - data.parts_with_contacts
    }));
    // 부품 카테고리별 테이블 컬럼
    const categoryColumns = [
        {
            title: '부품 카테고리',
            dataIndex: 'category',
            key: 'category',
            render: (text) => _jsx(Tag, { color: "green", children: text })
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
    const categoryTableData = aggregatedStats ? Object.entries(aggregatedStats.partCategories).map(([category, count]) => ({
        key: category,
        category,
        count: count,
        percentage: ((count / aggregatedStats.totalParts) * 100).toFixed(1)
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
            title: '총 부품 수',
            dataIndex: 'total_parts',
            key: 'total_parts',
            sorter: (a, b) => a.total_parts - b.total_parts,
            render: (value) => (_jsx(Statistic, { value: value, valueStyle: { fontSize: '14px' }, prefix: _jsx(BuildOutlined, {}) }))
        },
        {
            title: '연결된 부품',
            dataIndex: 'parts_with_contacts',
            key: 'parts_with_contacts',
            render: (value) => (_jsx(Statistic, { value: value, valueStyle: { fontSize: '14px', color: '#52c41a' }, prefix: _jsx(NodeIndexOutlined, {}) }))
        },
        {
            title: '고립된 부품',
            dataIndex: 'isolated_parts',
            key: 'isolated_parts',
            render: (parts) => (_jsx(Statistic, { value: parts.length, valueStyle: {
                    fontSize: '14px',
                    color: parts.length > 0 ? '#ff4d4f' : '#52c41a'
                }, prefix: _jsx(DisconnectOutlined, {}) }))
        },
        {
            title: '연결률',
            key: 'connection_rate',
            render: (record) => {
                const rate = record.total_parts > 0
                    ? (record.parts_with_contacts / record.total_parts) * 100
                    : 0;
                return (_jsx(Progress, { percent: Math.round(rate), size: "small", status: rate > 80 ? 'success' : rate > 50 ? 'normal' : 'exception' }));
            }
        }
    ];
    if (selectedCases.length === 0) {
        return (_jsx(Card, { children: _jsx(Empty, { description: "\uBD84\uC11D\uD560 \uCF00\uC774\uC2A4\uB97C \uC120\uD0DD\uD574\uC8FC\uC138\uC694", image: Empty.PRESENTED_IMAGE_SIMPLE }) }));
    }
    return (_jsx(Spin, { spinning: loading, children: _jsxs("div", { children: [aggregatedStats && (_jsxs(Row, { gutter: 16, style: { marginBottom: '24px' }, children: [_jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uCD1D \uBD80\uD488 \uC218", value: aggregatedStats.totalParts, prefix: _jsx(BuildOutlined, {}), valueStyle: { color: '#1890ff' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uD3C9\uADE0 \uBD80\uD488 \uC218", value: aggregatedStats.averageParts, precision: 1, prefix: _jsx(BuildOutlined, {}), valueStyle: { color: '#52c41a' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uC804\uCCB4 \uC5F0\uACB0\uB960", value: aggregatedStats.connectionRate, precision: 1, suffix: "%", prefix: _jsx(NodeIndexOutlined, {}), valueStyle: {
                                        color: aggregatedStats.connectionRate > 80 ? '#52c41a' : '#faad14'
                                    } }) }) }), _jsx(Col, { span: 6, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uACE0\uB9BD\uB41C \uBD80\uD488", value: aggregatedStats.totalIsolatedParts, prefix: _jsx(WarningOutlined, {}), valueStyle: {
                                        color: aggregatedStats.totalIsolatedParts > 0 ? '#ff4d4f' : '#52c41a'
                                    } }) }) })] })), _jsxs(Row, { gutter: 16, style: { marginBottom: '24px' }, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uBD80\uD488 \uCE74\uD14C\uACE0\uB9AC \uBD84\uD3EC", size: "small", children: categoryPieData.length > 0 ? (_jsx(Pie, { data: categoryPieData, angleField: "value", colorField: "type", radius: 0.8, label: {
                                        type: 'outer',
                                        content: '{name}: {percentage}%'
                                    }, height: 300 })) : (_jsx(Empty, { description: "\uB370\uC774\uD130 \uC5C6\uC74C" })) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "\uCF00\uC774\uC2A4\uBCC4 \uBD80\uD488 \uC5F0\uACB0\uC131", size: "small", children: partsColumnData.length > 0 ? (_jsx(Column, { data: partsColumnData.flatMap(item => [
                                        { case: item.case, type: '연결된 부품', value: item.connected },
                                        { case: item.case, type: '고립된 부품', value: item.isolated }
                                    ]), xField: "case", yField: "value", seriesField: "type", isStack: true, height: 300, color: ['#52c41a', '#ff4d4f'] })) : (_jsx(Empty, { description: "\uB370\uC774\uD130 \uC5C6\uC74C" })) }) })] }), _jsx(Card, { title: "\uBD80\uD488 \uCE74\uD14C\uACE0\uB9AC\uBCC4 \uD1B5\uACC4", style: { marginBottom: '24px' }, children: _jsx(Table, { columns: categoryColumns, dataSource: categoryTableData, size: "small", pagination: false }) }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 16, children: _jsx(Card, { title: "\uCF00\uC774\uC2A4\uBCC4 \uBD80\uD488 \uBD84\uC11D", children: _jsx(Table, { columns: caseDetailColumns, dataSource: partsData, rowKey: "caseId", size: "small", pagination: {
                                        pageSize: 10,
                                        showSizeChanger: true
                                    } }) }) }), _jsx(Col, { span: 8, children: _jsx(Card, { title: "\uACE0\uB9BD\uB41C \uBD80\uD488 \uBAA9\uB85D", size: "small", children: partsData.length > 0 ? (_jsx(List, { size: "small", dataSource: partsData.filter(data => data.isolated_parts.length > 0), renderItem: (data) => (_jsx(List.Item, { children: _jsxs("div", { style: { width: '100%' }, children: [_jsx(Text, { strong: true, children: data.caseId }), _jsxs("div", { style: { marginTop: '4px' }, children: [data.isolated_parts.slice(0, 3).map((part, index) => (_jsx(Tag, { color: "red", style: { margin: '2px' }, children: part.length > 20 ? `${part.substring(0, 20)}...` : part }, index))), data.isolated_parts.length > 3 && (_jsxs(Tag, { color: "orange", children: ["+", data.isolated_parts.length - 3, " \uB354"] }))] })] }) })), locale: { emptyText: '고립된 부품이 없습니다' } })) : (_jsx(Empty, { description: "\uB370\uC774\uD130 \uC5C6\uC74C" })) }) })] })] }) }));
};
export default PartsAnalysisView;
