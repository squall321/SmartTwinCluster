import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { Button, Space, Spin } from "antd";
const SimulationControls = ({ onRun, onReset, loading }) => (_jsxs(_Fragment, { children: [_jsxs(Space, { style: { marginTop: 16 }, children: [_jsx(Button, { type: "primary", onClick: onRun, disabled: loading, children: "Run Simulation" }), _jsx(Button, { danger: true, onClick: onReset, disabled: loading, children: "Reset" })] }), loading && (_jsx("div", { style: { marginTop: 16 }, children: _jsx(Spin, { tip: "Running simulation..." }) }))] }));
export default SimulationControls;
