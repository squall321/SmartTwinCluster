import { jsx as _jsx } from "react/jsx-runtime";
import BaseLayout from "../layouts/BaseLayout";
import ThreePointBendingApp from "../components/threepointbending/ThreePointBendingApp";
import { Typography } from "antd";
const { Title, Paragraph } = Typography;
const ThreePointBendingPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsx("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: _jsx(ThreePointBendingApp, {}) }) }));
};
export default ThreePointBendingPage;
