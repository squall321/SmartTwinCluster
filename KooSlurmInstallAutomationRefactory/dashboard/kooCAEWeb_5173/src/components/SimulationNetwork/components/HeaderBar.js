import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
// components/simulationnetwork/HeaderBar.tsx - Enhanced Version
import { useState, useMemo } from 'react';
import { Space, Select, Button, Input, Badge, Card, Row, Col, Typography, Tooltip, Divider, Dropdown, Switch } from 'antd';
import { SearchOutlined, FilterOutlined, ClearOutlined, DownloadOutlined, SettingOutlined, ReloadOutlined, PlayCircleOutlined, PauseCircleOutlined, EyeOutlined, EyeInvisibleOutlined, BarsOutlined } from '@ant-design/icons';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
import { ALL_STATUSES } from '../utils/statusUtils';
const { Text } = Typography;
const { Search } = Input;
// 🎨 Status configuration with colors and counts
const statusConfig = {
    Running: { color: '#1890ff', icon: '🔄' },
    Completed: { color: '#52c41a', icon: '✅' },
    Failed: { color: '#ff4d4f', icon: '❌' },
    Pending: { color: '#d9d9d9', icon: '⏳' },
    Cancelled: { color: '#faad14', icon: '⚠️' }
};
const HeaderBar = ({ onExport, onRefresh, showAnalysisPanel, onToggleAnalysisPanel }) => {
    // 🏪 Store state
    const { nodes, searchQuery, statusFilter, autoRefresh, setSearchQuery, setStatusFilter, toggleAutoRefresh } = useSimulationNetworkStore();
    // 🎛️ Local state
    const [showAdvancedFilters, setShowAdvancedFilters] = useState(false);
    const [selectedKinds, setSelectedKinds] = useState([]);
    // 📊 Calculate statistics
    const stats = useMemo(() => {
        const total = nodes.length;
        const statusCounts = nodes.reduce((acc, node) => {
            acc[node.status] = (acc[node.status] || 0) + 1;
            return acc;
        }, {});
        const kindCounts = nodes.reduce((acc, node) => {
            acc[node.kind] = (acc[node.kind] || 0) + 1;
            return acc;
        }, {});
        // Calculate filtered count
        let filteredCount = nodes.length;
        if (searchQuery || statusFilter.length > 0 || selectedKinds.length > 0) {
            const query = searchQuery.toLowerCase();
            filteredCount = nodes.filter(node => {
                const matchesSearch = !searchQuery ||
                    node.id.toLowerCase().includes(query) ||
                    node.label?.toLowerCase().includes(query) ||
                    node.path.toLowerCase().includes(query);
                const matchesStatus = statusFilter.length === 0 || statusFilter.includes(node.status);
                const matchesKind = selectedKinds.length === 0 || selectedKinds.includes(node.kind);
                return matchesSearch && matchesStatus && matchesKind;
            }).length;
        }
        return { total, statusCounts, kindCounts, filteredCount };
    }, [nodes, searchQuery, statusFilter, selectedKinds]);
    // 🎯 Event handlers
    const handleSearchChange = (value) => {
        setSearchQuery(value);
    };
    const handleStatusFilterChange = (values) => {
        setStatusFilter(values);
    };
    const handleClearFilters = () => {
        setSearchQuery('');
        setStatusFilter([]);
        setSelectedKinds([]);
    };
    const hasActiveFilters = searchQuery || statusFilter.length > 0 || selectedKinds.length > 0;
    // 📋 Settings dropdown menu
    const settingsMenu = {
        items: [
            {
                key: 'advanced-filters',
                label: (_jsxs(Space, { children: [_jsx(FilterOutlined, {}), "Advanced Filters"] })),
                onClick: () => setShowAdvancedFilters(!showAdvancedFilters)
            },
            {
                key: 'export',
                label: (_jsxs(Space, { children: [_jsx(DownloadOutlined, {}), "Export Data"] })),
                onClick: onExport,
                disabled: !onExport
            },
            { type: 'divider' },
            {
                key: 'auto-refresh',
                label: (_jsxs("div", { style: { display: 'flex', justifyContent: 'space-between', width: '100%' }, children: [_jsx("span", { children: "Auto Refresh" }), _jsx(Switch, { size: "small", checked: autoRefresh, onChange: toggleAutoRefresh })] }))
            }
        ]
    };
    return (_jsxs("div", { style: { marginBottom: '16px' }, children: [_jsxs(Card, { size: "small", style: { background: '#fafafa' }, children: [_jsxs(Row, { gutter: [16, 8], align: "middle", children: [_jsx(Col, { flex: "auto", children: _jsxs(Space, { size: "middle", wrap: true, children: [_jsx(Search, { placeholder: "Search by ID, label, or path...", value: searchQuery, onChange: (e) => handleSearchChange(e.target.value), onSearch: handleSearchChange, allowClear: true, style: { minWidth: 250 }, prefix: _jsx(SearchOutlined, {}) }), _jsx(Select, { mode: "multiple", allowClear: true, placeholder: "Filter by status", value: statusFilter.length ? statusFilter : undefined, onChange: handleStatusFilterChange, style: { minWidth: 180 }, optionLabelProp: "label", children: ALL_STATUSES.map(status => (_jsx(Select.Option, { value: status, label: _jsxs(Space, { children: [_jsx(Badge, { color: statusConfig[status].color }), status] }), children: _jsxs(Space, { children: [_jsx(Badge, { color: statusConfig[status].color }), _jsx("span", { children: status }), _jsxs(Text, { type: "secondary", children: ["(", stats.statusCounts[status] || 0, ")"] })] }) }, status))) }), hasActiveFilters && (_jsx(Tooltip, { title: "Clear all filters", children: _jsx(Button, { icon: _jsx(ClearOutlined, {}), onClick: handleClearFilters, size: "small", children: "Clear" }) })), hasActiveFilters && (_jsx(Badge, { count: stats.filteredCount, color: "#1890ff", children: _jsx(Text, { type: "secondary", children: "Filtered" }) }))] }) }), _jsx(Col, { children: _jsxs(Space, { size: "large", split: _jsx(Divider, { type: "vertical" }), children: [_jsxs(Space, { children: [_jsx(Text, { type: "secondary", children: "Total:" }), _jsx(Badge, { count: stats.total, color: "#722ed1" })] }), Object.entries(stats.statusCounts).map(([status, count]) => (count > 0 && (_jsxs(Space, { children: [_jsx(Text, { type: "secondary", children: statusConfig[status].icon }), _jsx(Badge, { count: count, color: statusConfig[status].color })] }, status))))] }) }), _jsx(Col, { children: _jsxs(Space, { children: [_jsx(Tooltip, { title: autoRefresh ? "Auto-refresh ON (1min)" : "Auto-refresh OFF", children: _jsx(Button, { type: autoRefresh ? "primary" : "default", icon: autoRefresh ? _jsx(PauseCircleOutlined, {}) : _jsx(PlayCircleOutlined, {}), onClick: toggleAutoRefresh, size: "small", children: autoRefresh ? "ON" : "OFF" }) }), _jsx(Tooltip, { title: "Refresh data", children: _jsx(Button, { icon: _jsx(ReloadOutlined, {}), onClick: onRefresh, size: "small" }) }), onToggleAnalysisPanel && (_jsx(Tooltip, { title: showAnalysisPanel ? "Hide Analysis Panel" : "Show Analysis Panel", children: _jsx(Button, { type: showAnalysisPanel ? "primary" : "default", icon: showAnalysisPanel ? _jsx(EyeInvisibleOutlined, {}) : _jsx(EyeOutlined, {}), onClick: onToggleAnalysisPanel, size: "small", children: "Analysis" }) })), _jsx(Dropdown, { menu: settingsMenu, trigger: ['click'], children: _jsx(Button, { icon: _jsx(SettingOutlined, {}), size: "small" }) })] }) })] }), showAdvancedFilters && (_jsxs(_Fragment, { children: [_jsx(Divider, { style: { margin: '12px 0' } }), _jsxs(Row, { gutter: [16, 8], align: "middle", children: [_jsx(Col, { span: 6, children: _jsx(Text, { strong: true, children: "Advanced Filters" }) }), _jsx(Col, { span: 18, children: _jsxs(Space, { wrap: true, children: [_jsx(Select, { mode: "multiple", allowClear: true, placeholder: "Filter by kind", value: selectedKinds, onChange: setSelectedKinds, style: { minWidth: 150 }, children: Object.entries(stats.kindCounts).map(([kind, count]) => (_jsx(Select.Option, { value: kind, children: _jsxs(Space, { children: [_jsx("span", { children: kind }), _jsxs(Text, { type: "secondary", children: ["(", count, ")"] })] }) }, kind))) }), _jsx(Button, { icon: _jsx(BarsOutlined, {}), size: "small", disabled: true, style: { opacity: 0.5 }, children: "More filters coming soon..." })] }) })] })] }))] }), hasActiveFilters && (_jsx(Card, { size: "small", style: { marginTop: '8px', background: '#e6f7ff' }, children: _jsxs(Row, { justify: "space-between", align: "middle", children: [_jsx(Col, { children: _jsxs(Text, { type: "secondary", children: ["Showing ", stats.filteredCount, " of ", stats.total, " cases", searchQuery && ` matching "${searchQuery}"`, statusFilter.length > 0 && ` with status: ${statusFilter.join(', ')}`, selectedKinds.length > 0 && ` of kind: ${selectedKinds.join(', ')}`] }) }), _jsx(Col, { children: _jsx(Button, { type: "link", size: "small", onClick: handleClearFilters, icon: _jsx(ClearOutlined, {}), children: "Clear all filters" }) })] }) }))] }));
};
export default HeaderBar;
