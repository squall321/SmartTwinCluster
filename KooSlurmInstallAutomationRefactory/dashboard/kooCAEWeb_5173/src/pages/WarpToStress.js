import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider, message } from 'antd';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import PartWarpageTable from '../components/shared/PartWarpageTable';
import WarpVisualizerComponent from '../components/WarpVisualizerComponent';
const { Title, Paragraph, Text } = Typography;
const WarpToStressPage = () => {
    const [kFileName, setKFileName] = useState('uploaded_file.k');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [includePartIds, setIncludePartIds] = useState([]);
    const [selectedPartId, setSelectedPartId] = useState(null);
    const [partWarpageMap, setPartWarpageMap] = useState({});
    const handlePartSelect = (part) => {
        if (!includePartIds.find(p => p.id === part.id)) {
            setIncludePartIds(prev => [...prev, part]);
        }
    };
    const handlePartRemove = (id) => {
        setIncludePartIds(prev => prev.filter(p => p.id !== id));
    };
    const handleUploadDat = async (partId, file) => {
        try {
            const text = await file.text();
            const rows = text.trim().split('\n').map(line => line.trim().split(/\t|\s+/).map(val => {
                const num = parseFloat(val);
                return isNaN(num) ? 9999 : num;
            }));
            setPartWarpageMap(prev => ({
                ...prev,
                [partId]: {
                    rawData: rows,
                    xLength: 1,
                    yLength: 1,
                    scaleFactor: 1
                }
            }));
            message.success(`Part ${partId}에 DAT 파일 업로드 완료`);
        }
        catch (e) {
            message.error('파일 파싱 실패');
        }
    };
    const handleParamChange = (partId, newParams) => {
        setPartWarpageMap(prev => ({
            ...prev,
            [partId]: {
                ...prev[partId],
                ...newParams
            }
        }));
    };
    return (_jsxs(BaseLayout, { isLoggedIn: true, children: [_jsxs("div", { style: {
                    padding: 24,
                    backgroundColor: '#fff',
                    minHeight: '100vh',
                    borderRadius: '24px',
                }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDCE6 \uD728\u2192\uC751\uB825 \uBCC0\uD658\uAE30" }), _jsx(Paragraph, { children: "\uD728(Warpage) \uB370\uC774\uD130\uB97C \uC774\uC6A9\uD574 \uC720\uD55C\uC694\uC18C \uD574\uC11D\uC5D0 \uC0AC\uC6A9\uD560 \uCD08\uAE30 \uC751\uB825 \uC0C1\uD0DC\uB97C \uC0DD\uC131\uD558\uB294 \uB3C4\uAD6C\uC785\uB2C8\uB2E4. .dat \uD615\uC2DD\uC758 \uBCC0\uC704 \uB370\uC774\uD130\uB97C \uBD88\uB7EC\uC640 \uC804\uCCB4 \uD06C\uAE30\uC640 \uC2A4\uCF00\uC77C \uD329\uD130\uB97C \uC9C0\uC815\uD558\uBA74, \uAC01 \uC9C0\uC810\uC758 \uBCC0\uD615\uB7C9\uC744 \uAE30\uBC18\uC73C\uB85C \uCD08\uAE30 \uC751\uB825 \uBD84\uD3EC\uB97C \uACC4\uC0B0\uD569\uB2C8\uB2E4. \uC0DD\uC131\uB41C \uC751\uB825\uC740 \uAD6C\uC870 \uD574\uC11D \uCD08\uAE30 \uC870\uAC74\uC73C\uB85C \uD65C\uC6A9\uD560 \uC218 \uC788\uC73C\uBA70, \uC131\uD615 \uC794\uB958\uC751\uB825\uC774\uB098 \uC5F4\uBCC0\uD615 \uB4F1\uC758 \uC601\uD5A5\uC744 \uBC18\uC601\uD558\uB294 \uB370 \uC720\uC6A9\uD569\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts) => {
                            setKFileName(filename);
                            setAllPartInfos(parts);
                            setIncludePartIds([]);
                            setPartWarpageMap({});
                        } }), _jsx(Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(PartSelector, { allParts: allPartInfos, onSelect: handlePartSelect }), _jsx(Divider, {}), _jsx(PartWarpageTable, { parts: includePartIds, editable: true, onRemove: handlePartRemove, onUploadDat: handleUploadDat, onViewPart: setSelectedPartId, datStatusMap: Object.fromEntries(includePartIds.map(p => [p.id, !!partWarpageMap[p.id]])), warpageMap: partWarpageMap, onParamChange: handleParamChange, title: "\uD3EC\uD568\uD560 Part \uBAA9\uB85D" })] }), _jsx(WarpVisualizerComponent, { warpageInfo: selectedPartId ? partWarpageMap[selectedPartId] ?? null : null })] }));
};
export default WarpToStressPage;
