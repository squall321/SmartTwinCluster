import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// components/simulationnetwork/SimulationNetwork.tsx - Enhanced Version
import React, { useEffect, useCallback, useState, useRef } from 'react';
import { useSimulationNetworkStore } from './store/simulationnetworkStore';
import HeaderBar from './components/HeaderBar';
import GraphView from './components/GraphView';
import NodeDrawer from './components/NodeDrawer';
import StatusLegend from './components/StatusLegend';
import SimulationStatusTable from './components/SimulationStatusTable';
import DebugPanel from './components/DebugPanel';
import AnalysisPanel from './components/analysis/AnalysisPanel';
import { api } from '../../api/axiosClient';
import { Space, Tag, Typography, Spin, Divider, Tabs, Alert, Button, Card, Row, Col, notification } from 'antd';
import { PartitionOutlined, TableOutlined, BugOutlined, BarChartOutlined, ReloadOutlined, ExclamationCircleOutlined, CheckCircleOutlined } from '@ant-design/icons';
const { Text, Title } = Typography;
// 데이터 해시 생성 함수
const generateDataHash = (data) => {
    return JSON.stringify(data).length.toString() + '_' + JSON.stringify(data).slice(0, 100);
};
const SimulationNetwork = () => {
    const autoRefresh = useSimulationNetworkStore(state => state.autoRefresh);
    const setNodes = useSimulationNetworkStore(state => state.setNodes);
    const nodes = useSimulationNetworkStore(state => state.nodes);
    const intervalRef = useRef(null);
    // 🔹 Enhanced state management
    const [projects, setProjects] = useState([]);
    const [loadingProjects, setLoadingProjects] = useState(false);
    const [loadingGraph, setLoadingGraph] = useState(false);
    const [activeTab, setActiveTab] = useState('network');
    const [showAnalysisPanel, setShowAnalysisPanel] = useState(false);
    const [lastUpdateTime, setLastUpdateTime] = useState(null);
    const [dataHash, setDataHash] = useState('');
    const [connectionStatus, setConnectionStatus] = useState('connected');
    const [errorMessage, setErrorMessage] = useState(null);
    // 📊 Statistics
    const stats = React.useMemo(() => {
        const total = nodes.length;
        const statusCounts = nodes.reduce((acc, node) => {
            acc[node.status] = (acc[node.status] || 0) + 1;
            return acc;
        }, {});
        return { total, statusCounts };
    }, [nodes]);
    // 🔄 Load projects with error handling
    const loadProjects = useCallback(async () => {
        try {
            setLoadingProjects(true);
            setConnectionStatus('connected');
            const { data } = await api.get('/api/proxy/automation/api/simulation-automation/projects');
            setProjects(Array.isArray(data?.projects) ? data.projects : []);
            console.log('[SimulationNetwork] Projects loaded:', data?.projects?.length || 0);
        }
        catch (e) {
            console.error('[SimulationNetwork] Failed to load projects:', e);
            setProjects([]);
            setConnectionStatus('error');
            setErrorMessage('Failed to connect to simulation automation service');
        }
        finally {
            setLoadingProjects(false);
        }
    }, []);
    // 🔄 Enhanced graph data loading
    const loadGraphData = useCallback(async (forceUpdate = false) => {
        try {
            setLoadingGraph(true);
            setConnectionStatus('connected');
            setErrorMessage(null);
            console.log('[SimulationNetwork] Loading graph data... (forceUpdate:', forceUpdate, ')');
            const url = `/api/proxy/automation/api/simulation-automation/simulationnetwork`;
            const { data } = await api.get(url);
            // Check if data actually changed
            const newHash = generateDataHash(data);
            if (!forceUpdate && newHash === dataHash) {
                console.log('[SimulationNetwork] Data unchanged, skipping update');
                return;
            }
            console.log('[SimulationNetwork] Data loaded, updating...');
            // API 응답 구조 확인 및 처리
            const nodes = data?.nodes || [];
            const edges = data?.edges || [];
            console.log('[SimulationNetwork] Found nodes:', nodes.length, 'edges:', edges.length);
            if (nodes.length > 0 || edges.length > 0) {
                setNodes(nodes, edges);
                setDataHash(newHash);
                setLastUpdateTime(new Date());
                console.log('[SimulationNetwork] Nodes updated in store');
                // Show success notification for manual refresh
                if (forceUpdate) {
                    notification.success({
                        message: 'Data Updated',
                        description: `Loaded ${nodes.length} nodes and ${edges.length} edges`,
                        duration: 3
                    });
                }
            }
            else {
                console.warn('[SimulationNetwork] No nodes or edges found in response');
                console.log('[SimulationNetwork] Response structure:', Object.keys(data || {}));
                if (forceUpdate) {
                    notification.warning({
                        message: 'No Data Found',
                        description: 'No simulation network data available',
                        duration: 3
                    });
                }
            }
        }
        catch (error) {
            console.error('[SimulationNetwork] Error loading simulation network data:', error);
            setConnectionStatus('error');
            setErrorMessage('Failed to load simulation data');
            if (forceUpdate) {
                notification.error({
                    message: 'Load Failed',
                    description: 'Unable to fetch simulation network data',
                    duration: 5
                });
            }
        }
        finally {
            setLoadingGraph(false);
        }
    }, [setNodes, dataHash]);
    // 🎯 Manual refresh handler
    const handleManualRefresh = useCallback(() => {
        console.log('[SimulationNetwork] Manual refresh triggered');
        loadProjects();
        loadGraphData(true);
    }, [loadProjects, loadGraphData]);
    // 🎯 Export data handler
    const handleExportData = useCallback(() => {
        try {
            const exportData = {
                timestamp: new Date().toISOString(),
                projects,
                nodes,
                statistics: stats
            };
            const dataStr = JSON.stringify(exportData, null, 2);
            const dataBlob = new Blob([dataStr], { type: 'application/json' });
            const url = URL.createObjectURL(dataBlob);
            const link = document.createElement('a');
            link.href = url;
            link.download = `simulation-network-${new Date().getTime()}.json`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
            notification.success({
                message: 'Export Successful',
                description: 'Simulation network data exported successfully',
                duration: 3
            });
        }
        catch (error) {
            notification.error({
                message: 'Export Failed',
                description: 'Failed to export simulation network data',
                duration: 5
            });
        }
    }, [projects, nodes, stats]);
    // 🔄 Initial loading
    useEffect(() => {
        console.log('[SimulationNetwork] Component mounted, starting initial load');
        loadProjects();
        loadGraphData(true);
    }, [loadProjects, loadGraphData]);
    // 🔄 Auto-refresh logic with enhanced error handling
    useEffect(() => {
        if (intervalRef.current) {
            clearInterval(intervalRef.current);
            intervalRef.current = null;
        }
        if (!autoRefresh) {
            console.log('[SimulationNetwork] Auto-refresh disabled');
            return;
        }
        console.log('[SimulationNetwork] Setting up auto-refresh (60 seconds)');
        intervalRef.current = setInterval(() => {
            console.log('[SimulationNetwork] Auto-refresh triggered');
            loadGraphData();
        }, 60000); // 60초 = 1분
        return () => {
            if (intervalRef.current) {
                clearInterval(intervalRef.current);
                intervalRef.current = null;
            }
        };
    }, [autoRefresh, loadGraphData]);
    // 🧹 Cleanup on unmount
    useEffect(() => {
        return () => {
            if (intervalRef.current) {
                clearInterval(intervalRef.current);
                intervalRef.current = null;
            }
        };
    }, []);
    // 🎨 Enhanced tab items
    const tabItems = [
        {
            key: 'network',
            label: (_jsxs("span", { children: [_jsx(PartitionOutlined, {}), "Network Graph", loadingGraph && _jsx(Spin, { size: "small", style: { marginLeft: 8 } })] })),
            children: (_jsxs("div", { children: [_jsx(HeaderBar, { onRefresh: handleManualRefresh, onExport: handleExportData, showAnalysisPanel: showAnalysisPanel, onToggleAnalysisPanel: () => setShowAnalysisPanel(!showAnalysisPanel) }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: showAnalysisPanel ? 16 : 24, children: _jsxs("div", { style: { position: 'relative', height: '75vh', border: '1px solid #f0f0f0', borderRadius: '8px' }, children: [_jsx(GraphView, {}), _jsx("div", { style: {
                                                position: 'absolute',
                                                bottom: 8,
                                                right: 8,
                                                background: 'white',
                                                padding: '4px 8px',
                                                borderRadius: 4,
                                                boxShadow: '0 0 4px rgba(0,0,0,0.15)',
                                            }, children: _jsx(StatusLegend, {}) })] }) }), showAnalysisPanel && (_jsx(Col, { span: 8, children: _jsx(Card, { title: "Quick Analysis", size: "small", style: { height: '75vh', overflow: 'auto' }, extra: _jsx(Button, { type: "text", size: "small", onClick: () => setShowAnalysisPanel(false), children: "\u00D7" }), children: _jsx(AnalysisPanel, {}) }) }))] }), _jsx(NodeDrawer, {})] })),
        },
        {
            key: 'table',
            label: (_jsxs("span", { children: [_jsx(TableOutlined, {}), "Status Table"] })),
            children: _jsx(SimulationStatusTable, {}),
        },
        {
            key: 'analysis',
            label: (_jsxs("span", { children: [_jsx(BarChartOutlined, {}), "Analysis Dashboard"] })),
            children: _jsx(AnalysisPanel, {}),
        },
        {
            key: 'debug',
            label: (_jsxs("span", { children: [_jsx(BugOutlined, {}), "Debug Info"] })),
            children: _jsx(DebugPanel, {}),
        },
    ];
    return (_jsxs("div", { style: { minHeight: '100vh', background: '#f5f5f5' }, children: [_jsx(Card, { style: { margin: '0 0 16px 0', borderRadius: '0' }, children: _jsxs(Row, { justify: "space-between", align: "middle", children: [_jsx(Col, { flex: "auto", children: _jsxs(Space, { align: "center", wrap: true, children: [_jsxs(Title, { level: 4, style: { margin: 0 }, children: [_jsx(PartitionOutlined, { style: { color: '#1890ff' } }), "Simulation Automation Network"] }), _jsx(Tag, { color: connectionStatus === 'connected' ? 'green' : connectionStatus === 'error' ? 'red' : 'orange', icon: connectionStatus === 'connected' ? _jsx(CheckCircleOutlined, {}) : _jsx(ExclamationCircleOutlined, {}), children: connectionStatus.toUpperCase() }), _jsx(Text, { type: "secondary", children: "Projects:" }), loadingProjects ? (_jsx(Spin, { size: "small" })) : projects.length ? (projects.map(p => (_jsx(Tag, { color: "blue", children: p }, p)))) : (_jsx(Tag, { color: "default", children: "No projects" })), _jsx(Divider, { type: "vertical" }), _jsxs(Space, { children: [_jsx(Text, { type: "secondary", children: "Total Cases:" }), _jsx(Tag, { color: "purple", children: stats.total }), Object.entries(stats.statusCounts).map(([status, count]) => (_jsxs(Tag, { color: getStatusColor(status), children: [status, ": ", count] }, status)))] })] }) }), _jsx(Col, { children: _jsxs(Space, { children: [lastUpdateTime && (_jsxs(Text, { type: "secondary", style: { fontSize: 12 }, children: ["Updated: ", lastUpdateTime.toLocaleTimeString()] })), _jsxs(Text, { type: "secondary", style: { fontSize: 12 }, children: ["Auto-refresh: ", autoRefresh ? (_jsx(Text, { type: "success", children: "ON (1min)" })) : (_jsx(Text, { type: "warning", children: "OFF" }))] }), _jsx(Button, { icon: _jsx(ReloadOutlined, {}), onClick: handleManualRefresh, loading: loadingGraph || loadingProjects, size: "small", children: "Refresh" })] }) })] }) }), errorMessage && (_jsx(Alert, { message: "Connection Error", description: errorMessage, type: "error", showIcon: true, closable: true, onClose: () => setErrorMessage(null), style: { margin: '0 16px 16px 16px' }, action: _jsx(Button, { size: "small", onClick: handleManualRefresh, children: "Retry" }) })), _jsx("div", { style: { padding: '0 16px' }, children: _jsx(Tabs, { activeKey: activeTab, onChange: setActiveTab, items: tabItems, size: "large", type: "card", style: { background: 'white', borderRadius: '8px' } }) })] }));
};
// 🎨 Helper function for status colors
function getStatusColor(status) {
    switch (status.toLowerCase()) {
        case 'running': return 'blue';
        case 'completed': return 'green';
        case 'failed': return 'red';
        case 'pending': return 'default';
        case 'cancelled': return 'orange';
        default: return 'default';
    }
}
export default SimulationNetwork;
