import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import MckLayout from '../../layouts/mck/MckLayout';
import BaseLayout from '../../layouts/BaseLayout';
import { Typography } from 'antd';
import ModelFormulaBox from '../../components/common/ModelFormulaBox';
const { Title, Paragraph } = Typography;
const MckEditorPage = () => {
    return (_jsxs(BaseLayout, { isLoggedIn: false, children: [_jsxs("div", { style: {
                    padding: 24,
                    backgroundColor: '#fff',
                    minHeight: '100vh',
                    borderRadius: '24px',
                }, children: [_jsx(Title, { level: 3, children: "MCK \uC2DC\uBBAC\uB808\uC774\uC158" }), _jsx(Paragraph, { children: "\uC774 \uD398\uC774\uC9C0\uC5D0\uC11C\uB294 MCK \uC2DC\uC2A4\uD15C \uBAA8\uB378\uC744 \uC2DC\uBBAC\uB808\uC774\uC158\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(ModelFormulaBox, { title: "MCK \uC2DC\uC2A4\uD15C \uC6B4\uB3D9\uBC29\uC815\uC2DD", description: "MCK \uC2DC\uC2A4\uD15C\uC758 \uC6B4\uB3D9\uBC29\uC815\uC2DD\uC740 \uC9C8\uB7C9, \uAC10\uC1E0, \uAC15\uC131 \uD589\uB82C\uB85C \uAD6C\uC131\uB429\uB2C8\uB2E4.", formulas: [
                            'M \\ddot{x}(t) + C \\dot{x}(t) + K x(t) = F(t)',
                        ] }), _jsx(ModelFormulaBox, { title: "Modal Analysis", description: "\uBAA8\uB2EC \uD574\uC11D\uC5D0\uC11C\uB294 \uACE0\uC720\uCE58 \uBB38\uC81C\uB97C \uD480\uC5B4 \uC2DC\uC2A4\uD15C\uC758 \uACE0\uC720\uC9C4\uB3D9\uC218\uC640 \uAC10\uC1E0\uBE44\uB97C \uAD6C\uD569\uB2C8\uB2E4.", formulas: [
                            'det\\bigl(K - \\omega^2 M\\bigr) = 0',
                            '\\zeta = -\\frac{\\text{Re}(\\lambda)}{\\sqrt{\\text{Re}(\\lambda)^2 + \\text{Im}(\\lambda)^2}}',
                            'f_n = \\frac{\\sqrt{\\text{Re}(\\lambda)^2 + \\text{Im}(\\lambda)^2}}{2 \\pi}',
                        ] }), _jsx(ModelFormulaBox, { title: "Harmonic Response", description: "\uD558\uBAA8\uB2C9 \uD574\uC11D\uC5D0\uC11C\uB294 \uC8FC\uC5B4\uC9C4 \uC8FC\uD30C\uC218\uC5D0 \uB300\uD574 \uC2DC\uC2A4\uD15C \uC751\uB2F5\uC744 \uACC4\uC0B0\uD569\uB2C8\uB2E4.", formulas: [
                            'Z(j\\omega) = -\\omega^2 M + j\\omega C + K',
                            'X(j\\omega) = Z(j\\omega)^{-1} F(j\\omega)',
                            '|X(j\\omega)|_{dB} = 20 \\log_{10} |X(j\\omega)|',
                        ] })] }), _jsx(MckLayout, {})] }));
};
export default MckEditorPage;
