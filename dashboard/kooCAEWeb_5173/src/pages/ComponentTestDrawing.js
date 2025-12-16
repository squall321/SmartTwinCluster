import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider } from 'antd';
import DrawingCanvaswithModel from '../components/DrawingCanvaswithModel';
const { Title, Paragraph } = Typography;
const ComponentTestDrawing = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                width: '100%',
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDD8A\uFE0F Component Test: Drawing Canvas" }), _jsxs(Paragraph, { children: ["Poly \uBC84\uD2BC\uC744 \uB20C\uB7EC \uB2E4\uAC01\uD615\uC744, Box \uBC84\uD2BC\uC744 \uB20C\uB7EC \uC0AC\uAC01\uD615\uC744 \uADF8\uB9B4 \uC218 \uC788\uC2B5\uB2C8\uB2E4.", _jsx("br", {}), "\uAC01 \uC810\uC740 \uB4DC\uB798\uADF8\uB85C \uC774\uB3D9\uD560 \uC218 \uC788\uC73C\uBA70, grid\uC5D0 \uC2A4\uB0C5\uB429\uB2C8\uB2E4.", _jsx("br", {}), "Grid \uAC04\uACA9\uB3C4 \uC790\uC720\uB86D\uAC8C \uC870\uC808\uD574\uBCF4\uC138\uC694!"] }), _jsx(Divider, {}), _jsx(DrawingCanvaswithModel, {})] }) }));
};
export default ComponentTestDrawing;
