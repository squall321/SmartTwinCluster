import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState, useEffect } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider, Button, Table, Input, Select, Space, message, } from 'antd';
import { DownloadOutlined, DeleteOutlined, ArrowUpOutlined, ArrowDownOutlined, CopyOutlined, CloseCircleOutlined, } from '@ant-design/icons';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import { api } from '../api/axiosClient';
import { parseMaterialTxt } from '../components/MaterialParserWorker';
import { useNavigate } from 'react-router-dom';
const { Title, Paragraph, Text } = Typography;
const AdvancedDisplayBuilder = () => {
    const navigate = useNavigate();
    const [kFileName, setKFileName] = useState('uploaded_file.k');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [selectedParts, setSelectedParts] = useState([]);
    const [layerGroups, setLayerGroups] = useState([]);
    const [materialDict, setMaterialDict] = useState({});
    const [materialOptions, setMaterialOptions] = useState([]);
    const [midMap, setMidMap] = useState(new Map());
    const [uploadedKFile, setUploadedKFile] = useState(null);
    function simplifyMatType(type) {
        if (!type.startsWith('*MAT_'))
            return type;
        let core = type.replace('*MAT_', '');
        core = core.replace('_TITLE', '');
        core = core.replace('_', ' ');
        return core.trim();
    }
    useEffect(() => {
        const fetchMaterials = async () => {
            try {
                const url = `/api/materials/display`;
                const res = await api.get(url, { responseType: 'text' });
                const parsed = parseMaterialTxt(res.data);
                setMaterialDict(parsed);
                const entries = Object.entries(parsed);
                const newOptions = entries.map(([key, data], index) => {
                    let type = simplifyMatType(data.type || '');
                    let name = data.name?.trim() || `Material_${index + 1}`;
                    return {
                        label: `${type} / ${name}`,
                        value: key,
                    };
                });
                setMaterialOptions(newOptions);
            }
            catch (err) {
                console.error('📛 재료 정보 불러오기 실패:', err);
            }
        };
        fetchMaterials();
    }, []);
    const handlePartSelect = (part) => {
        const modelThickness = (part.boundaryBox?.max_z ?? 0) -
            (part.boundaryBox?.min_z ?? 0);
        const partWithThickness = {
            ...part,
            modelThickness,
        };
        const index = selectedParts.findIndex((p) => p.id === part.id);
        let updatedParts;
        if (index >= 0) {
            updatedParts = [...selectedParts];
            updatedParts[index] = partWithThickness;
        }
        else {
            updatedParts = [...selectedParts, partWithThickness];
            setLayerGroups((prev) => [...prev, []]);
        }
        setSelectedParts(updatedParts);
    };
    const handleRemovePart = (id) => {
        const updatedParts = [];
        const updatedGroups = [];
        selectedParts.forEach((p, index) => {
            if (p.id !== id) {
                updatedParts.push(p);
                updatedGroups.push(layerGroups[index]);
            }
        });
        setSelectedParts(updatedParts);
        setLayerGroups(updatedGroups);
    };
    const handleLayerChange = (groupIndex, layerIndex, key, value) => {
        const updatedGroups = [...layerGroups];
        const updatedLayers = [...updatedGroups[groupIndex]];
        updatedLayers[layerIndex] = {
            ...updatedLayers[layerIndex],
            [key]: key === 'thickness' || key === 'numE' ? parseFloat(value) : value,
        };
        updatedGroups[groupIndex] = updatedLayers;
        setLayerGroups(updatedGroups);
    };
    const addLayer = (groupIndex) => {
        const updatedGroups = [...layerGroups];
        updatedGroups[groupIndex].push({
            name: `Layer ${updatedGroups[groupIndex].length + 1}`,
            thickness: 0.05,
            materialId: '',
            numE: 3,
        });
        setLayerGroups(updatedGroups);
    };
    const deleteLayer = (groupIndex, index) => {
        const updatedGroups = [...layerGroups];
        updatedGroups[groupIndex] = updatedGroups[groupIndex].filter((_, i) => i !== index);
        setLayerGroups(updatedGroups);
    };
    const moveLayer = (groupIndex, index, direction) => {
        const updatedGroups = [...layerGroups];
        const layers = updatedGroups[groupIndex];
        if ((direction === 'up' && index === 0) ||
            (direction === 'down' && index === layers.length - 1))
            return;
        const swapIndex = direction === 'up' ? index - 1 : index + 1;
        [layers[index], layers[swapIndex]] = [layers[swapIndex], layers[index]];
        updatedGroups[groupIndex] = layers;
        setLayerGroups(updatedGroups);
    };
    const copyLayer = (groupIndex, index) => {
        const updatedGroups = [...layerGroups];
        const newLayer = {
            ...updatedGroups[groupIndex][index],
            name: `${updatedGroups[groupIndex][index].name} Copy`,
        };
        updatedGroups[groupIndex].push(newLayer);
        setLayerGroups(updatedGroups);
    };
    const columns = (groupIndex) => [
        {
            title: '층 이름',
            render: (_, __, i) => (_jsx(Input, { value: layerGroups[groupIndex][i].name, onChange: (e) => handleLayerChange(groupIndex, i, 'name', e.target.value) })),
        },
        {
            title: '두께 (mm)',
            render: (_, __, i) => (_jsx(Input, { type: "number", value: layerGroups[groupIndex][i].thickness, onChange: (e) => handleLayerChange(groupIndex, i, 'thickness', e.target.value) })),
        },
        {
            title: 'Element 수',
            render: (_, __, i) => (_jsx(Input, { type: "number", value: layerGroups[groupIndex][i].numE ?? 3, onChange: (e) => handleLayerChange(groupIndex, i, 'numE', e.target.value) })),
        },
        {
            title: 'Material ID',
            render: (_, __, i) => (_jsx(Select, { value: layerGroups[groupIndex][i].materialId, onChange: (val) => handleLayerChange(groupIndex, i, 'materialId', val), style: { width: 400 }, showSearch: true, placeholder: "Material \uC120\uD0DD", filterOption: (input, option) => {
                    const label = option?.label?.toString().toLowerCase() ?? '';
                    const value = option?.value?.toString().toLowerCase() ?? '';
                    return (label.includes(input.toLowerCase()) ||
                        value.includes(input.toLowerCase()));
                }, options: materialOptions })),
        },
        {
            title: '작업',
            render: (_, __, i) => (_jsxs(Space, { children: [_jsx(Button, { icon: _jsx(ArrowUpOutlined, {}), onClick: () => moveLayer(groupIndex, i, 'up') }), _jsx(Button, { icon: _jsx(ArrowDownOutlined, {}), onClick: () => moveLayer(groupIndex, i, 'down') }), _jsx(Button, { icon: _jsx(CopyOutlined, {}), onClick: () => copyLayer(groupIndex, i) }), _jsx(Button, { icon: _jsx(DeleteOutlined, {}), onClick: () => deleteLayer(groupIndex, i), danger: true })] })),
        },
    ];
    /**
     * Layup 옵션 텍스트(=TXT 파일 내용) 생성 + midMap 업데이트
     */
    const buildOptionText = () => {
        const lines = [];
        lines.push(`*Inputfile\n${kFileName}\n*Mode`);
        layerGroups.forEach((_, groupIndex) => {
            lines.push(`PART_EXCHANGE,${groupIndex + 1}`);
        });
        let midMapLocal = new Map(midMap);
        let midCounter = 1;
        if (midMapLocal.size > 0) {
            const existingMids = Array.from(midMapLocal.values())
                .map((m) => parseInt(m.replace(/^MID/, ''), 10))
                .filter((n) => !isNaN(n));
            midCounter = existingMids.length > 0 ? Math.max(...existingMids) + 1 : 1;
        }
        layerGroups.forEach((layers, groupIndex) => {
            const part = selectedParts[groupIndex];
            const pid = part?.id || `1001${groupIndex}`;
            lines.push(`**PartExchange,${groupIndex + 1}`);
            lines.push(`*PID,${pid}`);
            lines.push(`*ConvertHexato,SolidComp,(0,0,1),5.0`);
            const thkLines = [];
            const usedMaterialIds = new Set();
            layers.forEach((layer, i) => {
                if (!layer.materialId)
                    return;
                usedMaterialIds.add(layer.materialId);
                if (!midMapLocal.has(layer.materialId)) {
                    const newMid = `MID${midCounter.toString().padStart(2, '0')}`;
                    midMapLocal.set(layer.materialId, newMid);
                    midCounter++;
                }
                const realMid = midMapLocal.get(layer.materialId);
                const thkId = `THK${(groupIndex + 1).toString().padStart(2, '0')}${i + 1}`;
                const numEId = `NUME${(groupIndex + 1).toString().padStart(2, '0')}${i + 1}`;
                const numE = layer.numE ?? 3;
                lines.push(`*${thkId},${layer.thickness.toExponential(5)}`);
                lines.push(`*${numEId},${numE}`);
                thkLines.push(`${thkId},${realMid},EOS,HGID,${numEId}`);
            });
            midMapLocal.forEach((newMid, matId) => {
                if (!usedMaterialIds.has(matId)) {
                    return;
                }
                const mat = materialDict[matId];
                if (mat?.impl) {
                    const linesInTemplate = mat.impl.split('\n');
                    let rest = linesInTemplate.slice(1).join('\n');
                    const keywordLine = `*${newMid},${mat.type || '*MAT_ELASTIC_TITLE'}`;
                    let implFixed = rest
                        .split('\n')
                        .map((line) => {
                        if (line.trim().startsWith('$')) {
                            return line;
                        }
                        let replaced = line.replace(/\bMIDXX\b/g, newMid);
                        replaced = replaced.replace(/^(\s*)MID\d+(\.?\d*)/, (_, spaces, trailing) => {
                            const indentSpaces = ' '.repeat(10 - newMid.length);
                            return indentSpaces + newMid + trailing;
                        });
                        return replaced;
                    })
                        .join('\n');
                    lines.push(keywordLine);
                    lines.push(implFixed);
                }
                else {
                    lines.push(`*${newMid},*MAT_ELASTIC_TITLE`);
                    lines.push(`${mat?.name || matId}`);
                    lines.push(`$$     MID        RO         E        PR`);
                    lines.push(`     ${newMid.padStart(10, ' ')}    1.0E-9    1000.0      0.30`);
                }
            });
            lines.push(`*Layup`);
            lines.push(`$$THK,MID,EOSID,HGID,NUME from bottomside`);
            thkLines.reverse().forEach((line) => lines.push(line));
            lines.push(`*EndLayup`);
            lines.push(`**EndPartExchange`);
        });
        lines.push(`*End`);
        return {
            text: lines.join('\n'),
            midMapLocal,
        };
    };
    const exportLSDynaScript = () => {
        const { text, midMapLocal } = buildOptionText();
        setMidMap(midMapLocal);
        const blob = new Blob([text], {
            type: 'text/plain;charset=utf-8',
        });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = 'advancedDisplayBuilder.txt';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };
    const runMeshModifier = async () => {
        try {
            const { text, midMapLocal } = buildOptionText();
            setMidMap(midMapLocal);
            // 1) 옵션파일(TXT) -> File
            const optionFile = new File([text], 'advancedDisplayBuilder.txt', {
                type: 'text/plain',
            });
            // 2) 업로드했던 K파일(opt)을 서버에서 다시 불러와 File로 만들기
            //    (API 경로는 환경에 맞게 수정)
            if (!uploadedKFile) {
                message.error('K 파일이 업로드되지 않았습니다.');
                return;
            }
            const kFile = uploadedKFile;
            // 3) StreamRunner로 넘겨서 자동 제출
            navigate('/tools/stream-runner', {
                state: {
                    solver: 'MeshModifier', // StreamRunner 내부에서 solver !== "AutomatedModeller" 이면 MeshModifier 경로 사용
                    mode: 'AdvancedDisplay',
                    txtFiles: [optionFile],
                    optFiles: [kFile],
                    autoSubmit: true,
                },
            });
        }
        catch (e) {
            console.error(e);
            message.error('Mesh Modifier 실행 중 오류가 발생했습니다.');
        }
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "Advanced Display Builder" }), _jsx(Paragraph, { children: "K \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uACE0 Part ID\uB97C \uC120\uD0DD\uD55C \uB4A4 \uAC01 \uD30C\uD2B8\uC758 \uC801\uCE35 \uAD6C\uC870\uB97C \uC815\uC758\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                        setKFileName(filename);
                        setAllPartInfos(parts);
                        setSelectedParts([]);
                        setLayerGroups([]);
                        setMidMap(new Map());
                        setUploadedKFile(file ?? null); // ✅ file 저장
                    } }), _jsx(Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allPartInfos, onSelect: handlePartSelect }), _jsx(Divider, {}), layerGroups.map((layers, groupIndex) => {
                    const part = selectedParts[groupIndex];
                    if (!part)
                        return null;
                    const modelThickness = part.modelThickness ?? 0;
                    const totalThickness = layers.reduce((sum, l) => sum + l.thickness, 0);
                    const thicknessDiff = Math.abs(modelThickness - totalThickness);
                    const diffColor = thicknessDiff < 0.01 ? '#52c41a' : '#ff4d4f';
                    return (_jsxs("div", { style: { marginBottom: 48 }, children: [_jsxs("div", { style: {
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'space-between',
                                }, children: [_jsxs(Title, { level: 4, style: { margin: 0 }, children: ["PART ID: ", part.id, " - ", part.name, part.boundaryBox && (_jsxs(_Fragment, { children: [_jsx("br", {}), _jsxs("span", { style: { fontSize: '0.9em', color: '#555' }, children: ["\uBAA8\uB378 \uB450\uAED8:", ' ', modelThickness.toExponential(3), " mm"] })] })), layers.length > 0 && (_jsxs(_Fragment, { children: [_jsx("br", {}), _jsxs("span", { style: {
                                                            fontSize: '0.9em',
                                                            color: diffColor,
                                                        }, children: ["Layer \uCD1D \uB450\uAED8:", ' ', totalThickness.toExponential(3), " mm", part.boundaryBox &&
                                                                ` (차이: ${thicknessDiff.toExponential(3)} mm)`] })] }))] }), _jsx(Button, { danger: true, icon: _jsx(CloseCircleOutlined, {}), onClick: () => handleRemovePart(part.id), children: "\uC81C\uAC70" })] }), _jsx(Button, { onClick: () => addLayer(groupIndex), type: "primary", style: { marginBottom: 16 }, children: "\uCE35 \uCD94\uAC00" }), _jsx(Table, { columns: columns(groupIndex), dataSource: layers.map((l, i) => ({ ...l, key: i })), pagination: false, bordered: true })] }, part.id));
                }), _jsxs("div", { style: { marginTop: '2rem', textAlign: 'center' }, children: [_jsx(Button, { type: "primary", icon: _jsx(DownloadOutlined, {}), onClick: exportLSDynaScript, children: "\uC635\uC158\uD30C\uC77C \uCD9C\uB825" }), _jsx(Button, { style: { marginLeft: 12 }, onClick: runMeshModifier, children: "\uD83D\uDD01 \uD574\uC11D \uC2E4\uD589 (Mesh Modifier)" })] })] }) }));
};
export default AdvancedDisplayBuilder;
