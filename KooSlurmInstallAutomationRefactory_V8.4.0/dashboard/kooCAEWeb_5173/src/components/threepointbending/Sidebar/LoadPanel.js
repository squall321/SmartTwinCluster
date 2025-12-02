import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import { Form, InputNumber } from "antd";
const LoadPanel = ({ loadConfig, setLoadConfig }) => {
    const handleChange = (key, value) => {
        setLoadConfig({
            ...loadConfig,
            [key]: value
        });
    };
    return (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "Max Load (N)", children: _jsx(InputNumber, { value: loadConfig.maxLoad, onChange: (v) => handleChange("maxLoad", v || 0), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Step (N)", children: _jsx(InputNumber, { value: loadConfig.step, onChange: (v) => handleChange("step", v || 0), style: { width: "100%" } }) })] }));
};
export default LoadPanel;
