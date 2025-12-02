import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider } from 'antd';
import ResourceSummary from '../components/ResourceSummaryComponent';
import RackViewerComponent from '../components/RackViewerComponent';
const { Title, Paragraph } = Typography;
const SlurmStatusPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDDA5\uFE0F Slurm \uC2A4\uCF00\uC904\uB7EC \uC0C1\uD0DC \uB300\uC2DC\uBCF4\uB4DC" }), _jsx(Paragraph, { children: "\uD604\uC7AC HPC \uD074\uB7EC\uC2A4\uD130\uC758 \uB178\uB4DC \uC790\uC6D0 \uC0AC\uC6A9 \uC0C1\uD0DC \uBC0F LSDYNA \uC791\uC5C5 \uCF54\uC5B4 \uC0AC\uC6A9\uB7C9\uC744 \uC2E4\uC2DC\uAC04\uC73C\uB85C \uD655\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "\uD83D\uDCCA \uC790\uC6D0 \uC694\uC57D" }), _jsx(ResourceSummary, {}), _jsx(Divider, { orientation: "left", children: "\uD83D\uDDC4\uFE0F \uB799\uBCC4 \uB178\uB4DC \uC0AC\uC6A9 \uD604\uD669" }), _jsx(RackViewerComponent, {})] }) }));
};
export default SlurmStatusPage;
