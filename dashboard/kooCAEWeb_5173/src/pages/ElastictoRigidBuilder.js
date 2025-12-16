import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider } from 'antd';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import PartTable from '../components/shared/PartTable';
import ExportMeshModifierButton from '../components/shared/ExportMeshModifierButtonProps';
import { generateRigidOptionFile } from '../components/shared/utils';
const { Title, Paragraph, Text } = Typography;
const ElasticToRigid = () => {
    const [kFile, setKFile] = useState(null); // 🔹추가
    const [kFileName, setKFileName] = useState('uploaded_file.k');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [excludePartIds, setExcludePartIds] = useState([]);
    const handlePartSelect = (part) => {
        if (!excludePartIds.find(p => p.id === part.id)) {
            setExcludePartIds(prev => [...prev, part]);
        }
    };
    const handlePartRemove = (id) => {
        setExcludePartIds(prev => prev.filter(p => p.id !== id));
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Elastic to Rigid \uBCC0\uD658 \uC124\uC815" }), _jsxs(Paragraph, { children: ["LS-DYNA K \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uC5EC \uD30C\uD2B8\uB97C \uBD84\uC11D\uD558\uACE0, \uAC15\uCCB4\uB85C \uC804\uD658\uD558\uC9C0 \uC54A\uC744 \uD30C\uD2B8\uB97C \uC120\uD0DD\uD558\uC138\uC694.", _jsx("br", {}), "\uC774\uD6C4 \uC635\uC158\uD30C\uC77C\uC744 \uB2E4\uC6B4\uB85C\uB4DC\uD558\uC5EC \uD574\uC11D \uC785\uB825 \uD30C\uC77C\uC5D0 \uC0AC\uC6A9\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4."] }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                        setKFileName(filename);
                        setAllPartInfos(parts);
                        setExcludePartIds([]);
                        setKFile(file ?? null);
                    } }), _jsx(Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "\uC81C\uC678\uD560 Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allPartInfos, onSelect: handlePartSelect }), _jsx(PartTable, { parts: excludePartIds, editable: true, onRemove: handlePartRemove, title: "\uAC15\uCCB4\uB85C \uBCC0\uD658\uD558\uC9C0 \uC54A\uC744 \uD30C\uD2B8 \uBAA9\uB85D" }), _jsx("div", { style: { marginTop: 32, textAlign: 'center' }, children: _jsx(ExportMeshModifierButton, { kFile: kFile, kFileName: kFileName, optionFileGenerator: () => generateRigidOptionFile(kFileName, allPartInfos, excludePartIds), optionFileName: "elasticToRigidOption.txt", solver: "MeshModifier", mode: "ElasticToRigid", buttonLabel: "\uD83D\uDD01 \uD574\uC11D \uC2E4\uD589 (Mesh Modifier)" }) })] }) }));
};
export default ElasticToRigid;
