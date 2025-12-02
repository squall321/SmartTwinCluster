import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Switch } from 'antd';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
const AutoRefreshToggle = () => {
    const autoRefresh = useSimulationNetworkStore((state) => state.autoRefresh);
    const toggleAutoRefresh = useSimulationNetworkStore((state) => state.toggleAutoRefresh);
    return (_jsxs("div", { children: [_jsx(Switch, { checked: autoRefresh, onChange: toggleAutoRefresh }), _jsxs("span", { style: { marginLeft: 8 }, children: ["Auto Refresh ", autoRefresh ? '(1분마다)' : ''] })] }));
};
export default AutoRefreshToggle;
