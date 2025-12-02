import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import MorphComponent from '../components/MorphComponent';
const { Title, Paragraph } = Typography;
const BoxMorphPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDCE6 \uBC15\uC2A4 \uBAA8\uD551 \uC2DC\uBBAC\uB808\uC774\uC158" }), _jsx(Paragraph, { children: "\uC544\uB798 2D \uACF5\uAC04\uC5D0\uC11C \uBC15\uC2A4\uB97C \uADF8\uB824 Morphing \uBC94\uC704\uB97C \uC9C0\uC815\uD558\uACE0, \uC124\uC815\uAC12\uC744 \uD1B5\uD574 LS-DYNA \uC2A4\uD06C\uB9BD\uD2B8\uB97C \uC0DD\uC131\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(MorphComponent, {})] }) }));
};
export default BoxMorphPage;
