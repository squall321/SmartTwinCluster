import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState, useEffect } from 'react';
import { Typography, Form, InputNumber, Select, Input, Divider, Button, Row, Col, Card } from 'antd';
const { Text } = Typography;
import BaseLayout from '../layouts/BaseLayout';
import DynaFilePartVisualizerComponent from '../components/DynaFilePartVisualizerComponent';
import ImpactorSelectorComponent from '../components/downloader/ImpactSelectorComponent';
import MultipleStlViewerComponent from '../components/MultipleStlViewerComponent';
import * as BABYLON from '@babylonjs/core';
const { Title, Paragraph } = Typography;
const DropWeightImpactTestGenerator = () => {
    const [kfile, setKFile] = useState(null);
    const [partId, setPartId] = useState(null);
    const [stlUrl, setStlUrl] = useState(null);
    const [impactorUrl, setImpactorUrl] = useState(null);
    const [impactPoints, setImpactPoints] = useState([]);
    const [heights, setHeights] = useState([]);
    const [targetBoundingBox, setTargetBoundingBox] = useState(null);
    const [tFinal, setTFinal] = useState(0.001);
    const [youngModulus, setYoungModulus] = useState(201e9);
    const [poissonRatio, setPoissonRatio] = useState(0.3);
    const [density, setDensity] = useState(2700);
    const [youngModulusDamper, setYoungModulusDamper] = useState(70e9);
    const [poissonRatioDamper, setPoissonRatioDamper] = useState(0.3);
    const [densityDamper, setDensityDamper] = useState(7800);
    const [type, setType] = useState('Sphere');
    const [dimension, setDimension] = useState(0.008);
    const [dimensionDamper, setDimensionDamper] = useState([0.0001, 0.0001, 0.01]);
    const [meshSize, setMeshSize] = useState(0.001);
    const [offsetDistance, setOffsetDistance] = useState(0.00001);
    const [youngModulusFront, setYoungModulusFront] = useState(50e6);
    const [densityFront, setDensityFront] = useState(2000);
    const [poissonRatioFront, setPoissonRatioFront] = useState(0.3);
    const [youngModulusWall, setYoungModulusWall] = useState(70e9);
    const [densityWall, setDensityWall] = useState(7800);
    const [poissonRatioWall, setPoissonRatioWall] = useState(0.3);
    const [cylinderDimensions, setCylinderDimensions] = useState([0.008, 0.01, 0.005, 0.02, 0.012]);
    useEffect(() => {
        if (!stlUrl)
            return;
        const engine = new BABYLON.NullEngine();
        const scene = new BABYLON.Scene(engine);
        BABYLON.SceneLoader.ImportMeshAsync(null, '', stlUrl, scene, undefined, '.stl')
            .then(result => {
            const mesh = result.meshes[0];
            mesh.computeWorldMatrix(true);
            mesh.refreshBoundingInfo();
            const bounds = mesh.getBoundingInfo().boundingBox;
            setTargetBoundingBox({
                min: bounds.minimumWorld.clone(),
                max: bounds.maximumWorld.clone(),
            });
        })
            .catch(err => {
            console.error('❌ Drop STL bounding box 불러오기 실패:', err);
        });
    }, [stlUrl]);
    useEffect(() => {
        setHeights(impactPoints.map(() => 0.2));
    }, [impactPoints]);
    const handleDownload = () => {
        if (!kfile || !impactPoints.length)
            return;
        const locationX = impactPoints.map(p => p.dx.toFixed(5)).join(',');
        const locationY = impactPoints.map(p => p.dy.toFixed(5)).join(',');
        const zeros = impactPoints.map(() => '0.00').join(',');
        const heightLine = heights.map(h => h.toFixed(5)).join(',');
        const lines = [
            '*Inputfile',
            kfile.name,
            '*Mode',
            'DROP_WEIGHT_IMPACT_TEST,1',
            '**DropWeightImpactTest,1',
            'BoundaryDistance,0.0',
            `LocationX,${locationX}`,
            `LocationY,${locationY}`,
            `InitialVelocityX,${zeros}`,
            `InitialVelocityY,${zeros}`,
            `InitialVelocityZ,${zeros}`,
            `Height,${heightLine}`,
            `tFinal,${tFinal}`,
            `YoungModulusDamper,${youngModulusDamper}`,
            `PoissonRatioDamper,${poissonRatioDamper}`,
            `Density,${density}`,
            `YoungModulus,${youngModulus}`,
            `DensityDamper,${densityDamper}`,
            `PoissonRatio,${poissonRatio}`,
            `Type,${type}`,
            `DimensionDamper,${dimensionDamper.join(',')}`,
            `MeshSize,${meshSize}`,
        ];
        if (type === 'Cylinder') {
            lines.push(`YoungModulusImpactorFront,${youngModulusFront}`, `DensityImpactorFront,${densityFront}`, `PoissonRatioImpactorFront,${poissonRatioFront}`, `YoungModulusWall,${youngModulusWall}`, `DensityWall,${densityWall}`, `PoissonRatioWall,${poissonRatioWall}`);
            lines.push(`Dimension,${cylinderDimensions.join(',')}`);
        }
        else {
            lines.push(`Dimension,${dimension}`);
        }
        lines.push(`OffsetDistance,${offsetDistance}`);
        lines.push('**EndDropWeightImpactTest');
        lines.push('*End');
        const blob = new Blob([lines.join('\n')], { type: 'text/plain;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = 'DropWeightImpactTestInput.txt';
        link.click();
        URL.revokeObjectURL(url);
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\u2699\uFE0F \uBD80\uBD84 \uCDA9\uACA9 \uC0DD\uC131\uAE30" }), _jsx(Paragraph, { children: "LS-DYNA\uC758 K \uD30C\uC77C\uB85C\uBD80\uD130 \uD2B9\uC815 Part\uB97C \uC120\uD0DD\uD558\uACE0, \uD574\uB2F9 \uC601\uC5ED\uC5D0 \uB300\uD55C \uBD80\uBD84 \uCDA9\uACA9 \uC2DC\uD5D8\uC744 \uC0DD\uC131\uD558\uAE30 \uC704\uD55C STL \uD615\uC0C1\uC744 \uCD94\uCD9C \uBC0F \uC2DC\uAC01\uD654\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(DynaFilePartVisualizerComponent, { onReady: ({ kfile, partId, stlUrl }) => {
                        setKFile(kfile);
                        setPartId(partId);
                        setStlUrl(stlUrl);
                    } }), kfile && partId && stlUrl && (_jsxs(Paragraph, { type: "secondary", style: { marginTop: 24 }, children: ["\uD604\uC7AC \uC120\uD0DD\uB41C \uD30C\uC77C: ", _jsx("strong", { children: kfile.name }), _jsx("br", {}), "\uC120\uD0DD\uB41C Part ID: ", _jsx("strong", { children: partId }), _jsx("br", {})] })), _jsx(ImpactorSelectorComponent, { onChange: (url, points) => {
                        setImpactorUrl(url);
                        setImpactPoints(points);
                    }, targetBoundingBox: targetBoundingBox }), impactorUrl && impactPoints.length > 0 && stlUrl && (_jsx(MultipleStlViewerComponent, { viewDirection: "top", models: [
                        {
                            url: `${impactorUrl}`,
                            positions: impactPoints.map(p => new BABYLON.Vector3(p.dx, 0, p.dy)),
                        },
                        {
                            url: `${stlUrl}`,
                            positions: [
                                new BABYLON.Vector3(0, targetBoundingBox ? -5 * targetBoundingBox.max.z : -100, 0),
                            ],
                        },
                    ] })), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "\u2699\uFE0F \uCDA9\uACA9 \uC870\uAC74 \uBC0F \uC2DC\uBBAC\uB808\uC774\uC158 \uC785\uB825\uD30C\uC77C \uC0DD\uC131" }), impactPoints.map((p, idx) => (_jsx(Card, { size: "small", style: { marginBottom: 12, background: '#fafafa', borderColor: '#d9d9d9' }, children: _jsxs(Row, { align: "middle", gutter: 16, children: [_jsxs(Col, { flex: "auto", children: [_jsxs(Text, { strong: true, children: ["#", idx + 1] }), " \u27A4 (x: ", p.dx.toFixed(4), ", y: ", p.dy.toFixed(4), ")"] }), _jsx(Col, { children: _jsx(InputNumber, { value: heights[idx], min: 0, step: 0.01, addonBefore: "Height (m)", onChange: (val) => setHeights((prev) => prev.map((v, i) => (i === idx ? val || 0 : v))) }) })] }) }, idx))), _jsx(Divider, { orientation: "left", children: "\uD83D\uDD28 \uCDA9\uACA9\uC790 \uC124\uC815 (Impactor)" }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Impactor Type (\uCDA9\uACA9\uC790 \uC885\uB958)", children: _jsxs(Select, { value: type, onChange: setType, style: { width: '100%' }, children: [_jsx(Select.Option, { value: "Sphere", children: "Sphere" }), _jsx(Select.Option, { value: "Cylinder", children: "Cylinder" })] }) }) }), _jsxs(Form, { layout: "vertical", style: { marginTop: 16 }, children: [_jsx(Row, { gutter: 16, children: _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "\u23F1\uFE0F tFinal (\uCD1D \uD574\uC11D \uC2DC\uAC04)", children: _jsx(InputNumber, { value: tFinal, step: 0.0001, onChange: (val) => setTFinal(val || 0), style: { width: '100%' } }) }) }) }), _jsx(Divider, { orientation: "left", children: "\uD83E\uDDF1 \uC7AC\uB8CC \uC18D\uC131 (Target Material)" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Young's Modulus (\uC7AC\uB8CC \uC601\uB960)", children: _jsx(InputNumber, { value: youngModulus, onChange: (val) => setYoungModulus(val || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Poisson's Ratio (\uC7AC\uB8CC \uD3EC\uC544\uC1A1\uBE44)", children: _jsx(InputNumber, { value: poissonRatio, onChange: (val) => setPoissonRatio(val || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Density (\uC7AC\uB8CC \uBC00\uB3C4)", children: _jsx(InputNumber, { value: density, onChange: (val) => setDensity(val || 0), style: { width: '100%' } }) }) })] }), _jsx(Divider, { orientation: "left", children: "\uD83E\uDDFD \uB310\uD37C \uC18D\uC131 (Damper Material)" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Young's Modulus (\uB310\uD37C \uC601\uB960)", children: _jsx(InputNumber, { value: youngModulusDamper, onChange: (val) => setYoungModulusDamper(val || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Poisson's Ratio (\uB310\uD37C \uD3EC\uC544\uC1A1\uBE44)", children: _jsx(InputNumber, { value: poissonRatioDamper, onChange: (val) => setPoissonRatioDamper(val || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Density (\uB310\uD37C \uBC00\uB3C4)", children: _jsx(InputNumber, { value: densityDamper, onChange: (val) => setDensityDamper(val || 0), style: { width: '100%' } }) }) })] }), type === 'Cylinder' && (_jsxs(_Fragment, { children: [_jsx(Divider, { orientation: "left", children: "\u2699\uFE0F Cylinder \uC635\uC158" }), _jsx(Row, { gutter: 16, children: _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Offset Distance (\uC704\uCE58 \uC624\uD504\uC14B)", children: _jsx(InputNumber, { value: offsetDistance, onChange: v => setOffsetDistance(v || 0), style: { width: '100%' } }) }) }) }), _jsx(Divider, { orientation: "left", children: "\uD83E\uDDF1 Impactor Front \uBB3C\uC131 (\uC804\uBA74 \uC7AC\uB8CC)" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Young's Modulus (\uC804\uBA74 \uC601\uB960)", children: _jsx(InputNumber, { value: youngModulusFront, onChange: v => setYoungModulusFront(v || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Density (\uC804\uBA74 \uBC00\uB3C4)", children: _jsx(InputNumber, { value: densityFront, onChange: v => setDensityFront(v || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Poisson's Ratio (\uC804\uBA74 \uD3EC\uC544\uC1A1\uBE44)", children: _jsx(InputNumber, { value: poissonRatioFront, onChange: v => setPoissonRatioFront(v || 0), style: { width: '100%' } }) }) })] }), _jsx(Divider, { orientation: "left", children: "\uD83E\uDDF1 Wall \uBB3C\uC131 (\uCDA9\uB3CC \uBCBD\uCCB4 \uC7AC\uB8CC)" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Young's Modulus (\uBCBD\uCCB4 \uC601\uB960)", children: _jsx(InputNumber, { value: youngModulusWall, onChange: v => setYoungModulusWall(v || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Density (\uBCBD\uCCB4 \uBC00\uB3C4)", children: _jsx(InputNumber, { value: densityWall, onChange: v => setDensityWall(v || 0), style: { width: '100%' } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Poisson's Ratio (\uBCBD\uCCB4 \uD3EC\uC544\uC1A1\uBE44)", children: _jsx(InputNumber, { value: poissonRatioWall, onChange: v => setPoissonRatioWall(v || 0), style: { width: '100%' } }) }) })] }), _jsx(Divider, { orientation: "left", children: "\uD83D\uDCCF Cylinder Dimensions (r, outerR, h1, h2, backR)" }), _jsx(Row, { gutter: 16, children: ['반지름 r', '외부 반지름 outerR', '높이 h1', '높이 h2', '후면 반지름 backR'].map((label, index) => (_jsx(Col, { span: 4, children: _jsx(Form.Item, { label: label, children: _jsx(InputNumber, { value: cylinderDimensions[index], min: 0, step: 0.001, onChange: (val) => {
                                                    const updated = [...cylinderDimensions];
                                                    updated[index] = val ?? 0;
                                                    setCylinderDimensions(updated);
                                                } }) }) }, label))) })] })), type === 'Sphere' && (_jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Impactor Radius (\uAD6C\uCCB4 \uBC18\uC9C0\uB984)", children: _jsx(Input, { value: dimension.toString(), onChange: e => setDimension(parseFloat(e.target.value)) }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Damper Size (\uB310\uD37C \uD06C\uAE30: width, height, offsetDistance)", children: _jsx(Input, { value: dimensionDamper.join(','), onChange: e => {
                                                const parts = e.target.value.split(',').map(Number);
                                                if (parts.length === 3)
                                                    setDimensionDamper([parts[0], parts[1], parts[2]]);
                                            } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Mesh Size (\uBA54\uC2DC \uD574\uC0C1\uB3C4)", children: _jsx(InputNumber, { value: meshSize, onChange: (val) => setMeshSize(val || 0), style: { width: '100%' } }) }) })] })), _jsx(Button, { type: "primary", onClick: handleDownload, style: { marginTop: 24 }, children: "\uD83D\uDCC4 \uC785\uB825\uD30C\uC77C \uC800\uC7A5" })] })] }) }));
};
export default DropWeightImpactTestGenerator;
