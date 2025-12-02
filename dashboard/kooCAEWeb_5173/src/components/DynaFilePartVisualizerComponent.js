import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState } from 'react';
import { Typography, Divider, Button, message } from 'antd';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import StlViewerComponent from './StlViewerComponent';
import { api } from '../api/axiosClient';
const { Title, Paragraph, Text } = Typography;
const DynaFilePartVisualizerComponent = ({ onReady }) => {
    const [kFileName, setKFileName] = useState('업로드된 파일 없음');
    const [allParts, setAllParts] = useState([]);
    const [selectedPart, setSelectedPart] = useState(null);
    const [uploadedFile, setUploadedFile] = useState(null);
    const [stlUrl, setStlUrl] = useState(null);
    const username = localStorage.getItem('username') || 'default_user';
    const handlePartSelect = (part) => {
        setSelectedPart(part);
    };
    const handleConvertToStl = async () => {
        if (!uploadedFile || !selectedPart) {
            message.error('파일과 Part ID를 모두 선택해주세요.');
            return;
        }
        const formData = new FormData();
        formData.append('file', uploadedFile);
        formData.append('partid', selectedPart.id);
        formData.append('user', username);
        try {
            message.info('STL 변환 중...');
            const response = await api.post('/api/convert_kfile_to_stl', formData, {
                headers: {
                    'Content-Type': 'multipart/form-data',
                },
                responseType: 'blob',
            });
            const blob = new Blob([response.data], { type: 'application/sla' });
            const url = URL.createObjectURL(blob);
            setStlUrl(url);
            message.success('STL 변환 성공');
            // ✅ 외부로 데이터 전달
            if (onReady) {
                onReady({
                    kfile: uploadedFile,
                    partId: selectedPart.id,
                    stlUrl: url,
                });
            }
        }
        catch (err) {
            console.error('STL 변환 오류:', err);
            const errorText = err.response?.data?.error || err.message || '알 수 없는 오류';
            message.error(`STL 변환 실패: ${errorText}`);
        }
    };
    return (_jsxs("div", { style: { padding: 24 }, children: [_jsx(Title, { level: 3, children: "Dyna K\uD30C\uC77C \uD30C\uD2B8 \uC120\uD0DD\uAE30 + STL \uC2DC\uAC01\uD654" }), _jsx(Paragraph, { children: "LS-DYNA\uC758 K \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uACE0 \uD3EC\uD568\uB41C Part\uB97C \uC120\uD0DD\uD55C \uB4A4, \uD615\uC0C1\uC744 \uC2DC\uAC01\uD654\uD558\uC5EC \uD30C\uD2B8\uB97C \uD655\uC778\uD569\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                    setKFileName(filename);
                    setAllParts(parts);
                    setUploadedFile(file || null);
                    setSelectedPart(null);
                    setStlUrl(null);
                } }), _jsxs(Text, { type: "secondary", children: ["\uD83D\uDCC2 ", kFileName] }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allParts, onSelect: handlePartSelect }), selectedPart && (_jsxs(Paragraph, { style: { marginTop: 16 }, children: ["\uC120\uD0DD\uB41C Part: ", _jsx(Text, { code: true, children: selectedPart.id }), selectedPart.name && _jsxs("span", { children: [" \u2013 ", selectedPart.name] })] })), _jsx(Button, { type: "primary", style: { marginTop: 16 }, onClick: handleConvertToStl, disabled: !uploadedFile || !selectedPart, children: "Part \uD615\uC0C1 \uD655\uC778\uD558\uAE30" }), stlUrl && (_jsxs(_Fragment, { children: [_jsx(Divider, {}), _jsx(Title, { level: 4, children: "\uD83E\uDDCA STL Viewer" }), _jsx(StlViewerComponent, { url: stlUrl }), _jsxs("div", { style: { marginTop: 16, display: 'flex', gap: '1rem' }, children: [_jsx(Button, { type: "default", children: _jsx("a", { href: stlUrl, download: `${kFileName.replace(/\.[^/.]+$/, '')}_${selectedPart?.id}.stl`, style: { color: 'inherit', textDecoration: 'none' }, children: "STL \uD30C\uC77C \uB2E4\uC6B4\uB85C\uB4DC" }) }), uploadedFile && (_jsx(Button, { type: "default", children: _jsx("a", { href: URL.createObjectURL(uploadedFile), download: kFileName, style: { color: 'inherit', textDecoration: 'none' }, children: "\uC6D0\uBCF8 K\uD30C\uC77C \uB2E4\uC6B4\uB85C\uB4DC" }) }))] })] }))] }));
};
export default DynaFilePartVisualizerComponent;
