import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
// LayeredModelEditor.tsx (2D Plotly + AntD, extended features)
import { useState } from 'react';
import { Row, Col, List, Button, Form, InputNumber, Input, Typography, Modal, Popconfirm, Space, Divider } from 'antd';
import Plot from 'react-plotly.js';
import { Table } from 'antd';
const { Title } = Typography;
const defaultLayer = () => ({
    name: `Layer ${Date.now()}`,
    location: [0, 0],
    length: [3.315, 4.035],
    thickness: 0.08,
    meshType: 'Tetra',
    meshPath: 'PackageMesh',
    materialID: 1,
    mirror: false,
    rotation: 0,
    isTop: false,
    surfaceTension: 480.0,
    cylinders: [],
    boxes: [],
});
const LayeredModelEditor = () => {
    const [layers, setLayers] = useState([]);
    const [selectedIndex, setSelectedIndex] = useState(-1);
    const [patternModalOpen, setPatternModalOpen] = useState(false);
    const [patternCols, setPatternCols] = useState(4);
    const [patternRows, setPatternRows] = useState(4);
    const [patternPitchX, setPatternPitchX] = useState(0.35);
    const [patternPitchY, setPatternPitchY] = useState(0.35);
    const [patternRadius, setPatternRadius] = useState(0.1);
    const [zoomRange, setZoomRange] = useState({});
    const addLayer = () => {
        const newLayer = defaultLayer();
        setLayers([...layers, newLayer]);
        setSelectedIndex(layers.length);
    };
    const removeLayer = (idx) => {
        const newLayers = layers.filter((_, i) => i !== idx);
        setLayers(newLayers);
        if (selectedIndex === idx)
            setSelectedIndex(-1);
        else if (selectedIndex > idx)
            setSelectedIndex(selectedIndex - 1);
    };
    const renameLayer = (idx, name) => {
        const newLayers = [...layers];
        newLayers[idx].name = name;
        setLayers(newLayers);
    };
    const updateLayer = (index, updated) => {
        const newLayers = [...layers];
        newLayers[index] = { ...newLayers[index], ...updated };
        setLayers(newLayers);
    };
    const addSingleCylinder = () => {
        const current = layers[selectedIndex];
        const newCyl = { x: 0, y: 0, r: 0.1, active: true };
        updateLayer(selectedIndex, { cylinders: [...current.cylinders, newCyl] });
    };
    const toggleCylinder = (index) => {
        const layer = layers[selectedIndex];
        const newCylinders = [...layer.cylinders];
        newCylinders[index].active = !newCylinders[index].active;
        updateLayer(selectedIndex, { cylinders: newCylinders });
    };
    const generatePattern = () => {
        const baseX = -((patternCols - 1) * patternPitchX) / 2;
        const baseY = -((patternRows - 1) * patternPitchY) / 2;
        const newCylinders = [];
        for (let i = 0; i < patternCols; i++) {
            for (let j = 0; j < patternRows; j++) {
                newCylinders.push({
                    x: baseX + i * patternPitchX,
                    y: baseY + j * patternPitchY,
                    r: patternRadius,
                    active: true,
                });
            }
        }
        const current = layers[selectedIndex];
        updateLayer(selectedIndex, { cylinders: [...current.cylinders, ...newCylinders] });
        setPatternModalOpen(false);
    };
    const generateScript = () => {
        return layers.map(layer => {
            const lines = [
                `*Layer,${layer.name}`,
                `Location,${layer.location.join(',')}`,
                `Length,${layer.length.map(v => v.toExponential(3)).join(',')}`,
                `Thickness,${layer.thickness.toExponential(3)}`,
                `MeshGenerationType,Solid,${layer.meshType}`,
                `MeshPath,${layer.meshPath}`,
                `MaterialID,${layer.materialID}`,
                `Mirror,${layer.mirror}`,
                `Rotation,${layer.rotation}`,
                `IsTop,${layer.isTop}`,
                `SurfaceTension,${layer.surfaceTension}`,
                ...layer.cylinders.filter(c => c.active !== false).map(c => `Cylinder,${c.x.toExponential(3)},${c.y.toExponential(3)},${c.r.toExponential(3)}`),
                ...layer.boxes.map(b => `Box,${b.xmin.toExponential(3)},${b.ymin.toExponential(3)},${b.xmax.toExponential(3)},${b.ymax.toExponential(3)}`),
            ];
            return lines.join('\n');
        }).join('\n\n');
    };
    const getPlotData = () => {
        if (selectedIndex < 0)
            return [];
        const layer = layers[selectedIndex];
        const [cx, cy] = layer.location;
        const [lx, ly] = layer.length;
        const halfX = lx / 2;
        const halfY = ly / 2;
        const x0 = cx - halfX;
        const x1 = cx + halfX;
        const y0 = cy - halfY;
        const y1 = cy + halfY;
        const active = layer.cylinders.filter(c => c.active !== false);
        const inactive = layer.cylinders.filter(c => c.active === false);
        return [
            {
                x: active.map(c => c.x),
                y: active.map(c => c.y),
                mode: 'markers',
                marker: { size: active.map(c => c.r * 200), color: 'red', opacity: 0.6 },
                type: 'scatter',
                name: 'Active Cylinders',
                customdata: active.map((_, i) => i),
            },
            {
                x: inactive.map(c => c.x),
                y: inactive.map(c => c.y),
                mode: 'markers',
                marker: { size: inactive.map(c => c.r * 200), color: 'gray', opacity: 0.3 },
                type: 'scatter',
                name: 'Inactive Cylinders',
                customdata: inactive.map((_, i) => i),
            },
            {
                type: 'scatter',
                mode: 'lines',
                x: [x0, x1, x1, x0, x0],
                y: [y0, y0, y1, y1, y0],
                line: { color: 'blue' },
                name: 'Layer Boundary'
            },
        ];
    };
    const handlePointClick = (e) => {
        if (!e.points || e.points.length === 0)
            return;
        const pt = e.points[0];
        const idx = pt.pointIndex;
        const traceName = pt.data.name;
        const layer = layers[selectedIndex];
        if (traceName.includes('Cylinder')) {
            const all = layer.cylinders;
            const allIndices = traceName.includes('Inactive')
                ? layer.cylinders.map((c, i) => (c.active === false ? i : -1)).filter(i => i !== -1)
                : layer.cylinders.map((c, i) => (c.active !== false ? i : -1)).filter(i => i !== -1);
            const realIndex = allIndices[idx];
            toggleCylinder(realIndex);
        }
    };
    return (_jsxs(Row, { gutter: 16, children: [_jsxs(Col, { span: 4, children: [_jsx(Title, { level: 4, children: "Layers" }), _jsx(List, { bordered: true, dataSource: layers, renderItem: (item, idx) => (_jsx(List.Item, { style: { background: selectedIndex === idx ? '#e6f7ff' : '' }, children: _jsxs(Space, { style: { width: '100%', justifyContent: 'space-between' }, children: [_jsx(Input, { value: item.name, onChange: e => renameLayer(idx, e.target.value), onClick: () => setSelectedIndex(idx), size: "small" }), _jsx(Popconfirm, { title: "Delete this layer?", onConfirm: () => removeLayer(idx), children: _jsx(Button, { size: "small", danger: true, children: "Delete" }) })] }) })) }), _jsx(Button, { type: "primary", block: true, onClick: addLayer, style: { marginTop: 8 }, children: "+ Add Layer" })] }), _jsx(Col, { span: 10, children: selectedIndex >= 0 && (_jsxs(_Fragment, { children: [_jsx(Title, { level: 4, children: "Layer Settings" }), _jsx(Form, { layout: "vertical", children: _jsxs(Row, { gutter: 8, children: [_jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Location (X, Y)", children: _jsxs(Input.Group, { compact: true, children: [_jsx(InputNumber, { value: layers[selectedIndex].location[0], onChange: v => updateLayer(selectedIndex, {
                                                            location: [v ?? 0, layers[selectedIndex].location[1]],
                                                        }), style: { width: '50%' } }), _jsx(InputNumber, { value: layers[selectedIndex].location[1], onChange: v => updateLayer(selectedIndex, {
                                                            location: [layers[selectedIndex].location[0], v ?? 0],
                                                        }), style: { width: '50%' } })] }) }) }), _jsx(Col, { span: 12, children: _jsx(Form.Item, { label: "Length (X, Y)", children: _jsxs(Input.Group, { compact: true, children: [_jsx(InputNumber, { value: layers[selectedIndex].length[0], onChange: v => updateLayer(selectedIndex, {
                                                            length: [v ?? 1, layers[selectedIndex].length[1]],
                                                        }), style: { width: '50%' } }), _jsx(InputNumber, { value: layers[selectedIndex].length[1], onChange: v => updateLayer(selectedIndex, {
                                                            length: [layers[selectedIndex].length[0], v ?? 1],
                                                        }), style: { width: '50%' } })] }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { label: "Thickness", children: _jsx(InputNumber, { value: layers[selectedIndex].thickness, onChange: val => updateLayer(selectedIndex, { thickness: val ?? 0.01 }), style: { width: '100%' } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { label: "Surface Tension", children: _jsx(InputNumber, { value: layers[selectedIndex].surfaceTension, onChange: val => updateLayer(selectedIndex, { surfaceTension: val ?? 0 }), style: { width: '100%' } }) }) }), _jsx(Col, { span: 8, children: _jsx(Form.Item, { label: "Cylinders", children: _jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsx(Button, { onClick: () => setPatternModalOpen(true), block: true, children: "Add Pattern" }), _jsx(Button, { onClick: addSingleCylinder, block: true, children: "+ Single" })] }) }) })] }) }), _jsx(Divider, {}), _jsx(Title, { level: 5, children: "Cylinder Editor" }), _jsx(Table, { size: "small", scroll: { y: 250 }, rowKey: (_, idx) => `${idx}`, dataSource: layers[selectedIndex].cylinders.map((c, idx) => ({ ...c, key: idx })), pagination: false, columns: [
                                {
                                    title: 'X',
                                    dataIndex: 'x',
                                    render: (value, _, idx) => (_jsx(InputNumber, { value: value, onChange: (val) => {
                                            const newCyls = [...layers[selectedIndex].cylinders];
                                            newCyls[idx].x = val ?? 0;
                                            updateLayer(selectedIndex, { cylinders: newCyls });
                                        } })),
                                },
                                {
                                    title: 'Y',
                                    dataIndex: 'y',
                                    render: (value, _, idx) => (_jsx(InputNumber, { value: value, onChange: (val) => {
                                            const newCyls = [...layers[selectedIndex].cylinders];
                                            newCyls[idx].y = val ?? 0;
                                            updateLayer(selectedIndex, { cylinders: newCyls });
                                        } })),
                                },
                                {
                                    title: 'R',
                                    dataIndex: 'r',
                                    render: (value, _, idx) => (_jsx(InputNumber, { value: value, onChange: (val) => {
                                            const newCyls = [...layers[selectedIndex].cylinders];
                                            newCyls[idx].r = val ?? 0.01;
                                            updateLayer(selectedIndex, { cylinders: newCyls });
                                        } })),
                                },
                                {
                                    title: 'Active',
                                    dataIndex: 'active',
                                    render: (value, _, idx) => (_jsx(Button, { type: value ? 'primary' : 'default', size: "small", onClick: () => toggleCylinder(idx), children: value ? 'On' : 'Off' })),
                                },
                                {
                                    title: 'Action',
                                    render: (_, __, idx) => (_jsx(Button, { danger: true, size: "small", onClick: () => {
                                            const newCyls = layers[selectedIndex].cylinders.filter((_, i) => i !== idx);
                                            updateLayer(selectedIndex, { cylinders: newCyls });
                                        }, children: "Delete" })),
                                },
                            ] })] })) }), _jsxs(Col, { span: 10, children: [_jsx(Title, { level: 4, children: "2D View" }), _jsx("div", { style: { padding: '0 12px' }, children: _jsx(Plot, { data: getPlotData(), onClick: handlePointClick, onRelayout: (event) => {
                                const x = event['xaxis.range[0]'] !== undefined && event['xaxis.range[1]'] !== undefined
                                    ? [event['xaxis.range[0]'], event['xaxis.range[1]']]
                                    : zoomRange.x;
                                const y = event['yaxis.range[0]'] !== undefined && event['yaxis.range[1]'] !== undefined
                                    ? [event['yaxis.range[0]'], event['yaxis.range[1]']]
                                    : zoomRange.y;
                                setZoomRange({ x, y });
                            }, layout: {
                                width: 600,
                                height: 500,
                                title: { text: 'Top View of Layer', font: { size: 16 } },
                                xaxis: {
                                    title: { text: 'X', font: { size: 16 } },
                                    ...(zoomRange.x ? { range: zoomRange.x } : {}),
                                },
                                yaxis: {
                                    title: { text: 'Y', font: { size: 16 } },
                                    ...(zoomRange.y ? { range: zoomRange.y } : {}),
                                    scaleanchor: 'x',
                                },
                                showlegend: true,
                                margin: { t: 50, l: 40, r: 40, b: 40 },
                            }, config: { responsive: true } }) })] }), _jsxs(Col, { span: 24, style: { marginTop: 16 }, children: [_jsx(Title, { level: 4, children: "Generated Script" }), _jsx(Input.TextArea, { rows: 10, value: generateScript(), readOnly: true })] }), _jsx(Modal, { open: patternModalOpen, onCancel: () => setPatternModalOpen(false), onOk: generatePattern, title: "Cylinder Pattern Generator", children: _jsxs(Form, { layout: "vertical", children: [_jsx(Form.Item, { label: "Columns", children: _jsx(InputNumber, { min: 1, value: patternCols, onChange: val => setPatternCols(val || 1) }) }), _jsx(Form.Item, { label: "Rows", children: _jsx(InputNumber, { min: 1, value: patternRows, onChange: val => setPatternRows(val || 1) }) }), _jsx(Form.Item, { label: "Pitch X", children: _jsx(InputNumber, { step: 0.01, value: patternPitchX, onChange: val => setPatternPitchX(val || 0.01) }) }), _jsx(Form.Item, { label: "Pitch Y", children: _jsx(InputNumber, { step: 0.01, value: patternPitchY, onChange: val => setPatternPitchY(val || 0.01) }) }), _jsx(Form.Item, { label: "Radius", children: _jsx(InputNumber, { step: 0.01, value: patternRadius, onChange: val => setPatternRadius(val || 0.01) }) })] }) })] }));
};
export default LayeredModelEditor;
