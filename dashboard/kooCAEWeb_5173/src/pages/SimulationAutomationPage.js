import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
//import SimulationNetwork from '../components/SimulationNetwork/SimulationNetwork';
import SimulationAutomationComponent from '../components/SimulationAutomation/SimulationAutomationComponent';
const { Title, Paragraph } = Typography;
const SimulationAutomationPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uC815\uADDC \uCC28\uC218 \uC2DC\uBBAC\uB808\uC774\uC158 \uC790\uB3D9\uD654" }), _jsx(Paragraph, { children: "\uAC1C\uBC1C \uD504\uB85C\uC138\uC2A4\uC758 \uC815\uADDC \uCC28\uC218 \uC2DC\uBBAC\uB808\uC774\uC158\uC744 \uC790\uB3D9\uD654\uD569\uB2C8\uB2E4." }), _jsx(SimulationAutomationComponent, {})] }) }));
};
export default SimulationAutomationPage;
