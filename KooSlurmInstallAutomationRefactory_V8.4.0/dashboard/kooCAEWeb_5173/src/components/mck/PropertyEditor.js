import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Card, Form, InputNumber } from 'antd';
const PropertyEditor = ({ selected, onChange, }) => {
    const handleChange = (field, value) => {
        if (!selected)
            return;
        const newData = { ...selected.data, [field]: value };
        onChange({ type: selected.type, data: newData });
    };
    return (_jsxs(Card, { title: "Property Editor", size: "small", bodyStyle: { padding: 12 }, style: { marginBottom: 10 }, children: [!selected && _jsx("p", { style: { margin: 0 }, children: "Nothing selected" }), selected?.type === 'mass' && (_jsx(Form, { layout: "inline", children: _jsx(Form.Item, { label: "Mass (kg)", style: { marginBottom: 0 }, children: _jsx(InputNumber, { min: 0, value: selected.data.m, size: "small", onChange: (v) => handleChange('m', v || 0) }) }) })), selected?.type === 'spring' && (_jsx(Form, { layout: "inline", children: _jsx(Form.Item, { label: "Stiffness (N/m)", style: { marginBottom: 0 }, children: _jsx(InputNumber, { min: 0, value: selected.data.k, size: "small", onChange: (v) => handleChange('k', v || 0) }) }) })), selected?.type === 'damper' && (_jsx(Form, { layout: "inline", children: _jsx(Form.Item, { label: "Damping (Ns/m)", style: { marginBottom: 0 }, children: _jsx(InputNumber, { min: 0, value: selected.data.c, size: "small", onChange: (v) => handleChange('c', v || 0) }) }) }))] }));
};
export default PropertyEditor;
