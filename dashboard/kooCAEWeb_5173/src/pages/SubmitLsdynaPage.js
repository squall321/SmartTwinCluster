import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// src/pages/SubmitLsdynaPage.tsx
import { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import SubmitLsdynaPanel from '../components/submit/SubmitLsdynaPanel';
const { Title } = Typography;
const SubmitLsdynaPage = () => {
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
            }, children: [_jsx(Title, { level: 2, children: "LS-DYNA \uC791\uC5C5 \uC81C\uCD9C" }), _jsx(SubmitLsdynaPanel, { initialConfigs: configs })] }) }));
};
export default SubmitLsdynaPage;
