import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Button, InputNumber, Form, Row, Col, Card } from "antd";
const MotorLevelSimulationConfigForm = ({ onRun }) => {
    const [form] = Form.useForm();
    const defaultConfig = {
        r_P_global_0: [0.54667, 80.96126, -4.04957],
        r_Q_global: [10.0, 30.0, 0.0],
        xvector: [0.00827, 0.00453, 0.99996],
        yvector: [0.99986, 0.01476, -0.00833],
        zvector: [-0.01480, 0.99988, -0.00441],
        I_principal: [526.62083, 426.54252, 102.66056],
        m: 0.2018,
        mu: 0.4,
        g: 9.81,
        width: 77.856,
        height: 163.368,
        thickness: 7.94,
        dt: 0.001,
        duration: 0.1,
        freq: 157.0,
        F0: 350,
        gridX: 20,
        gridY: 20,
        forceDirection: [1, 0.3, 0],
    };
    const onFinish = (values) => {
        const merged = {
            ...defaultConfig,
            ...values,
            r_P_global_0: [
                values.r_P_global_0_0,
                values.r_P_global_0_1,
                values.r_P_global_0_2,
            ],
            r_Q_global: [
                values.r_Q_global_0,
                values.r_Q_global_1,
                values.r_Q_global_2,
            ],
            xvector: [
                values.xvector_0,
                values.xvector_1,
                values.xvector_2,
            ],
            yvector: [
                values.yvector_0,
                values.yvector_1,
                values.yvector_2,
            ],
            zvector: [
                values.zvector_0,
                values.zvector_1,
                values.zvector_2,
            ],
            I_principal: [
                values.I_principal_0,
                values.I_principal_1,
                values.I_principal_2,
            ],
            forceDirection: [
                values.forceDirection_0,
                values.forceDirection_1,
                values.forceDirection_2,
            ],
        };
        onRun(merged);
    };
    return (_jsxs(Form, { layout: "vertical", form: form, initialValues: {
            ...defaultConfig,
            r_P_global_0_0: defaultConfig.r_P_global_0[0],
            r_P_global_0_1: defaultConfig.r_P_global_0[1],
            r_P_global_0_2: defaultConfig.r_P_global_0[2],
            r_Q_global_0: defaultConfig.r_Q_global[0],
            r_Q_global_1: defaultConfig.r_Q_global[1],
            r_Q_global_2: defaultConfig.r_Q_global[2],
            xvector_0: defaultConfig.xvector[0],
            xvector_1: defaultConfig.xvector[1],
            xvector_2: defaultConfig.xvector[2],
            yvector_0: defaultConfig.yvector[0],
            yvector_1: defaultConfig.yvector[1],
            yvector_2: defaultConfig.yvector[2],
            zvector_0: defaultConfig.zvector[0],
            zvector_1: defaultConfig.zvector[1],
            zvector_2: defaultConfig.zvector[2],
            I_principal_0: defaultConfig.I_principal[0],
            I_principal_1: defaultConfig.I_principal[1],
            I_principal_2: defaultConfig.I_principal[2],
            forceDirection_0: 1,
            forceDirection_1: 0.3,
            forceDirection_2: 0,
        }, onFinish: onFinish, children: [_jsx(Card, { size: "small", title: "Simulation Settings", style: { marginBottom: 16 }, children: _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Duration (s)", name: "duration", children: _jsx(InputNumber, { step: 0.01, min: 0.01, style: { width: "100%" } }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Time Step dt (s)", name: "dt", children: _jsx(InputNumber, { step: 0.0001, min: 0.0001, style: { width: "100%" } }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Frequency (Hz)", name: "freq", children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Force F0 (mN)", name: "F0", children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Grid X", name: "gridX", children: _jsx(InputNumber, { min: 5, max: 200, style: { width: "100%" } }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Grid Y", name: "gridY", children: _jsx(InputNumber, { min: 5, max: 200, style: { width: "100%" } }) }) })] }) }), _jsx(Card, { size: "small", title: "Force Direction", style: { marginBottom: 16 }, children: _jsx(Row, { gutter: 8, children: ["X", "Y", "Z"].map((axis, i) => (_jsx(Col, { span: 8, children: _jsx(Form.Item, { label: axis, name: `forceDirection_${i}`, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }, axis))) }) }), _jsx(Card, { size: "small", title: "Geometry", style: { marginBottom: 16 }, children: _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Width (mm)", name: "width", children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Height (mm)", name: "height", children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 24, children: _jsx(Form.Item, { label: "Thickness (mm)", name: "thickness", children: _jsx(InputNumber, { style: { width: "100%" } }) }) })] }) }), _jsx(Card, { size: "small", title: "Material Properties", style: { marginBottom: 16 }, children: _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 8, children: _jsx(Form.Item, { label: "Mass (kg)", name: "m", children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { label: "\u03BC (Friction)", name: "mu", children: _jsx(InputNumber, { style: { width: "100%" }, step: 0.01, min: 0 }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { label: "Gravity (m/s\u00B2)", name: "g", children: _jsx(InputNumber, { style: { width: "100%" }, step: 0.01, min: 0 }) }) })] }) }), _jsx(Card, { size: "small", title: "Position Vectors", style: { marginBottom: 16 }, children: _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 24, children: _jsx(Form.Item, { label: "P0 (X, Y, Z)", children: _jsxs(Row, { gutter: 8, children: [_jsx(Col, { span: 8, children: _jsx(Form.Item, { name: "r_P_global_0_0", noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { name: "r_P_global_0_1", noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { name: "r_P_global_0_2", noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) })] }) }) }), _jsx(Col, { span: 24, children: _jsx(Form.Item, { label: "Q (X, Y, Z)", children: _jsxs(Row, { gutter: 8, children: [_jsx(Col, { span: 8, children: _jsx(Form.Item, { name: "r_Q_global_0", noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { name: "r_Q_global_1", noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { name: "r_Q_global_2", noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) })] }) }) })] }) }), _jsx(Card, { size: "small", title: "Vectors", style: { marginBottom: 16 }, children: ["xvector", "yvector", "zvector", "I_principal"].map((vector) => (_jsx(Row, { gutter: 8, style: { marginBottom: 8 }, children: _jsx(Col, { span: 24, children: _jsx(Form.Item, { label: `${vector} (X, Y, Z)`, children: _jsxs(Row, { gutter: 8, children: [_jsx(Col, { span: 8, children: _jsx(Form.Item, { name: `${vector}_0`, noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { name: `${vector}_1`, noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { name: `${vector}_2`, noStyle: true, children: _jsx(InputNumber, { style: { width: "100%" } }) }) })] }) }) }) }, vector))) }), _jsx(Button, { htmlType: "submit", type: "primary", block: true, children: "Run Motor Level Simulation" })] }));
};
export default MotorLevelSimulationConfigForm;
