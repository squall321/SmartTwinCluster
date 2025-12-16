import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useCallback, useState } from 'react';
import { Typography, Upload, message } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import GLBDynamicViewerComponent from '../components/GLBDynamicViewerComponent';
const { Title, Paragraph } = Typography;
const { Dragger } = Upload;
const ComponentTestMeshViewerPage = () => {
    const [file, setFile] = useState(null);
    const handleFile = useCallback((file) => {
        const name = file.name.toLowerCase();
        if (!name.endsWith('.gltf') && !name.endsWith('.glb')) {
            message.error('❌ GLTF 또는 GLB 파일만 지원됩니다.');
            return false;
        }
        setFile(file);
        return false; // 수동 업로드
    }, []);
    const uploadProps = {
        multiple: false,
        beforeUpload: handleFile,
        showUploadList: false,
        accept: '.gltf,.glb',
    };
    return (_jsxs("div", { style: { padding: '2rem' }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDCE6 GLTF/GLB \uB4DC\uB798\uADF8 \uD14C\uC2A4\uD2B8" }), _jsx(Paragraph, { children: "GLTF \uB610\uB294 GLB \uD30C\uC77C\uC744 \uB4DC\uB798\uADF8\uD558\uBA74 3D\uB85C \uAC00\uC2DC\uD654\uB429\uB2C8\uB2E4." }), _jsxs(Dragger, { ...uploadProps, style: { marginBottom: 32 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "\uC5EC\uAE30\uC5D0 \uD30C\uC77C\uC744 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD574\uC11C \uC120\uD0DD\uD558\uC138\uC694" })] }), file && _jsx(GLBDynamicViewerComponent, { file: file, autoScale: false })] }));
};
export default ComponentTestMeshViewerPage;
