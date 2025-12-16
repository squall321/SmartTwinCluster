import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Card, Row, Col, Tooltip, Progress, Typography, Divider } from 'antd';
import { api } from '../api/axiosClient';
import BarChartComponent from '../components/BarChartComponent'; // 경로는 실제 위치에 따라 조정 필요
const { Title } = Typography;
const getUsageInfo = (load, total) => {
    const usage = load / total;
    if (usage < 0.3)
        return { color: '#52c41a', label: '낮음' };
    if (usage < 0.7)
        return { color: '#faad14', label: '중간' };
    return { color: '#f5222d', label: '높음' };
};
const RackViewerComponent = () => {
    const [rackData, setRackData] = useState({});
    const [userUsage, setUserUsage] = useState([]);
    const fetchRackData = async () => {
        try {
            const res = await api.get(`/api/rack-status`);
            setRackData({ ...res.data });
        }
        catch (error) {
            console.error('⚠️ 랙 데이터 요청 실패:', error);
        }
    };
    const fetchUserUsage = async () => {
        try {
            const res = await api.get(`/api/slurm/user-core-usage`);
            const sorted = res.data.sort((a, b) => b.cores - a.cores);
            setUserUsage(sorted);
        }
        catch (error) {
            console.error('⚠️ 유저 사용량 요청 실패:', error);
        }
    };
    useEffect(() => {
        fetchRackData();
        fetchUserUsage();
        const interval = setInterval(() => {
            fetchRackData();
            fetchUserUsage();
        }, 1000);
        return () => clearInterval(interval);
    }, []);
    return (_jsxs("div", { style: { padding: '40px 24px 24px', background: '#f0f2f5' }, children: [_jsx("div", { style: { display: 'flex', justifyContent: 'left', marginBottom: 24 }, children: _jsx(Typography.Title, { level: 3, style: { margin: 0 }, children: "\uD83D\uDCE1 \uD074\uB7EC\uC2A4\uD130 \uB799 \uC0C1\uD0DC \uBAA8\uB2C8\uD130\uB9C1" }) }), _jsx(Row, { gutter: [24, 24], wrap: true, justify: "start", children: Object.entries(rackData).map(([rack, nodes]) => (_jsx(Col, { children: _jsxs(Card, { title: _jsxs("span", { style: { fontWeight: 600 }, children: ["\uD83D\uDDC4\uFE0F ", rack] }), bordered: false, style: {
                            width: 280,
                            background: '#e6f7ff',
                            border: '2px solid #1890ff',
                            borderRadius: 12,
                            boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
                        }, bodyStyle: { padding: '12px 16px' }, children: [nodes.map((node) => {
                                const { color, label } = getUsageInfo(node.load, node.total);
                                const usagePercent = Math.round((node.load / node.total) * 100);
                                return (_jsx(Tooltip, { title: _jsxs(_Fragment, { children: [_jsx("div", { children: _jsx("strong", { children: node.name }) }), _jsxs("div", { children: ["\uCD1D \uCF54\uC5B4: ", node.total] }), _jsxs("div", { children: ["\uC0AC\uC6A9 \uC911: ", node.load.toFixed(1)] }), _jsxs("div", { children: ["\uC0AC\uC6A9\uB960: ", usagePercent, "% (", label, ")"] })] }), children: _jsxs("div", { style: {
                                            background: '#ffffff',
                                            border: `1px solid ${color}`,
                                            margin: '8px 0',
                                            padding: '6px 10px',
                                            borderRadius: 6,
                                            display: 'flex',
                                            alignItems: 'center',
                                            justifyContent: 'space-between',
                                            height: 38,
                                            boxShadow: `0 1px 3px ${color}44`,
                                            transition: 'all 0.3s',
                                        }, children: [_jsx("div", { style: {
                                                    fontSize: 13,
                                                    fontWeight: 500,
                                                    whiteSpace: 'nowrap',
                                                    overflow: 'hidden',
                                                    textOverflow: 'ellipsis',
                                                    marginRight: 10,
                                                    flex: 1,
                                                }, children: node.name }), _jsx(Progress, { percent: usagePercent, size: "small", status: "active", strokeColor: color, showInfo: false, style: { width: 120 } })] }) }, node.name));
                            }), _jsx(Divider, { style: { margin: '12px 0' } }), _jsxs("div", { style: { textAlign: 'right', fontSize: 12, color: '#888' }, children: ["\uCD1D \uB178\uB4DC: ", nodes.length] })] }) }, rack))) }), userUsage.length > 0 && (_jsxs("div", { style: { marginTop: 48 }, children: [_jsx(Typography.Title, { level: 4, children: "\uD83E\uDDD1\u200D\uD83D\uDCBB \uC720\uC800\uBCC4 \uCF54\uC5B4 \uC0AC\uC6A9\uB7C9" }), _jsx("div", { style: { width: '100%', height: 800 }, children: _jsx(BarChartComponent, { data: userUsage.map((u) => ({ name: u.user, number: u.cores })), title: "\uC720\uC800\uBCC4 \uC0AC\uC6A9\uB7C9", unitLabel: "\uCF54\uC5B4" }) })] }))] }));
};
export default RackViewerComponent;
