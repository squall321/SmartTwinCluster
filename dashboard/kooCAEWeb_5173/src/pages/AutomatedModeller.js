import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Select, Space } from 'antd';
import StreamRunner from '../components/StreamRunner';
const { Title, Paragraph } = Typography;
const { Option } = Select;
const AutomatedModeller = () => {
    let solver = "AutomatedModeller";
    const [mode, setMode] = useState(null);
    const handleModeChange = (value) => {
        setMode(value);
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [solver === "AutomatedModeller" && _jsx(Title, { level: 3, children: "\uD83D\uDCE6 Automated Modeller" }), _jsx(Paragraph, { children: "\uC2DC\uBBAC\uB808\uC774\uC158 \uBAA8\uB378\uC744 \uC790\uB3D9\uC73C\uB85C \uC0DD\uC131\uD569\uB2C8\uB2E4." }), _jsx(Space, { direction: "vertical", style: { marginBottom: 16 }, children: _jsxs(Select, { placeholder: "\uBAA8\uB4DC\uB97C \uC120\uD0DD\uD558\uC138\uC694", style: { width: 200 }, onChange: handleModeChange, value: mode, children: [_jsx(Option, { value: "PKG", children: "PKG" }), _jsx(Option, { value: "PBA", children: "PBA" }), _jsx(Option, { value: "ArrayPCB", children: "ArrayPCB" }), _jsx(Option, { value: "CAP", children: "CAP" })] }) }), _jsx(StreamRunner, { solver: solver, mode: mode })] }) }));
};
export default AutomatedModeller;
