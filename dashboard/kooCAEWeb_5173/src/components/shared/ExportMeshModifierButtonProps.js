import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Button } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
const ExportMeshModifierButton = ({ kFile, kFileName, optionFileGenerator, solver = 'MeshModifier', mode = 'default', optionFileName = 'option.txt', buttonLabel = '🔁 해석 실행', }) => {
    const navigate = useNavigate();
    const handleExportToFile = () => {
        const optionFile = optionFileGenerator();
        const link = document.createElement('a');
        link.href = URL.createObjectURL(optionFile);
        link.download = optionFileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };
    const handleExportToStreamRunner = () => {
        const optionFile = optionFileGenerator();
        const state = {
            solver,
            mode,
            txtFiles: [optionFile],
            optFiles: kFile ? [kFile] : [],
            autoSubmit: true,
        };
        navigate('/tools/stream-runner', { state });
    };
    return (_jsxs("div", { children: [_jsx(Button, { type: "primary", icon: _jsx(DownloadOutlined, {}), onClick: handleExportToFile, children: "\uC635\uC158\uD30C\uC77C \uCD9C\uB825" }), _jsx(Button, { style: { marginLeft: 12 }, onClick: handleExportToStreamRunner, children: buttonLabel })] }));
};
export default ExportMeshModifierButton;
