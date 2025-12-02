import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import { Form, Select, InputNumber } from "antd";
const AnalysisConditionPanel = ({ loadType, setLoadType, loadPosition, setLoadPosition, integrationSteps, setIntegrationSteps, supportCondition, setSupportCondition, span }) => {
    return (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "Support Condition", children: _jsx(Select, { value: supportCondition, onChange: setSupportCondition, options: [
                        { value: "SimplySupported", label: "Simply Supported" },
                        { value: "Cantilever", label: "Cantilever" }
                    ], style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Load Type", children: _jsx(Select, { value: loadType, onChange: setLoadType, options: [
                        { value: "Point", label: "Point Load" },
                        { value: "UDL", label: "Uniform Distributed Load" }
                    ], style: { width: "100%" } }) }), loadType === "Point" && (_jsx(Form.Item, { label: "Load Position (mm)", children: _jsx(InputNumber, { value: loadPosition, onChange: (v) => setLoadPosition(v || span / 2), style: { width: "100%" }, min: 0, max: span }) })), _jsx(Form.Item, { label: "Integration Steps", children: _jsx(InputNumber, { value: integrationSteps, onChange: (v) => setIntegrationSteps(v || 100), style: { width: "100%" }, min: 10, max: 1000 }) })] }));
};
export default AnalysisConditionPanel;
