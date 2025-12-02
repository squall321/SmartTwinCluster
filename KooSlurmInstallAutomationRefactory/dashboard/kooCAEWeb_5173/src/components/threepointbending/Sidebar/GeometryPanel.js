import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import { Form, InputNumber } from "antd";
const GeometryPanel = ({ geometry, setGeometry }) => {
    const handleChange = (key, value) => {
        setGeometry({
            ...geometry,
            [key]: value
        });
    };
    return (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "Span (mm)", children: _jsx(InputNumber, { value: geometry.span, onChange: (v) => handleChange("span", v || 0), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Height (mm)", children: _jsx(InputNumber, { value: geometry.height, onChange: (v) => handleChange("height", v || 0), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Width (mm)", children: _jsx(InputNumber, { value: geometry.width, onChange: (v) => handleChange("width", v || 0), style: { width: "100%" } }) })] }));
};
export default GeometryPanel;
