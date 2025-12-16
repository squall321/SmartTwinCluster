import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import ViscoElasticVisualizer from '../components/ViscoElasticVisualizer';
import { Typography } from 'antd';
const { Title, Paragraph } = Typography;
const ViscoelasticVisualizerPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Viscoelastic Visualizer" }), _jsx(Paragraph, { children: "\uBCF8 \uD398\uC774\uC9C0\uC5D0\uC11C\uB294 \uBE44\uC120\uD615 \uC7AC\uB8CC\uC758 \uBE44\uC120\uD615 \uAC70\uB3D9\uC744 \uC2DC\uBBAC\uB808\uC774\uC158\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(ViscoElasticVisualizer, {})] }) }));
};
export default ViscoelasticVisualizerPage;
