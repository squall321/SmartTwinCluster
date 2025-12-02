import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState } from 'react';
import { Typography, Divider, Button, message } from 'antd';
import PartIdFinderUploader from '../components/uploader/PartIDFindwithBDUploader';
import PartSelector from '../components/shared/PartSelector';
import GLBDynamicViewerComponent from './GLBDynamicViewerComponent';
import { api } from '../api/axiosClient';
const { Title, Paragraph, Text } = Typography;
const DynaFilePartVisualizerGLBComponent = ({ onReady }) => {
    const [kFileName, setKFileName] = useState('업로드된 파일 없음');
    const [allParts, setAllParts] = useState([]);
    const [selectedPart, setSelectedPart] = useState(null);
    const [uploadedFile, setUploadedFile] = useState(null);
    const [glbFile, setGlbFile] = useState(null);
    const username = localStorage.getItem('username') || 'default_user';
    const handlePartSelect = (part) => {
        setSelectedPart(part);
    };
    const handleConvertToGlb = async () => {
        if (!uploadedFile || !selectedPart) {
            message.error('파일과 Part ID를 모두 선택해주세요.');
            return;
        }
        const formData = new FormData();
        formData.append('file', uploadedFile);
        formData.append('partid', selectedPart.id);
        formData.append('user', username);
        try {
            message.info('GLB 변환 중...');
            console.log(formData.get('file'));
            console.log(formData.get('partid'));
            console.log(formData.get('user'));
            const response = await api.post('/api/convert_kfile_to_glb', // ✅ API 엔드포인트
            formData, {
                headers: {
                    'Content-Type': 'multipart/form-data',
                },
                responseType: 'blob',
            });
            // Blob → File 객체로 변환
            const glbBlob = new Blob([response.data], { type: 'model/gltf-binary' });
            const glbFilename = `${kFileName.replace(/\.[^/.]+$/, '')}_${selectedPart.id}.glb`;
            const fileObj = new File([glbBlob], glbFilename, { type: 'model/gltf-binary' });
            setGlbFile(fileObj);
            message.success('GLB 변환 성공');
            if (onReady) {
                onReady({
                    kfile: uploadedFile,
                    partId: selectedPart.id,
                    glbFile: fileObj,
                });
            }
        }
        catch (err) {
            console.error('GLB 변환 오류:', err);
            const errorText = err.response?.data?.error || err.message || '알 수 없는 오류';
            message.error(`GLB 변환 실패: ${errorText}`);
        }
    };
    return (_jsxs("div", { style: { padding: 24 }, children: [_jsx(Title, { level: 3, children: "Dyna K\uD30C\uC77C \uD30C\uD2B8 \uC120\uD0DD\uAE30 + GLB \uC2DC\uAC01\uD654" }), _jsx(Paragraph, { children: "LS-DYNA\uC758 K \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uACE0 \uD3EC\uD568\uB41C Part\uB97C \uC120\uD0DD\uD55C \uB4A4, GLB \uD615\uC0C1\uC73C\uB85C \uC2DC\uAC01\uD654\uD558\uC5EC \uD30C\uD2B8\uB97C \uD655\uC778\uD569\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                    setKFileName(filename);
                    setAllParts(parts);
                    setUploadedFile(file || null);
                    setSelectedPart(null);
                    setGlbFile(null);
                } }), _jsxs(Text, { type: "secondary", children: ["\uD83D\uDCC2 ", kFileName] }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allParts, onSelect: handlePartSelect }), selectedPart && (_jsxs(Paragraph, { style: { marginTop: 16 }, children: ["\uC120\uD0DD\uB41C Part: ", _jsx(Text, { code: true, children: selectedPart.id }), selectedPart.name && _jsxs("span", { children: [" \u2013 ", selectedPart.name] })] })), _jsx(Button, { type: "primary", style: { marginTop: 16 }, onClick: handleConvertToGlb, disabled: !uploadedFile || !selectedPart, children: "Part \uD615\uC0C1 \uD655\uC778\uD558\uAE30 (GLB)" }), glbFile && (_jsxs(_Fragment, { children: [_jsx(Divider, {}), _jsx(Title, { level: 4, children: "\uD83E\uDDCA GLB Viewer" }), _jsx(GLBDynamicViewerComponent, { file: glbFile, autoScale: false }), _jsxs("div", { style: { marginTop: 16, display: 'flex', gap: '1rem' }, children: [_jsx(Button, { type: "default", children: _jsx("a", { href: URL.createObjectURL(glbFile), download: glbFile.name, style: { color: 'inherit', textDecoration: 'none' }, children: "GLB \uD30C\uC77C \uB2E4\uC6B4\uB85C\uB4DC" }) }), uploadedFile && (_jsx(Button, { type: "default", children: _jsx("a", { href: URL.createObjectURL(uploadedFile), download: kFileName, style: { color: 'inherit', textDecoration: 'none' }, children: "\uC6D0\uBCF8 K\uD30C\uC77C \uB2E4\uC6B4\uB85C\uB4DC" }) }))] })] }))] }));
};
export default DynaFilePartVisualizerGLBComponent;
