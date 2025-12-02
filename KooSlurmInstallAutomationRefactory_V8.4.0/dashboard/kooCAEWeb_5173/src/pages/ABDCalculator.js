import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// 앞부분 동일
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Input, Button, Table, Select, message, Typography } from 'antd';
import { DeleteOutlined, ArrowUpOutlined, ArrowDownOutlined, CopyOutlined, SearchOutlined } from '@ant-design/icons';
import { Bar } from '@ant-design/charts';
const { Title, Paragraph } = Typography;
const predefinedMaterials = [
    {
        name: 'CU',
        layers: [
            { name: 'Cu', modulus: 100.0, thickness: 18 },
        ],
    },
    {
        name: 'FPCB',
        layers: [
            { name: 'EMI', modulus: 2.0, thickness: 20 },
            { name: 'Coverlay PI', modulus: 3.0, thickness: 15 },
            { name: 'FCCL-Cu', modulus: 30.0, thickness: 18 },
            { name: 'FCCL-PI', modulus: 3.0, thickness: 20 },
        ],
    },
    {
        name: 'Rigid PCB (Cu 12L)',
        layers: [
            { name: 'Solder Resist Top', modulus: 2.0, thickness: 20 },
            { name: 'Cu Layer 1 (outer)', modulus: 110.0, thickness: 35 },
            { name: 'Prepreg 1', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 2', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 2', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 3', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 3', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 4', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 4', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 5', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 5', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 6', modulus: 110.0, thickness: 12 },
            { name: 'Core Mid', modulus: 20.0, thickness: 150 },
            { name: 'Cu Layer 7', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 6', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 8', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 7', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 9', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 8', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 10', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 9', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 11', modulus: 110.0, thickness: 12 },
            { name: 'Prepreg 10', modulus: 20.0, thickness: 18 },
            { name: 'Cu Layer 12 (outer)', modulus: 110.0, thickness: 35 },
            { name: 'Solder Resist Bot', modulus: 2.0, thickness: 20 },
        ]
    },
    {
        name: 'Foldable OLED Display (세분화)',
        layers: [
            { name: 'Hardcoat', modulus: 5.0, thickness: 10 },
            { name: 'Top PET Film', modulus: 3.5, thickness: 50 },
            { name: 'OCA Adhesive', modulus: 0.1, thickness: 25 },
            { name: 'Circular Polarizer', modulus: 2.0, thickness: 80 },
            { name: 'TFT Substrate', modulus: 20.0, thickness: 20 },
            { name: 'EML Stack (OLED)', modulus: 10.0, thickness: 5 },
            { name: 'PI Substrate', modulus: 3.0, thickness: 25 },
            { name: 'Backplane Encapsulation', modulus: 5.0, thickness: 10 },
        ],
    }
];
const ABDCalculator = () => {
    const [materials, setMaterials] = useState(predefinedMaterials);
    const [layers, setLayers] = useState([]);
    const [selectedMaterial, setSelectedMaterial] = useState('CU');
    const [abdMatrix, setAbdMatrix] = useState([]);
    const [searchTerm, setSearchTerm] = useState('');
    const handleLayerChange = (index, key, value) => {
        const newLayers = [...layers];
        if (key === 'modulus' || key === 'thickness') {
            const num = parseFloat(value);
            if (isNaN(num) || num < 0) {
                message.error('영률과 두께는 0 이상의 숫자여야 합니다.');
                return;
            }
            newLayers[index] = { ...newLayers[index], [key]: num };
        }
        else {
            newLayers[index] = { ...newLayers[index], [key]: value };
        }
        setLayers(newLayers);
    };
    const addPredefinedLayers = () => {
        const material = materials.find(m => m.name === selectedMaterial);
        if (material) {
            setLayers([...layers, ...material.layers]);
        }
    };
    const calculateABD = () => {
        const A = [];
        const B = [];
        const D = [];
        layers.forEach(layer => {
            const { modulus, thickness } = layer;
            A.push(modulus * thickness);
            B.push(modulus * thickness * thickness / 2);
            D.push(modulus * thickness * thickness * thickness / 3);
        });
        setAbdMatrix([A, B, D]);
    };
    const clearLayers = () => setLayers([]);
    const deleteLayer = (index) => setLayers(layers.filter((_, i) => i !== index));
    const moveLayerUp = (index) => {
        if (index === 0)
            return;
        const newLayers = [...layers];
        [newLayers[index - 1], newLayers[index]] = [newLayers[index], newLayers[index - 1]];
        setLayers(newLayers);
    };
    const moveLayerDown = (index) => {
        if (index === layers.length - 1)
            return;
        const newLayers = [...layers];
        [newLayers[index + 1], newLayers[index]] = [newLayers[index], newLayers[index + 1]];
        setLayers(newLayers);
    };
    const copyLayer = (index) => {
        const newLayer = { ...layers[index], name: `L${layers.length + 1}` };
        setLayers([...layers, newLayer]);
    };
    const filteredLayers = layers.filter(layer => layer.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        layer.modulus.toString().includes(searchTerm) ||
        layer.thickness.toString().includes(searchTerm));
    const colors = ['#1890ff', '#ff4d4f', '#52c41a', '#faad14', '#722ed1'];
    const columns = [
        {
            title: '층 이름',
            dataIndex: 'name',
            key: 'name',
            render: (text, record, index) => (_jsx(Input, { value: text, onChange: (e) => handleLayerChange(index, 'name', e.target.value) })),
        },
        {
            title: '영률',
            dataIndex: 'modulus',
            key: 'modulus',
            render: (text, record, index) => (_jsx(Input, { type: "number", step: "any", value: text, onChange: (e) => handleLayerChange(index, 'modulus', e.target.value) })),
        },
        {
            title: '두께',
            dataIndex: 'thickness',
            key: 'thickness',
            render: (text, record, index) => (_jsx(Input, { type: "number", step: "any", value: text, onChange: (e) => handleLayerChange(index, 'thickness', e.target.value) })),
        },
        {
            title: '작업',
            key: 'action',
            render: (text, record, index) => (_jsxs("span", { children: [_jsx(Button, { icon: _jsx(ArrowUpOutlined, {}), onClick: () => moveLayerUp(index), style: { marginRight: 8 } }), _jsx(Button, { icon: _jsx(ArrowDownOutlined, {}), onClick: () => moveLayerDown(index), style: { marginRight: 8 } }), _jsx(Button, { icon: _jsx(CopyOutlined, {}), onClick: () => copyLayer(index), style: { marginRight: 8 } }), _jsx(Button, { icon: _jsx(DeleteOutlined, {}), onClick: () => deleteLayer(index), danger: true })] })),
        },
    ];
    const chartConfig = {
        data: layers,
        xField: 'name',
        yField: 'modulus',
        seriesField: 'name',
        color: colors,
        legend: { position: 'top-left' },
    };
    const abdTotal = {
        key: '합계',
        A: abdMatrix[0]?.reduce((sum, v) => sum + v, 0).toFixed(2),
        B: abdMatrix[1]?.reduce((sum, v) => sum + v, 0).toFixed(2),
        D: abdMatrix[2]?.reduce((sum, v) => sum + v, 0).toFixed(2),
    };
    // 총 두께 합
    const totalThickness = layers.reduce((sum, layer) => sum + layer.thickness, 0);
    // 인장 유효 영률 (단순 평균)
    const effectiveTensileModulus = abdMatrix[0]?.reduce((sum, a) => sum + a, 0) / totalThickness;
    // 굽힘 유효 영률
    const momentDenominator = layers.reduce((sum, layer) => sum + (layer.thickness ** 3) / 12, 0);
    const totalD = abdMatrix[2]?.reduce((sum, v) => sum + v, 0) ?? 0;
    // z 중심 좌표 계산
    const layerCenters = [];
    let zStart = -totalThickness / 2;
    layers.forEach(layer => {
        const center = zStart + layer.thickness / 2;
        layerCenters.push(center);
        zStart += layer.thickness;
    });
    // D (굽힘강성) 계산
    let D_total = 0;
    let I_total = 0;
    for (let i = 0; i < layers.length; i++) {
        const { modulus, thickness } = layers[i];
        const z = layerCenters[i];
        D_total += modulus * thickness * z * z; // E * t * z^2
        I_total += thickness * z * z; // t * z^2
    }
    const effectiveBendingModulus = D_total / I_total; // GPa
    const abdTableData = abdMatrix.length > 0
        ? [
            ...layers.map((_, i) => ({
                key: `L${i + 1}`,
                A: abdMatrix[0][i]?.toFixed(2),
                B: abdMatrix[1][i]?.toFixed(2),
                D: abdMatrix[2][i]?.toFixed(2),
            })),
            abdTotal // 👈 총합 추가
        ]
        : [];
    return (_jsx(BaseLayout, { isLoggedIn: false, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uBCF5\uD569\uC7AC\uB8CC ABD \uD589\uB82C \uACC4\uC0B0\uAE30" }), _jsx(Paragraph, { children: "\uC0AC\uC804 \uC815\uC758\uB41C \uC7AC\uB8CC\uB97C \uBD88\uB7EC\uC624\uAC70\uB098 \uC9C1\uC811 \uC785\uB825\uD558\uC5EC \uC801\uCE35 \uAD6C\uC870\uB97C \uB9CC\uB4E4 \uC218 \uC788\uC73C\uBA70, \uAC01 \uCE35\uC758 \uC601\uB960\uACFC \uB450\uAED8\uB97C \uAE30\uBC18\uC73C\uB85C ABD \uD589\uB82C\uACFC \uC720\uD6A8 \uC778\uC7A5/\uAD7D\uD798 \uC601\uB960\uC744 \uACC4\uC0B0\uD574\uC90D\uB2C8\uB2E4. \uC2DC\uAC01\uC801 \uB2E8\uBA74 \uD45C\uC2DC \uBC0F \uBB3C\uC131 \uADF8\uB798\uD504\uB3C4 \uD568\uAED8 \uC81C\uACF5\uB418\uC5B4 \uAD6C\uC870 \uC124\uACC4\uC640 \uBB3C\uC131 \uBD84\uC11D\uC744 \uC9C1\uAD00\uC801\uC73C\uB85C \uB3C4\uC640\uC90D\uB2C8\uB2E4." }), _jsxs("div", { style: { marginBottom: '20px' }, children: [_jsx(Select, { placeholder: "\uC7AC\uB8CC \uC120\uD0DD", value: selectedMaterial, onChange: (value) => setSelectedMaterial(value), style: { width: 200, marginRight: 10 }, children: materials.map((material, index = 0) => (_jsx(Select.Option, { value: material.name, children: material.name }, index))) }), _jsx(Button, { onClick: addPredefinedLayers, children: "\uCE35 \uCD94\uAC00" }), _jsx(Button, { onClick: clearLayers, danger: true, style: { marginLeft: 10 }, children: "\uC804\uCCB4 \uC0AD\uC81C" }), _jsx(Button, { onClick: calculateABD, style: { marginLeft: 10 }, children: "ABD \uACC4\uC0B0" }), _jsx(Input, { placeholder: "\uAC80\uC0C9", value: searchTerm, onChange: (e) => setSearchTerm(e.target.value), style: { width: 200, marginLeft: 10 }, prefix: _jsx(SearchOutlined, {}) })] }), _jsx(Table, { dataSource: filteredLayers, columns: columns, rowKey: (_, i = 0) => i.toString(), style: { marginTop: 20 } }), _jsx("div", { style: { position: 'relative', height: '400px', border: '1px solid #ccc', marginTop: 20 }, children: (() => {
                        const totalThicknessForDisplay = layers.reduce((sum, layer) => sum + layer.thickness, 0);
                        let currentTop = 0;
                        return layers.map((layer, index = 0) => {
                            const height = (layer.thickness / totalThicknessForDisplay) * 400;
                            const layerDiv = (_jsx("div", { style: {
                                    position: 'absolute',
                                    top: currentTop,
                                    left: 0,
                                    width: '100%',
                                    height: `${height}px`,
                                    backgroundColor: colors[index % colors.length],
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    color: '#fff',
                                    border: '1px solid #000',
                                    fontSize: '0.75em'
                                }, children: layer.name }, index));
                            currentTop += height;
                            return layerDiv;
                        });
                    })() }), abdMatrix.length > 0 && (_jsxs("div", { style: { marginTop: 20 }, children: [_jsx("h3", { children: "ABD \uD589\uB82C:" }), _jsx(Table, { dataSource: abdTableData, columns: [
                                { title: 'Layer', dataIndex: 'key', key: 'key' },
                                { title: 'A', dataIndex: 'A', key: 'A' },
                                { title: 'B', dataIndex: 'B', key: 'B' },
                                { title: 'D', dataIndex: 'D', key: 'D' },
                            ], pagination: false, bordered: true, size: "small" }), _jsxs("div", { style: { marginTop: 20 }, children: [_jsx("h4", { children: "\uC720\uD6A8 \uC601\uB960 \uACC4\uC0B0:" }), _jsxs("p", { children: ["\uC778\uC7A5 \uC720\uD6A8 \uC601\uB960 (E", _jsx("sub", { children: "tensile" }), "): ", _jsx("strong", { children: effectiveTensileModulus?.toFixed(2) })] }), _jsxs("p", { children: ["\uAD7D\uD798 \uC720\uD6A8 \uC601\uB960 (E", _jsx("sub", { children: "bending" }), "): ", _jsx("strong", { children: effectiveBendingModulus?.toFixed(2) })] })] })] })), _jsxs("div", { style: { marginTop: 20 }, children: [_jsx("h3", { children: "\uCE35\uBCC4 \uBB3C\uC131 \uADF8\uB798\uD504:" }), _jsx(Bar, { ...chartConfig })] })] }) }));
};
export default ABDCalculator;
