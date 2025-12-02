import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useMemo, useEffect } from "react";
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider, Input, Select, Button, Space, Checkbox, Tag, InputNumber } from "antd";
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import PartDropWeightImpactTable from '../components/shared/PartDropWeightImpactTable';
import { generateDropWeightImpactTestbyPartsOptionFile } from "../components/shared/utils";
import ExportMeshModifierButton from "@components/shared/ExportMeshModifierButtonProps";
const { Title, Paragraph, Text } = Typography;
const { Option } = Select;
const cellStyle = {
    border: '1px solid #ddd',
    padding: 8,
    textAlign: 'center',
};
// 공통 옵션
const dotPatterns = [
    '1x1', '1x2', '2x1', '2x2', '1x3', '3x1', '3x3'
];
const heightOptions = Array.from({ length: 10 }, (_, i) => 50 * (i + 1)); // 50~500
const AllPointsDropWeightImpactGenerator = () => {
    const [kFileName, setKFileName] = useState('');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [selectedParts, setSelectedParts] = useState([]);
    const [layerGroups, setLayerGroups] = useState([]);
    const [midMap, setMidMap] = useState(new Map());
    const [uploadedKFile, setUploadedKFile] = useState(null);
    // ✅ 추가: 키워드 기반 일괄 적용 상태
    const [bulkKeyword, setBulkKeyword] = useState('');
    const [bulkPattern, setBulkPattern] = useState('3x3');
    const [bulkHeight, setBulkHeight] = useState(200);
    const [includeNotSelected, setIncludeNotSelected] = useState(true); // 선택 안 된 파트도 추가할지 여부
    const [densityCylinder, setDensityCylinder] = useState(7.800e-9);
    const [youngModulusCylinder, setYoungModulusCylinder] = useState(210e3);
    const [poissonRatioCylinder, setPoissonRatioCylinder] = useState(0.35);
    const [youngModulusCylinderFront, setYoungModulusCylinderFront] = useState(100);
    const [densityCylinderFront, setDensityCylinderFront] = useState(0.900e-9);
    const [poissonRatioCylinderFront, setPoissonRatioCylinderFront] = useState(0.499);
    const [densitySphere, setDensitySphere] = useState(7.800e-9);
    const [youngModulusSphere, setYoungModulusSphere] = useState(210e3);
    const [poissonRatioSphere, setPoissonRatioSphere] = useState(0.35);
    const [densityWall, setDensityWall] = useState(7.800e-9);
    const [youngModulusWall, setYoungModulusWall] = useState(210e3);
    const [poissonRatioWall, setPoissonRatioWall] = useState(0.35);
    const [offsetDistance, setOffsetDistance] = useState(0.05);
    const [meshSize, setMeshSize] = useState(1);
    const [tFinal, setTFinal] = useState(0.005);
    const [dt, setDt] = useState(1e-6);
    const [velocityVector, setVelocityVector] = useState([0, 0, 0]);
    const [impactorType, setImpactorType] = useState('cylinder');
    const [impactorDiameter, setImpactorDiameter] = useState(8);
    const [impactorWeight, setImpactorWeight] = useState(200);
    const [frontDiameter, setFrontDiameter] = useState(16); // radius1
    const [midDiameter, setMidDiameter] = useState(20); // radius2
    const [backDiameter, setBackDiameter] = useState(24); // radius3
    const [frontHeight, setFrontHeight] = useState(10); // height1
    const [backHeight, setBackHeight] = useState(40); // height2
    const materialTableData = [
        {
            key: 'impactor',
            label: 'Impactor Cylinder',
            enabledFor: ['cylinder'],
            young: youngModulusCylinder,
            setYoung: setYoungModulusCylinder,
            poisson: poissonRatioCylinder,
            setPoisson: setPoissonRatioCylinder,
            density: densityCylinder,
            setDensity: setDensityCylinder,
        },
        {
            key: 'front',
            label: 'Impactor Front',
            enabledFor: ['cylinder'],
            young: youngModulusCylinderFront,
            setYoung: setYoungModulusCylinderFront,
            poisson: poissonRatioCylinderFront,
            setPoisson: setPoissonRatioCylinderFront,
            density: densityCylinderFront,
            setDensity: setDensityCylinderFront,
        },
        {
            key: 'sphere',
            label: 'Impactor Sphere',
            enabledFor: ['sphere'],
            young: youngModulusSphere,
            setYoung: setYoungModulusSphere,
            poisson: poissonRatioSphere,
            setPoisson: setPoissonRatioSphere,
            density: densitySphere,
            setDensity: setDensitySphere,
        },
        {
            key: 'wall',
            label: 'Wall',
            enabledFor: ['cylinder', 'sphere'],
            young: youngModulusWall,
            setYoung: setYoungModulusWall,
            poisson: poissonRatioWall,
            setPoisson: setPoissonRatioWall,
            density: densityWall,
            setDensity: setDensityWall,
        },
    ];
    const updateVector = (index, value) => {
        const newVec = [...velocityVector];
        newVec[index] = value;
        setVelocityVector(newVec);
    };
    const handlePartSelect = (part) => {
        const impactPart = {
            ...part,
            impactPattern: '3x3',
            impactHeight: 200,
            impactVelocityVector: velocityVector,
            impactorType: 'sphere',
            impactorDiameter: 10,
            impactorWeight: 100
        };
        const index = selectedParts.findIndex((p) => p.id === part.id);
        let updatedParts;
        if (index >= 0) {
            updatedParts = [...selectedParts];
            updatedParts[index] = impactPart;
        }
        else {
            updatedParts = [...selectedParts, impactPart];
        }
        setSelectedParts(updatedParts);
    };
    const handlePartRemove = (id) => {
        setSelectedParts(selectedParts.filter((p) => p.id !== id));
    };
    const handlePatternChange = (id, pattern) => {
        const updated = selectedParts.map((p) => p.id === id ? { ...p, impactPattern: pattern } : p);
        setSelectedParts(updated);
    };
    const handleHeightChange = (id, height) => {
        const updated = selectedParts.map((p) => p.id === id ? { ...p, impactHeight: height } : p);
        setSelectedParts(updated);
    };
    // ✅ 추가: 키워드에 매칭되는 파트 미리 계산 (미리보기용)
    const matchedParts = useMemo(() => {
        const kw = bulkKeyword.trim().toLowerCase();
        if (!kw)
            return [];
        return allPartInfos.filter(p => p.name.toLowerCase().includes(kw) || p.id.toLowerCase().includes(kw));
    }, [bulkKeyword, allPartInfos]);
    // ✅ 추가: 키워드 일괄 적용 버튼
    const handleBulkApply = () => {
        const kw = bulkKeyword.trim().toLowerCase();
        if (!kw)
            return;
        const matched = matchedParts;
        const map = new Map(selectedParts.map(p => [p.id, { ...p }]));
        matched.forEach(p => {
            if (map.has(p.id) || includeNotSelected) {
                const base = map.get(p.id) ?? { ...p };
                map.set(p.id, {
                    ...base,
                    impactPattern: bulkPattern,
                    impactHeight: bulkHeight,
                    impactVelocityVector: velocityVector,
                });
            }
        });
        setSelectedParts(Array.from(map.values()));
    };
    const handleVelocityVectorChange = (id, vector) => {
        const updated = selectedParts.map((p) => p.id === id ? { ...p, impactVelocityVector: vector } : p);
        setSelectedParts(updated);
    };
    const handleImpactorChange = (id, field, value) => {
        const updated = selectedParts.map((p) => p.id === id ? { ...p, [field]: value } : p);
        setSelectedParts(updated);
    };
    const partIDs = selectedParts.map(p => Number(p.id)); // 또는 적절히 파싱
    const initialVelocityXList = partIDs.map(() => velocityVector[0]);
    const initialVelocityYList = partIDs.map(() => velocityVector[1]);
    const initialVelocityZList = partIDs.map(() => velocityVector[2]);
    const locationModes = selectedParts.map(p => p.impactPattern);
    const heightList = selectedParts.map(p => p.impactHeight);
    useEffect(() => {
        if (impactorType === 'cylinder') {
            const mass = calculateCylinderWithFilletMass(frontDiameter, midDiameter, backDiameter, frontHeight, backHeight, densityCylinderFront, densityCylinder);
            setImpactorWeight(Math.round(mass * 1000000) / 1000000);
        }
    }, [impactorType, frontDiameter, midDiameter, backDiameter, frontHeight, backHeight, densityCylinder]);
    useEffect(() => {
        if (impactorType === 'sphere') {
            const mass = calculateSphereMass(impactorDiameter, densitySphere);
            setImpactorWeight(Math.round(mass));
        }
    }, [impactorType, impactorDiameter, densitySphere]);
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uC804\uC704\uCE58 \uBD80\uBD84 \uCDA9\uACA9 \uC2DC\uBBAC\uB808\uC774\uC158" }), _jsx(Paragraph, { children: "\uC120\uD0DD\uB41C \uD30C\uD2B8 \uD639\uC740 \uD2B9\uC815 \uD0A4\uC6CC\uB4DC\uB97C \uD3EC\uD568\uD558\uB294 \uBAA8\uB4E0 \uD30C\uD2B8\uC5D0 \uB300\uD55C \uCDA9\uACA9 \uC2DC\uBBAC\uB808\uC774\uC158\uC744 \uC790\uB3D9\uD654\uD558\uC5EC \uC2E4\uD589\uD569\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                        setKFileName(filename);
                        setAllPartInfos(parts);
                        setSelectedParts([]);
                        setLayerGroups([]);
                        setMidMap(new Map());
                        setUploadedKFile(file ?? null);
                    } }), _jsx(Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allPartInfos, onSelect: handlePartSelect }), _jsx(Divider, {}), _jsx(Title, { level: 5, children: "\uD0A4\uC6CC\uB4DC\uB85C \uC77C\uAD04 \uC635\uC158 \uC801\uC6A9" }), _jsxs(Space, { wrap: true, children: [_jsx(Input, { placeholder: "\uD0A4\uC6CC\uB4DC (id \uB610\uB294 name\uC5D0 \uD3EC\uD568)", value: bulkKeyword, onChange: (e) => setBulkKeyword(e.target.value), style: { width: 200 } }), _jsx(Select, { value: bulkPattern, onChange: (v) => setBulkPattern(v), style: { width: 100 }, children: dotPatterns.map(p => _jsx(Option, { value: p, children: p }, p)) }), _jsx(Select, { value: bulkHeight, onChange: (v) => setBulkHeight(v), style: { width: 120 }, options: heightOptions.map(h => ({ value: h, label: `${h} mm` })) }), _jsx(InputNumber, { value: velocityVector[0], onChange: (v) => updateVector(0, v ?? 0), style: { width: 100 } }), _jsx(InputNumber, { value: velocityVector[1], onChange: (v) => updateVector(1, v ?? 0), style: { width: 100 } }), _jsx(InputNumber, { value: velocityVector[2], onChange: (v) => updateVector(2, v ?? 0), style: { width: 100 } }), _jsx(Checkbox, { checked: includeNotSelected, onChange: (e) => setIncludeNotSelected(e.target.checked), children: "\uC120\uD0DD\uB418\uC9C0 \uC54A\uC740 \uD30C\uD2B8\uB3C4 \uD3EC\uD568" }), _jsx(Button, { type: "primary", onClick: handleBulkApply, children: "\uC77C\uAD04 \uC801\uC6A9" })] }), bulkKeyword && (_jsx("div", { style: { marginTop: 8 }, children: _jsxs(Text, { type: "secondary", children: ["\uD0A4\uC6CC\uB4DC \"", _jsx("b", { children: bulkKeyword }), "\" \uB85C \uB9E4\uCE6D\uB41C \uD30C\uD2B8: ", _jsx(Tag, { color: "blue", children: matchedParts.length }), "\uAC1C"] }) })), _jsx(Divider, {}), _jsx(PartDropWeightImpactTable, { parts: selectedParts, onRemove: handlePartRemove, onPatternChange: handlePatternChange, onHeightChange: handleHeightChange, onImpactorChange: handleImpactorChange, onVelocityVectorChange: handleVelocityVectorChange }), _jsx(Divider, {}), _jsx(Divider, { orientation: "left", orientationMargin: "0", children: "\u2699 \uC2DC\uBBAC\uB808\uC774\uC158 \uC124\uC815" }), _jsxs("div", { style: { display: 'flex', flexWrap: 'wrap', gap: 16 }, children: [_jsx(InputNumber, { addonBefore: "tFinal (s)", value: tFinal, onChange: (v) => setTFinal(v ?? 0), step: 0.001, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "dt (s)", value: dt, onChange: (v) => setDt(v ?? 0), step: 1e-6, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Mesh Size (mm)", value: meshSize, onChange: (v) => setMeshSize(v ?? 0), style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Offset Distance (mm)", value: offsetDistance, onChange: (v) => setOffsetDistance(v ?? 0), step: 0.01, style: { width: 220 } })] }), _jsx(Divider, {}), _jsx(Title, { level: 3, children: "\uC2DC\uBBAC\uB808\uC774\uC158 \uC804\uC5ED \uC635\uC158 - \uC7AC\uB8CC \uBB3C\uC131" }), _jsxs("div", { style: { display: 'flex', gap: 16, alignItems: 'center', marginBottom: 16 }, children: [_jsx(Text, { strong: true, children: "Impactor Type \uC120\uD0DD:" }), _jsx(Select, { value: impactorType, onChange: setImpactorType, style: { width: 200 }, options: [
                                { value: 'cylinder', label: 'Cylinder' },
                                { value: 'sphere', label: 'Sphere' }
                            ] })] }), _jsx("div", { style: { overflowX: 'auto' }, children: _jsxs("table", { style: { borderCollapse: 'collapse', width: '100%', minWidth: 900 }, children: [_jsx("thead", { children: _jsxs("tr", { children: [_jsx("th", { style: cellStyle, children: "\uC704\uCE58" }), _jsx("th", { style: cellStyle, children: "Young's Modulus (MPa)" }), _jsx("th", { style: cellStyle, children: "Poisson Ratio" }), _jsx("th", { style: cellStyle, children: "Density (ton/mm\u00B3)" })] }) }), _jsx("tbody", { children: materialTableData.map((row) => {
                                    const isEnabled = row.enabledFor?.includes(impactorType) ?? true;
                                    return (_jsxs("tr", { children: [_jsx("td", { style: cellStyle, children: _jsx("strong", { children: row.label }) }), _jsx("td", { style: cellStyle, children: _jsx(InputNumber, { value: row.young, onChange: (v) => row.setYoung(v ?? 0), disabled: !isEnabled, style: { width: '100%' } }) }), _jsx("td", { style: cellStyle, children: _jsx(InputNumber, { value: row.poisson, min: 0, max: 0.5, step: 0.001, onChange: (v) => row.setPoisson(v ?? 0), disabled: !isEnabled, style: { width: '100%' } }) }), _jsx("td", { style: cellStyle, children: _jsx(InputNumber, { value: row.density, onChange: (v) => row.setDensity(v ?? 0), disabled: !isEnabled, style: { width: '100%' } }) })] }, row.key));
                                }) })] }) }), impactorType === 'sphere' ? (_jsxs("div", { style: { display: 'flex', gap: 16, marginTop: 16 }, children: [_jsx(InputNumber, { addonBefore: "Impactor \uC9C1\uACBD (mm)", value: impactorDiameter, onChange: (v) => setImpactorDiameter(v ?? 0), min: 0, style: { width: 250 } }), _jsx(InputNumber, { addonBefore: "Impactor \uC9C8\uB7C9 (g)", value: impactorWeight, disabled: true, onChange: (v) => setImpactorWeight(v ?? 0), min: 0, style: { width: 250 } })] })) : (_jsxs("div", { style: { display: 'flex', flexWrap: 'wrap', gap: 16, marginTop: 16 }, children: [_jsx(InputNumber, { addonBefore: "Front Diameter (mm)", value: frontDiameter, onChange: (v) => setFrontDiameter(v ?? 0), min: 0, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Mid Diameter (mm)", value: midDiameter, onChange: (v) => setMidDiameter(v ?? 0), min: 0, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Back Diameter (mm)", value: backDiameter, onChange: (v) => setBackDiameter(v ?? 0), min: 0, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Front Height (mm)", value: frontHeight, onChange: (v) => setFrontHeight(v ?? 0), min: 0, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Back Height (mm)", value: backHeight, onChange: (v) => setBackHeight(v ?? 0), min: 0, style: { width: 220 } }), _jsx(InputNumber, { addonBefore: "Impactor \uC9C8\uB7C9 (g)", value: impactorWeight, disabled: true, onChange: (v) => setImpactorWeight(v ?? 0), min: 0, style: { width: 220 } })] })), _jsx(Divider, {}), _jsx("div", { style: { marginTop: 16, marginBottom: 16, textAlign: 'center', display: 'flex', flexDirection: 'column', gap: 16 }, children: _jsx(ExportMeshModifierButton, { kFile: uploadedKFile, kFileName: kFileName || 'UNKNOWN.k', optionFileGenerator: () => generateDropWeightImpactTestbyPartsOptionFile(kFileName || 'UNKNOWN.k', partIDs, initialVelocityXList, initialVelocityYList, initialVelocityZList, locationModes, heightList, tFinal, dt, impactorType === 'cylinder' ? densityCylinder : densitySphere, impactorType === 'cylinder' ? youngModulusCylinder : youngModulusSphere, impactorType === 'cylinder' ? poissonRatioCylinder : poissonRatioSphere, impactorType, meshSize, impactorType === 'cylinder' ? youngModulusCylinderFront : youngModulusSphere, impactorType === 'cylinder' ? densityCylinderFront : densitySphere, impactorType === 'cylinder' ? poissonRatioCylinderFront : poissonRatioSphere, youngModulusWall, densityWall, poissonRatioWall, [frontDiameter / 2.0, midDiameter / 2.0, frontHeight, backHeight, backDiameter / 2.0], [impactorDiameter / 2.0], offsetDistance), optionFileName: "drop_weight_impact.txt" }) })] }) }));
};
export default AllPointsDropWeightImpactGenerator;
function calculateCylinderWithFilletMass(d1, d2, d3, h1, h2, densityFront, // ton/mm³
densityBack // ton/mm³
) {
    const r1 = d1 / 2;
    const r2 = d2 / 2;
    const r3 = d3 / 2;
    const fillet1Height = r2 - r1;
    const fillet2Height = r3 - r2;
    // Front: Cylinder + Fillet (cone)
    const volumeFrontCylinder = Math.PI * r1 * r1 * h1;
    const volumeFillet1 = (1 / 3) * Math.PI * fillet1Height * (r1 ** 2 + r1 * r2 + r2 ** 2);
    // Back: Cylinder + Fillet (cone)
    const volumeBackCylinder = Math.PI * r3 * r3 * h2;
    const volumeFillet2 = (1 / 3) * Math.PI * fillet2Height * (r2 ** 2 + r2 * r3 + r3 ** 2);
    const frontVolume = volumeFrontCylinder + volumeFillet1;
    const backVolume = volumeBackCylinder + volumeFillet2;
    const massTon = frontVolume * densityFront + backVolume * densityBack;
    return massTon * 1e6; // convert to g
}
function calculateSphereMass(diameter, density) {
    const radius = diameter / 2;
    const volume = (4 / 3) * Math.PI * Math.pow(radius, 3);
    const massGram = volume * density * 1e6;
    return massGram;
}
