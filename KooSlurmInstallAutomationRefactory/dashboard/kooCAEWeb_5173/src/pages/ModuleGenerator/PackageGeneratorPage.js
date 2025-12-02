import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from "../../layouts/BaseLayout";
import LayeredModelEditor from "../../ModuleGenerator/LayeredModelEditor";
import { Typography } from "antd";
const { Title, Paragraph } = Typography;
const PackageGeneratorPage = () => {
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Package Generator" }), _jsx(Paragraph, { children: "Package Generator" }), _jsx(LayeredModelEditor, {})] }) }));
};
export default PackageGeneratorPage;
