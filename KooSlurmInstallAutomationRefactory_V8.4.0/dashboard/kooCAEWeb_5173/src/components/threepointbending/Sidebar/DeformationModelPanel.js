import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Form, Radio } from "antd";
const DeformationModelPanel = ({ deformationModel, setDeformationModel }) => (_jsx(Form.Item, { label: "Deformation Model", children: _jsxs(Radio.Group, { value: deformationModel, onChange: (e) => setDeformationModel(e.target.value), children: [_jsx(Radio, { value: "Small", children: "Small Deformation" }), _jsx(Radio, { value: "Large", children: "Large Deformation" })] }) }));
export default DeformationModelPanel;
