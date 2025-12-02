import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from "../../layouts/BaseLayout";
import PDEFEMMainRouter from "../../components/Theories/FiniteElementMethod/PDEFEMMainRouter";
import { Typography } from "antd";
const { Title, Paragraph } = Typography;
const PDEFEMPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Partial Differential Equation" }), _jsx(Paragraph, { children: "\uD3B8\uBBF8\uBD84\uBC29\uC815\uC2DD\uC758 \uC720\uD55C\uC694\uC18C\uBC95 \uC774\uB860 \uC790\uB8CC\uC785\uB2C8\uB2E4." }), _jsx(PDEFEMMainRouter, {})] }) }));
};
export default PDEFEMPage;
