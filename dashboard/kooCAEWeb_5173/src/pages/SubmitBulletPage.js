import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import SubmitBulletPanel from '../components/submit/SubmitBulletPanel';
const { Title } = Typography;
const SubmitBulletPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 2, children: "Bullet \uC791\uC5C5 \uC81C\uCD9C" }), _jsx(SubmitBulletPanel, {})] }) }));
};
export default SubmitBulletPage;
