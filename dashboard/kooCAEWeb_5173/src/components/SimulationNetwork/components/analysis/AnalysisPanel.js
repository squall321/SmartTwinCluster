import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * 시뮬레이션 분석 메인 패널
 * 분석 기능들을 통합한 메인 컴포넌트
 */
import { useState, useEffect } from 'react';
import { Tabs, Card, Button, Select, Space, Alert, Spin, Typography, Row, Col, Statistic } from 'antd';
import { BarChartOutlined, PieChartOutlined, TableOutlined, DashboardOutlined, ReloadOutlined } from '@ant-design/icons';
import { simulationAnalysisService } from '../../services/analysisService';
import { useSimulationNetworkStore } from '../../store/simulationnetworkStore';
import ContactAnalysisView from './ContactAnalysisView';
import PartsAnalysisView from './PartsAnalysisView';
import CaseAnalysisView from './CaseAnalysisView.js';
import SummaryDashboard from './SummaryDashboard';
const { Title, Text } = Typography;
const { Option } = Select;
const AnalysisPanel = () => {
    const nodes = useSimulationNetworkStore((state) => state.nodes);
    const selectedNode = useSimulationNetworkStore((state) => state.selectedNode);
    // 상태 관리
    const [activeTab, setActiveTab] = useState('dashboard');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [systemHealth, setSystemHealth] = useState(null);
    const [selectedCases, setSelectedCases] = useState([]);
    const [analysisMode, setAnalysisMode] = useState('single');
    // 케이스 목록 (노드에서 추출)
    const availableCases = nodes.map((node) => ({
        id: node.id,
        label: node.label || node.id,
        status: node.status
    }));
    // 시스템 상태 확인
    useEffect(() => {
        const checkHealth = async () => {
            try {
                const health = await simulationAnalysisService.checkSystemHealth();
                setSystemHealth(health);
            }
            catch (error) {
                console.error('Health check failed:', error);
            }
        };
        checkHealth();
    }, []);
    // 선택된 노드가 변경되면 단일 케이스 모드로 설정
    useEffect(() => {
        if (selectedNode) {
            setSelectedCases([selectedNode.id]);
            setAnalysisMode('single');
        }
    }, [selectedNode]);
    // 전체 새로고침
    const handleRefresh = async () => {
        setLoading(true);
        setError(null);
        try {
            const health = await simulationAnalysisService.checkSystemHealth();
            setSystemHealth(health);
        }
        catch (err) {
            setError('시스템 상태 확인에 실패했습니다.');
        }
        finally {
            setLoading(false);
        }
    };
    // 케이스 선택 변경
    const handleCaseSelection = (caseIds) => {
        setSelectedCases(caseIds);
        setAnalysisMode(caseIds.length === 1 ? 'single' : 'batch');
    };
    // 탭 아이템 구성
    const tabItems = [
        {
            key: 'dashboard',
            label: (_jsxs("span", { children: [_jsx(DashboardOutlined, {}), "\uB300\uC2DC\uBCF4\uB4DC"] })),
            children: (_jsx(SummaryDashboard, { selectedCases: selectedCases, systemHealth: systemHealth }))
        },
        {
            key: 'case-analysis',
            label: (_jsxs("span", { children: [_jsx(TableOutlined, {}), "\uCF00\uC774\uC2A4 \uBD84\uC11D"] })),
            children: (_jsx(CaseAnalysisView, { selectedCases: selectedCases, analysisMode: analysisMode }))
        },
        {
            key: 'contact-analysis',
            label: (_jsxs("span", { children: [_jsx(PieChartOutlined, {}), "\uC811\uCD09 \uBD84\uC11D"] })),
            children: (_jsx(ContactAnalysisView, { selectedCases: selectedCases }))
        },
        {
            key: 'parts-analysis',
            label: (_jsxs("span", { children: [_jsx(BarChartOutlined, {}), "\uBD80\uD488 \uBD84\uC11D"] })),
            children: (_jsx(PartsAnalysisView, { selectedCases: selectedCases }))
        }
    ];
    return (_jsxs("div", { style: { padding: '16px', backgroundColor: '#f5f5f5', minHeight: '100vh' }, children: [_jsxs(Card, { style: { marginBottom: '16px' }, children: [_jsxs(Row, { justify: "space-between", align: "middle", children: [_jsxs(Col, { children: [_jsxs(Title, { level: 3, style: { margin: 0 }, children: [_jsx(DashboardOutlined, { style: { color: '#1890ff', marginRight: '8px' } }), "\uC2DC\uBBAC\uB808\uC774\uC158 \uBD84\uC11D"] }), _jsx(Text, { type: "secondary", children: "DropSet.json \uB370\uC774\uD130\uB97C \uBD84\uC11D\uD558\uC5EC \uC811\uCD09, \uBD80\uD488, \uD488\uC9C8 \uC815\uBCF4\uB97C \uC81C\uACF5\uD569\uB2C8\uB2E4" })] }), _jsx(Col, { children: _jsx(Space, { children: _jsx(Button, { icon: _jsx(ReloadOutlined, {}), onClick: handleRefresh, loading: loading, children: "\uC0C8\uB85C\uACE0\uCE68" }) }) })] }), systemHealth && (_jsxs(Row, { gutter: 16, style: { marginTop: '16px' }, children: [_jsx(Col, { span: 6, children: _jsx(Statistic, { title: "\uC0AC\uC6A9 \uAC00\uB2A5\uD55C \uCF00\uC774\uC2A4", value: systemHealth.available_cases, prefix: _jsx(TableOutlined, {}) }) }), _jsx(Col, { span: 6, children: _jsx(Statistic, { title: "\uBD84\uC11D \uAC00\uB2A5\uD55C \uCF00\uC774\uC2A4", value: systemHealth.analyzable_cases, prefix: _jsx(DashboardOutlined, {}), valueStyle: {
                                        color: systemHealth.analyzable_cases > 0 ? '#52c41a' : '#ff4d4f'
                                    } }) }), _jsx(Col, { span: 6, children: _jsx(Statistic, { title: "\uC120\uD0DD\uB41C \uCF00\uC774\uC2A4", value: selectedCases.length, prefix: _jsx(PieChartOutlined, {}) }) }), _jsx(Col, { span: 6, children: _jsx(Statistic, { title: "\uBD84\uC11D \uBAA8\uB4DC", value: analysisMode === 'single' ? '단일' : '일괄', prefix: _jsx(BarChartOutlined, {}) }) })] }))] }), _jsxs(Card, { style: { marginBottom: '16px' }, title: "\uBD84\uC11D \uB300\uC0C1 \uC120\uD0DD", children: [_jsxs(Row, { gutter: 16, align: "middle", children: [_jsx(Col, { flex: "auto", children: _jsx(Select, { mode: "multiple", placeholder: "\uBD84\uC11D\uD560 \uCF00\uC774\uC2A4\uB97C \uC120\uD0DD\uD558\uC138\uC694", value: selectedCases, onChange: handleCaseSelection, style: { width: '100%' }, showSearch: true, filterOption: (input, option) => option?.children?.toString().toLowerCase().includes(input.toLowerCase()) ?? false, children: availableCases.map(case_ => (_jsx(Option, { value: case_.id, children: _jsxs(Space, { children: [_jsx("span", { children: case_.label }), _jsxs(Text, { type: "secondary", children: ["(", case_.status, ")"] })] }) }, case_.id))) }) }), _jsx(Col, { children: _jsx(Text, { type: "secondary", children: selectedCases.length > 0
                                        ? `${selectedCases.length}개 케이스 선택됨`
                                        : '케이스를 선택해주세요' }) })] }), selectedNode && (_jsx(Alert, { style: { marginTop: '12px' }, message: `현재 선택된 노드: ${selectedNode.label || selectedNode.id}`, description: "\uADF8\uB798\uD504\uC5D0\uC11C \uB178\uB4DC\uB97C \uC120\uD0DD\uD558\uBA74 \uD574\uB2F9 \uCF00\uC774\uC2A4\uAC00 \uC790\uB3D9\uC73C\uB85C \uBD84\uC11D \uB300\uC0C1\uC73C\uB85C \uC124\uC815\uB429\uB2C8\uB2E4.", type: "info", showIcon: true, closable: true, onClose: () => setSelectedCases([]) }))] }), error && (_jsx(Alert, { message: "\uC624\uB958 \uBC1C\uC0DD", description: error, type: "error", closable: true, onClose: () => setError(null), style: { marginBottom: '16px' } })), _jsx(Spin, { spinning: loading, children: _jsx(Tabs, { activeKey: activeTab, onChange: setActiveTab, items: tabItems, size: "large" }) })] }));
};
export default AnalysisPanel;
