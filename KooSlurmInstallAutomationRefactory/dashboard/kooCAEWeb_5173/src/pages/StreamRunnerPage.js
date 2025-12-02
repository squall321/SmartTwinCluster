import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useLocation } from 'react-router-dom';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import StreamRunner from '../components/StreamRunner';
const { Title, Paragraph } = Typography;
const StreamRunnerPage = () => {
    const location = useLocation();
    const state = location.state || {};
    const solver = state.solver ?? "MeshModifier";
    const mode = state.mode ?? null;
    const txtFiles = state.txtFiles ?? [];
    const optFiles = state.optFiles ?? [];
    const autoSubmit = state.autoSubmit ?? false;
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [solver === "MeshModifier" && _jsx(Title, { level: 3, children: "\uD83D\uDCE6 Mesh Modifier" }), solver === "AutomatedModeller" && _jsx(Title, { level: 3, children: "\uD83D\uDCE6 Automated Modeller" }), _jsx(Paragraph, { children: "\uC2DC\uBBAC\uB808\uC774\uC158 \uBAA8\uB378\uC5D0 \uB300\uD55C \uACA9\uC790 \uC218\uC815\uC744 \uC704\uD55C \uC790\uB3D9\uD654 \uCF54\uB4DC\uB97C \uC218\uD589\uD569\uB2C8\uB2E4." }), _jsx(StreamRunner, { solver: solver, mode: mode, txtFiles: txtFiles, optFiles: optFiles, autoSubmit: autoSubmit })] }) }));
};
export default StreamRunnerPage;
