import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from "../../layouts/BaseLayout";
import FemMainRouter from "../../components/Theories/FEMStructuralAnalysis/FemMainRouter";
import { Typography } from "antd";
const { Title, Paragraph } = Typography;
const FEMStructuralAnalysisPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Computational Statics and Dynamics" }), _jsx(Paragraph, { children: "\uC720\uD55C\uC694\uC18C\uBC95\uC744 \uC774\uC6A9\uD55C \uAD6C\uC870\uD574\uC11D \uC774\uB860 \uC790\uB8CC\uC785\uB2C8\uB2E4." }), _jsx(FemMainRouter, {})] }) }));
};
export default FEMStructuralAnalysisPage;
