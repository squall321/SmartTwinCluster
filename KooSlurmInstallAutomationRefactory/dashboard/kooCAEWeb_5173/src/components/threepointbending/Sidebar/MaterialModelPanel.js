import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import { Form, Select, InputNumber } from "antd";
import ModelFormulaBox from "../../common/ModelFormulaBox";
const MaterialModelPanel = ({ materialModel, setMaterialModel, materialParams, setMaterialParams }) => {
    const handleParamChange = (key, value) => {
        setMaterialParams({
            model: materialModel,
            params: {
                ...materialParams.params,
                [key]: value
            }
        });
    };
    return (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "Material Model", children: _jsx(Select, { value: materialModel, style: { width: "100%" }, onChange: (v) => {
                        setMaterialModel(v);
                        switch (v) {
                            case "LinearElastic":
                                setMaterialParams({
                                    model: v,
                                    params: { E: 200000 }
                                });
                                break;
                            case "PowerLaw":
                                setMaterialParams({
                                    model: v,
                                    params: {
                                        E: 200000,
                                        sigmaY: 250,
                                        K: 500,
                                        n: 0.2
                                    }
                                });
                                break;
                            case "RambergOsgood":
                                setMaterialParams({
                                    model: v,
                                    params: {
                                        E: 200000,
                                        sigma0: 250,
                                        K: 0.002,
                                        n: 5
                                    }
                                });
                                break;
                        }
                    }, options: [
                        { value: "LinearElastic", label: "Linear Elastic" },
                        { value: "PowerLaw", label: "Power Law Plasticity" },
                        { value: "RambergOsgood", label: "Ramberg-Osgood Plasticity" }
                    ] }) }), Object.entries(materialParams.params).map(([key, val]) => (_jsx(Form.Item, { label: key, children: _jsx(InputNumber, { value: val, onChange: (v) => handleParamChange(key, v || 0), style: { width: "100%" } }) }, key))), materialModel === "LinearElastic" && (_jsx(ModelFormulaBox, { title: "Linear Elastic", description: "\uC120\uD615 \uD0C4\uC131 \uC7AC\uB8CC \uBAA8\uB378\uC785\uB2C8\uB2E4.", formulas: [
                    "\\sigma = E \\cdot \\varepsilon"
                ] })), materialModel === "PowerLaw" && (_jsx(ModelFormulaBox, { title: "Power Law Plasticity", description: "\uD0C4\uC131 \uC774\uD6C4 \uC18C\uC131 \uC601\uC5ED\uC5D0\uC11C Power Law\uB97C \uC801\uC6A9\uD569\uB2C8\uB2E4.", formulas: [
                    "\\sigma = \\begin{cases} E \\cdot \\varepsilon & \\text{(Elastic)} \\\\ \\sigma_Y + K \\cdot \\varepsilon_p^n & \\text{(Plastic)} \\end{cases}"
                ] })), materialModel === "RambergOsgood" && (_jsx(ModelFormulaBox, { title: "Ramberg-Osgood Plasticity", description: "Ramberg-Osgood \uBAA8\uB378\uC740 \uD0C4\uC18C\uC131 \uBCC0\uD615\uC744 \uBD80\uB4DC\uB7FD\uAC8C \uD45C\uD604\uD569\uB2C8\uB2E4.", formulas: [
                    "\\varepsilon = \\frac{\\sigma}{E} + K \\left( \\frac{\\sigma}{\\sigma_0} \\right)^n"
                ] }))] }));
};
export default MaterialModelPanel;
