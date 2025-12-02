import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import ContactStiffnessDemoComponent from '../components/ContactStiffnessDemoComponent';
import { Typography } from 'antd';
const { Title, Paragraph } = Typography;
const ContactStiffnessDemoPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Contact Stiffness Demo" }), _jsx(Paragraph, { children: "\uC774 \uD398\uC774\uC9C0\uC5D0\uC11C\uB294 \uCDA9\uB3CC \uAC15\uC131\uC744 \uC2DC\uBBAC\uB808\uC774\uC158\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uD604\uC7AC \uC0AC\uC6A9\uD558\uB294 \uC694\uC18C \uD06C\uAE30\uC640 \uC2DC\uAC04 \uAC04\uACA9\uC744 \uC870\uC815\uD558\uC5EC \uCDA9\uB3CC \uAC15\uC131\uC744 \uC2DC\uBBAC\uB808\uC774\uC158\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(ContactStiffnessDemoComponent, {})] }) }));
};
export default ContactStiffnessDemoPage;
