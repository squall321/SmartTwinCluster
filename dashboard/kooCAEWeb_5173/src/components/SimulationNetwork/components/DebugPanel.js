import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// components/DebugPanel.tsx
import { useState } from 'react';
import { Card, Button, Space, Typography, Collapse, Tag } from 'antd';
import { BugOutlined, ReloadOutlined } from '@ant-design/icons';
import { api } from '../../../api/axiosClient';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
const { Title, Text, Paragraph } = Typography;
const { Panel } = Collapse;
const DebugPanel = () => {
    const [apiResponse, setApiResponse] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const nodes = useSimulationNetworkStore(state => state.nodes);
    const edges = useSimulationNetworkStore(state => state.edges);
    const testApiCall = async () => {
        setLoading(true);
        setError(null);
        try {
            console.log('🔍 Testing API call...');
            const url = `/api/proxy/automation/api/simulation-automation/simulationnetwork`;
            const response = await api.post(url);
            console.log('✅ API Response:', response);
            setApiResponse(response.data);
            // 응답 구조 분석
            const data = response.data;
            console.log('📊 Response Analysis:');
            console.log('- Response type:', typeof data);
            console.log('- Has nodes?', 'nodes' in data, Array.isArray(data?.nodes));
            console.log('- Has edges?', 'edges' in data, Array.isArray(data?.edges));
            console.log('- Nodes count:', data?.nodes?.length || 0);
            console.log('- Edges count:', data?.edges?.length || 0);
            if (data?.nodes?.length > 0) {
                console.log('- First node sample:', data.nodes[0]);
            }
            if (data?.edges?.length > 0) {
                console.log('- First edge sample:', data.edges[0]);
            }
        }
        catch (err) {
            console.error('❌ API Error:', err);
            setError(err.message || 'Unknown error');
        }
        finally {
            setLoading(false);
        }
    };
    const renderApiResponse = () => {
        if (!apiResponse)
            return _jsx(Text, { type: "secondary", children: "No API response yet" });
        return (_jsxs("div", { children: [_jsxs(Paragraph, { children: [_jsx(Text, { strong: true, children: "Response Type:" }), " ", typeof apiResponse] }), _jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsxs("div", { children: [_jsx(Text, { strong: true, children: "Has nodes: " }), _jsx(Tag, { color: Array.isArray(apiResponse?.nodes) ? 'green' : 'red', children: Array.isArray(apiResponse?.nodes) ? 'Yes' : 'No' }), Array.isArray(apiResponse?.nodes) && (_jsxs(Tag, { color: "blue", children: ["Count: ", apiResponse.nodes.length] }))] }), _jsxs("div", { children: [_jsx(Text, { strong: true, children: "Has edges: " }), _jsx(Tag, { color: Array.isArray(apiResponse?.edges) ? 'green' : 'red', children: Array.isArray(apiResponse?.edges) ? 'Yes' : 'No' }), Array.isArray(apiResponse?.edges) && (_jsxs(Tag, { color: "blue", children: ["Count: ", apiResponse.edges.length] }))] })] }), _jsxs(Collapse, { style: { marginTop: 16 }, children: [_jsx(Panel, { header: "Raw Response", children: _jsx("pre", { style: {
                                    background: '#f5f5f5',
                                    padding: '12px',
                                    borderRadius: '4px',
                                    maxHeight: '300px',
                                    overflow: 'auto',
                                    fontSize: '12px'
                                }, children: JSON.stringify(apiResponse, null, 2) }) }, "raw"), apiResponse?.nodes?.length > 0 && (_jsx(Panel, { header: "Sample Node", children: _jsx("pre", { style: {
                                    background: '#f5f5f5',
                                    padding: '12px',
                                    borderRadius: '4px',
                                    fontSize: '12px'
                                }, children: JSON.stringify(apiResponse.nodes[0], null, 2) }) }, "node")), apiResponse?.edges?.length > 0 && (_jsx(Panel, { header: "Sample Edge", children: _jsx("pre", { style: {
                                    background: '#f5f5f5',
                                    padding: '12px',
                                    borderRadius: '4px',
                                    fontSize: '12px'
                                }, children: JSON.stringify(apiResponse.edges[0], null, 2) }) }, "edge"))] })] }));
    };
    const renderStoreState = () => (_jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsxs("div", { children: [_jsx(Text, { strong: true, children: "Store Nodes: " }), _jsxs(Tag, { color: nodes.length > 0 ? 'green' : 'orange', children: [nodes.length, " nodes"] })] }), _jsxs("div", { children: [_jsx(Text, { strong: true, children: "Store Edges: " }), _jsxs(Tag, { color: edges.length > 0 ? 'green' : 'orange', children: [edges.length, " edges"] })] }), nodes.length > 0 && (_jsx(Collapse, { children: _jsx(Panel, { header: "Sample Store Node", children: _jsx("pre", { style: {
                            background: '#f5f5f5',
                            padding: '12px',
                            borderRadius: '4px',
                            fontSize: '12px'
                        }, children: JSON.stringify(nodes[0], null, 2) }) }, "store-node") }))] }));
    return (_jsxs("div", { style: { padding: '16px' }, children: [_jsxs(Title, { level: 3, children: [_jsx(BugOutlined, {}), " API Debug Panel"] }), _jsxs(Space, { direction: "vertical", style: { width: '100%' }, size: "large", children: [_jsxs(Card, { title: "API Test", extra: _jsx(Button, { type: "primary", icon: _jsx(ReloadOutlined, {}), onClick: testApiCall, loading: loading, children: "Test API" }), children: [error && (_jsx("div", { style: { marginBottom: 16 }, children: _jsxs(Text, { type: "danger", children: ["Error: ", error] }) })), renderApiResponse()] }), _jsx(Card, { title: "Store State", children: renderStoreState() }), _jsxs(Card, { title: "Debugging Steps", children: [_jsxs("ol", { children: [_jsxs("li", { children: [_jsx(Text, { strong: true, children: "Step 1:" }), " Click \"Test API\" to see raw API response"] }), _jsxs("li", { children: [_jsx(Text, { strong: true, children: "Step 2:" }), " Check if response has proper \"nodes\" and \"edges\" arrays"] }), _jsxs("li", { children: [_jsx(Text, { strong: true, children: "Step 3:" }), " Verify store state is updated after API call"] }), _jsxs("li", { children: [_jsx(Text, { strong: true, children: "Step 4:" }), " Check browser console for detailed logs"] })] }), _jsx("div", { style: { marginTop: 16, padding: '12px', background: '#f6f8fa', borderRadius: '4px' }, children: _jsxs(Text, { type: "secondary", children: [_jsx("strong", { children: "Expected API Response Format:" }), _jsx("br", {}), `{ "nodes": [...], "edges": [...] }`] }) })] })] })] }));
};
export default DebugPanel;
