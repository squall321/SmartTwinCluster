import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from "../layouts/BaseLayout";
import PWMGenerator from "../components/PWMGenerator";
import { Typography } from "antd";
const { Title, Paragraph } = Typography;
const PWMGeneratorPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "PWM Generator" }), _jsx(Paragraph, { children: "PWM \uC2E0\uD638\uB97C \uC0DD\uC131\uD558\uB294 \uB3C4\uAD6C\uC785\uB2C8\uB2E4. \uC6D0\uD558\uB294 \uCC44\uB110 \uAC1C\uC218\uC640 \uD30C\uB77C\uBBF8\uD130\uB97C \uC9C1\uC811 \uC124\uC815\uD558\uACE0 \uADF8\uB798\uD504\uB85C \uC2DC\uAC01\uD654\uD558\uBA70 CSV\uB85C \uB0B4\uBCF4\uB0BC \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(PWMGenerator, {})] }) }));
};
export default PWMGeneratorPage;
