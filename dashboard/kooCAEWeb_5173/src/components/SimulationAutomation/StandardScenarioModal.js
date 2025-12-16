import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
/**
 * Standard Scenario Modal Component
 * 표준 규격 시나리오 선택 모달
 */
import { useState, useEffect } from 'react';
import { Modal, Card, Button, Tag, Spin, Alert, Tabs, Descriptions, Empty } from 'antd';
import { ExperimentOutlined, FallOutlined, ThunderboltOutlined, RotateRightOutlined, SafetyOutlined, CheckCircleOutlined } from '@ant-design/icons';
import axios from 'axios';
const { TabPane } = Tabs;
const StandardScenarioModal = ({ visible, onClose, onSelect }) => {
    const [scenarios, setScenarios] = useState([]);
    const [categories, setCategories] = useState([]);
    const [selectedCategory, setSelectedCategory] = useState('all');
    const [selectedScenario, setSelectedScenario] = useState(null);
    const [scenarioDetail, setScenarioDetail] = useState(null);
    const [loading, setLoading] = useState(false);
    const [detailLoading, setDetailLoading] = useState(false);
    const [error, setError] = useState(null);
    // 시나리오 목록 로드
    useEffect(() => {
        if (visible) {
            fetchScenarios();
            fetchCategories();
        }
    }, [visible]);
    // 선택된 시나리오 상세 정보 로드
    useEffect(() => {
        if (selectedScenario) {
            fetchScenarioDetail(selectedScenario.id);
        }
    }, [selectedScenario]);
    const fetchScenarios = async () => {
        setLoading(true);
        setError(null);
        try {
            const response = await axios.get('/cae/api/standard-scenarios/');
            setScenarios(response.data.scenarios || []);
        }
        catch (err) {
            setError(err?.response?.data?.error || '시나리오 목록을 불러오는데 실패했습니다.');
            console.error('Error fetching scenarios:', err);
        }
        finally {
            setLoading(false);
        }
    };
    const fetchCategories = async () => {
        try {
            const response = await axios.get('/cae/api/standard-scenarios/categories');
            setCategories([{ id: 'all', name: '전체' }, ...(response.data.categories || [])]);
        }
        catch (err) {
            console.error('Error fetching categories:', err);
        }
    };
    const fetchScenarioDetail = async (scenarioId) => {
        setDetailLoading(true);
        try {
            const response = await axios.get(`/cae/api/standard-scenarios/${scenarioId}`);
            setScenarioDetail(response.data.scenario);
        }
        catch (err) {
            console.error('Error fetching scenario detail:', err);
            setScenarioDetail(null);
        }
        finally {
            setDetailLoading(false);
        }
    };
    const handleScenarioClick = (scenario) => {
        setSelectedScenario(scenario);
    };
    const handleAddScenario = () => {
        if (scenarioDetail) {
            onSelect(scenarioDetail);
            handleClose();
        }
    };
    const handleClose = () => {
        setSelectedScenario(null);
        setScenarioDetail(null);
        setSelectedCategory('all');
        onClose();
    };
    // 카테고리 필터링
    const filteredScenarios = scenarios.filter(s => selectedCategory === 'all' || s.category === selectedCategory);
    // 카테고리 아이콘
    const getCategoryIcon = (category) => {
        switch (category) {
            case 'fall_test':
                return _jsx(FallOutlined, {});
            case 'cumulative_test':
                return _jsx(ThunderboltOutlined, {});
            case 'impact_test':
                return _jsx(ExperimentOutlined, {});
            case 'rotation_test':
                return _jsx(RotateRightOutlined, {});
            case 'attitude_test':
                return _jsx(SafetyOutlined, {});
            default:
                return _jsx(ExperimentOutlined, {});
        }
    };
    // 카테고리 색상
    const getCategoryColor = (category) => {
        switch (category) {
            case 'fall_test':
                return 'blue';
            case 'cumulative_test':
                return 'orange';
            case 'impact_test':
                return 'red';
            case 'rotation_test':
                return 'purple';
            case 'attitude_test':
                return 'green';
            default:
                return 'default';
        }
    };
    return (_jsxs(Modal, { title: "\uADDC\uACA9 \uC2DC\uB098\uB9AC\uC624 \uC120\uD0DD", open: visible, onCancel: handleClose, width: 1000, footer: [
            _jsx(Button, { onClick: handleClose, children: "\uCDE8\uC18C" }, "cancel"),
            _jsx(Button, { type: "primary", disabled: !scenarioDetail, onClick: handleAddScenario, icon: _jsx(CheckCircleOutlined, {}), children: "\uC2DC\uB098\uB9AC\uC624 \uCD94\uAC00" }, "submit")
        ], children: [error && (_jsx(Alert, { message: "\uC624\uB958", description: error, type: "error", closable: true, onClose: () => setError(null), style: { marginBottom: 16 } })), _jsx(Tabs, { activeKey: selectedCategory, onChange: setSelectedCategory, style: { marginBottom: 16 }, children: categories.map(cat => (_jsx(TabPane, { tab: cat.name }, cat.id))) }), _jsxs("div", { style: { display: 'flex', gap: '16px', minHeight: '500px' }, children: [_jsx("div", { style: { flex: 1, overflowY: 'auto', maxHeight: '500px' }, children: loading ? (_jsx("div", { style: { textAlign: 'center', padding: '50px' }, children: _jsx(Spin, { size: "large", tip: "\uC2DC\uB098\uB9AC\uC624 \uBAA9\uB85D\uC744 \uBD88\uB7EC\uC624\uB294 \uC911..." }) })) : filteredScenarios.length === 0 ? (_jsx(Empty, { description: "\uD45C\uC900 \uC2DC\uB098\uB9AC\uC624\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4" })) : (_jsx("div", { style: { display: 'grid', gap: '12px' }, children: filteredScenarios.map(scenario => (_jsx(Card, { hoverable: true, onClick: () => handleScenarioClick(scenario), style: {
                                    border: selectedScenario?.id === scenario.id ? '2px solid #1890ff' : '1px solid #d9d9d9',
                                    cursor: 'pointer'
                                }, bodyStyle: { padding: '12px' }, children: _jsx("div", { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'start' }, children: _jsxs("div", { style: { flex: 1 }, children: [_jsxs("div", { style: { display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }, children: [getCategoryIcon(scenario.category), _jsx("strong", { children: scenario.name })] }), _jsx("div", { style: { fontSize: '12px', color: '#666', marginBottom: '8px' }, children: scenario.description }), _jsxs("div", { style: { display: 'flex', gap: '8px', flexWrap: 'wrap' }, children: [_jsx(Tag, { color: getCategoryColor(scenario.category), style: { margin: 0 }, children: categories.find(c => c.id === scenario.category)?.name || scenario.category }), _jsxs(Tag, { color: "cyan", style: { margin: 0 }, children: ["\uD83D\uDCD0 ", scenario.angleCount, "\uAC1C \uAC01\uB3C4"] }), _jsxs(Tag, { color: "default", style: { margin: 0 }, children: ["v", scenario.version] })] })] }) }) }, scenario.id))) })) }), _jsx("div", { style: { flex: 1, borderLeft: '1px solid #d9d9d9', paddingLeft: '16px', overflowY: 'auto', maxHeight: '500px' }, children: detailLoading ? (_jsx("div", { style: { textAlign: 'center', padding: '50px' }, children: _jsx(Spin, { tip: "\uC0C1\uC138 \uC815\uBCF4\uB97C \uBD88\uB7EC\uC624\uB294 \uC911..." }) })) : scenarioDetail ? (_jsxs("div", { children: [_jsx("h3", { style: { marginBottom: '16px' }, children: scenarioDetail.name }), _jsxs(Descriptions, { bordered: true, size: "small", column: 1, style: { marginBottom: '16px' }, children: [_jsx(Descriptions.Item, { label: "\uC124\uBA85", children: scenarioDetail.description }), _jsx(Descriptions.Item, { label: "\uCE74\uD14C\uACE0\uB9AC", children: _jsx(Tag, { color: getCategoryColor(scenarioDetail.category), children: categories.find(c => c.id === scenarioDetail.category)?.name || scenarioDetail.category }) }), _jsx(Descriptions.Item, { label: "\uBC84\uC804", children: scenarioDetail.version }), _jsxs(Descriptions.Item, { label: "\uAC01\uB3C4 \uC218", children: [scenarioDetail.angles.length, "\uAC1C"] })] }), scenarioDetail.metadata && (_jsxs(_Fragment, { children: [scenarioDetail.metadata.standardReference && (_jsx(Descriptions, { bordered: true, size: "small", column: 1, style: { marginBottom: '8px' }, children: _jsx(Descriptions.Item, { label: "\uD45C\uC900 \uCC38\uC870", children: scenarioDetail.metadata.standardReference }) })), scenarioDetail.metadata.testMethod && (_jsx(Descriptions, { bordered: true, size: "small", column: 1, style: { marginBottom: '8px' }, children: _jsx(Descriptions.Item, { label: "\uC2DC\uD5D8 \uBC29\uBC95", children: scenarioDetail.metadata.testMethod }) })), scenarioDetail.metadata.requiredEquipment && scenarioDetail.metadata.requiredEquipment.length > 0 && (_jsxs("div", { style: { marginBottom: '8px' }, children: [_jsx("div", { style: { fontWeight: 'bold', marginBottom: '4px', fontSize: '12px' }, children: "\uD544\uC694 \uC7A5\uBE44:" }), _jsx("div", { style: { display: 'flex', flexWrap: 'wrap', gap: '4px' }, children: scenarioDetail.metadata.requiredEquipment.map((eq, idx) => (_jsx(Tag, { color: "blue", style: { margin: 0 }, children: eq }, idx))) })] })), scenarioDetail.metadata.safetyRequirements && scenarioDetail.metadata.safetyRequirements.length > 0 && (_jsxs("div", { style: { marginBottom: '8px' }, children: [_jsx("div", { style: { fontWeight: 'bold', marginBottom: '4px', fontSize: '12px' }, children: "\uC548\uC804 \uC694\uAD6C\uC0AC\uD56D:" }), _jsx("div", { style: { display: 'flex', flexWrap: 'wrap', gap: '4px' }, children: scenarioDetail.metadata.safetyRequirements.map((req, idx) => (_jsx(Tag, { color: "red", style: { margin: 0 }, children: req }, idx))) })] }))] })), _jsxs("div", { style: { marginTop: '16px' }, children: [_jsx("h4", { style: { marginBottom: '8px' }, children: "\uAC01\uB3C4 \uBAA9\uB85D:" }), _jsx("div", { style: { maxHeight: '200px', overflowY: 'auto' }, children: scenarioDetail.angles.map((angle, idx) => (_jsxs("div", { style: {
                                                    padding: '6px 8px',
                                                    marginBottom: '4px',
                                                    backgroundColor: '#f5f5f5',
                                                    borderRadius: '4px',
                                                    fontSize: '12px'
                                                }, children: [_jsx("strong", { children: angle.name }), ": \u03C6=", angle.phi, "\u00B0, \u03B8=", angle.theta, "\u00B0, \u03C8=", angle.psi, "\u00B0"] }, idx))) })] })] })) : (_jsx(Empty, { description: "\uC2DC\uB098\uB9AC\uC624\uB97C \uC120\uD0DD\uD558\uC138\uC694" })) })] })] }));
};
export default StandardScenarioModal;
