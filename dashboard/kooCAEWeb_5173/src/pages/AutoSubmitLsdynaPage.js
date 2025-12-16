import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useLocation, useNavigate } from 'react-router-dom';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, message } from 'antd';
import SubmitLsdynaPanel from '../components/submit/SubmitLsdynaPanel';
const { Title } = Typography;
const AutoSubmitLsdynaPage = () => {
    const location = useLocation();
    const navigate = useNavigate();
    const jobConfigs = location.state?.jobConfigs || [];
    if (jobConfigs.length === 0) {
        message.warning("전달된 작업 정보가 없습니다. 다시 업로드해 주세요.");
        navigate("/full-angle-drop");
        return null;
    }
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 2, children: "\uC81C\uCD9C \uC635\uC158 \uAC80\uD1A0 \uBC0F \uC804\uC1A1" }), _jsx(SubmitLsdynaPanel, { initialConfigs: jobConfigs })] }) }));
};
export default AutoSubmitLsdynaPage;
