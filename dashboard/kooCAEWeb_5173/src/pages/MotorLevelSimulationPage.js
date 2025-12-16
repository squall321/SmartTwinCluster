import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from "react";
import MotorLevelSimulationConfigForm from "../components/MotorLevelSimulationConfigForm";
import MotorLevelResultCharts from "../components/MotorLevelResultCharts";
import { runMotorLevelSimulation } from "../utils/motorLevelSimulation";
import { Typography, Row, Col } from "antd";
import BaseLayout from "../layouts/BaseLayout";
const { Title } = Typography;
const MotorLevelSimulationPage = () => {
    const [results, setResults] = useState(null);
    const runSimulation = (config) => {
        const result = runMotorLevelSimulation(config);
        setResults(result);
    };
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 2, children: "Motor Level Vibration Simulation" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 8, children: _jsx(MotorLevelSimulationConfigForm, { onRun: runSimulation }) }), _jsx(Col, { span: 16, children: results && _jsx(MotorLevelResultCharts, { results: results }) })] })] }) }));
};
export default MotorLevelSimulationPage;
