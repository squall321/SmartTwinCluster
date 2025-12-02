import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * SubmitLsdynaWithTemplatesPage
 *
 * Enhanced LS-DYNA job submission page with Apptainer command template integration.
 * This page demonstrates the complete Phase 3 production integration.
 */
import { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import SubmitLsdynaPanelWithTemplates from '../components/submit/SubmitLsdynaPanelWithTemplates';
const { Title, Paragraph } = Typography;
const SubmitLsdynaWithTemplatesPage = () => {
    const [configs, setConfigs] = useState([]);
    useEffect(() => {
        if (configs) {
            setConfigs(configs);
        }
    }, [configs]);
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 2, children: "LS-DYNA \uC791\uC5C5 \uC81C\uCD9C (\uD15C\uD50C\uB9BF \uD1B5\uD569)" }), _jsx(Paragraph, { style: { fontSize: '14px', color: '#666', marginBottom: 24 }, children: "Apptainer \uBA85\uB839\uC5B4 \uD15C\uD50C\uB9BF\uC744 \uC0AC\uC6A9\uD558\uC5EC LS-DYNA \uC791\uC5C5\uC744 \uC81C\uCD9C\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uD15C\uD50C\uB9BF\uC744 \uC120\uD0DD\uD558\uBA74 \uC790\uB3D9\uC73C\uB85C Slurm \uC2A4\uD06C\uB9BD\uD2B8\uAC00 \uC0DD\uC131\uB418\uBA70, \uD544\uC694\uD55C \uB9E4\uAC1C\uBCC0\uC218\uAC00 \uC790\uB3D9\uC73C\uB85C \uC124\uC815\uB429\uB2C8\uB2E4." }), _jsx(SubmitLsdynaPanelWithTemplates, { initialConfigs: configs })] }) }));
};
export default SubmitLsdynaWithTemplatesPage;
