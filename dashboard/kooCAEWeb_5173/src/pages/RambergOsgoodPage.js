import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import RambergOsgoodPanel from '../components/RambergOsgoodPanel';
import { Typography } from 'antd';
const { Title, Paragraph } = Typography;
const RambergOsgoodPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Ramberg-Osgood \uBE44\uC120\uD615 \uC7AC\uB8CC \uBAA8\uB378" }), _jsx(Paragraph, { children: "\uBCF8 \uD398\uC774\uC9C0\uC5D0\uC11C\uB294 \uAE08\uC18D \uC7AC\uB8CC\uC758 \uD0C4\uC18C-\uC18C\uC131 \uAC70\uB3D9\uC744 \uD45C\uD604\uD558\uB294 Ramberg-Osgood \uBAA8\uB378\uC744 \uC2E4\uC2DC\uAC04\uC73C\uB85C \uC2DC\uBBAC\uB808\uC774\uC158\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uC601\uB960, \uD56D\uBCF5\uAC15\uB3C4, \uBE44\uC120\uD615 \uD30C\uB77C\uBBF8\uD130 \uB4F1\uC744 \uC870\uC815\uD558\uC5EC Stress-Strain \uACE1\uC120\uACFC \uD53C\uB85C \uC218\uBA85 \uACE1\uC120\uC744 \uD655\uC778\uD560 \uC218 \uC788\uC73C\uBA70, Fracture Strain \uC120\uD0DD \uC2DC \uD53C\uB85C \uD30C\uB77C\uBBF8\uD130\uAC00 \uC790\uB3D9 \uACC4\uC0B0\uB429\uB2C8\uB2E4." }), _jsx(RambergOsgoodPanel, {})] }) }));
};
export default RambergOsgoodPage;
