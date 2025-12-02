import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import MolbeideStressPlot from '../components/MolbeideStressPlot';
const { Title, Paragraph } = Typography;
const PostFullAngleDropsPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: { padding: 24, backgroundColor: '#fff', minHeight: '100vh', borderRadius: '24px' }, children: [_jsx(Title, { level: 3, children: " \uC804\uAC01\uB3C4 \uCDA9\uB3CC \uC2DC\uBBAC\uB808\uC774\uC158 \uACB0\uACFC" }), _jsx(Paragraph, { children: "\uC804\uAC01\uB3C4 \uCDA9\uB3CC \uC2DC\uBBAC\uB808\uC774\uC158 \uACB0\uACFC\uB97C \uBCF4\uC5EC\uC90D\uB2C8\uB2E4." }), _jsx(MolbeideStressPlot, {})] }) }));
};
export default PostFullAngleDropsPage;
