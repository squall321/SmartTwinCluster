import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import { Layout, Row, Col, Card, InputNumber } from 'antd';
import AntdTable from 'antd/es/table';
import BlockPalette from '../../components/mck/BlockPalette';
import EditorCanvas from '../../components/mck/EditorCanvas';
import PropertyEditor from '../../components/mck/PropertyEditor';
import HarmonicAnalysisPanel from '../../components/mck/HarmonicAnalysisPanel';
import ModalAnalysisPanel from '../../components/mck/ModalAnalysisPanel';
import HarmonicResultsPanel from '../../components/mck/HarmonicResultsPanel';
import TransientAnalysisPanel from '../../components/mck/TransientAnalysisPanel';
import { modalAnalysis } from '../../services/mck/mckSolver';
import { transientResponse } from "../../services/mck/mckSolver";
import { message } from "antd";
import { create, all } from 'mathjs';
import Plot from 'react-plotly.js';
const math = create(all, {});
const { Content } = Layout;
const MckLayout = () => {
    const [selectedTool, setSelectedTool] = useState(null);
    const [massIdCounter, setMassIdCounter] = useState(1);
    const [springIdCounter, setSpringIdCounter] = useState(1);
    const [damperIdCounter, setDamperIdCounter] = useState(1);
    const [fixedIdCounter, setFixedIdCounter] = useState(1);
    const [transientForces, setTransientForces] = useState([]);
    const [transientResults, setTransientResults] = useState(null);
    const [system, setSystem] = useState({
        masses: [],
        springs: [],
        dampers: [],
        forces: [],
        fixedPoints: [],
    });
    const handleDeleteForce = (forceKey) => {
        setTransientForces((prev) => prev.filter((force) => {
            const key = `${force.nodeId}-${force.type}-${force.expression || force.pwmChannel || ""}`;
            return key !== forceKey;
        }));
    };
    const [selectedElement, setSelectedElement] = useState(null);
    const [modalResults, setModalResults] = useState(null);
    const [harmonicResults, setHarmonicResults] = useState(null);
    const handleSelectTool = (tool) => {
        console.log('Selected tool:', tool);
        setSelectedTool(tool);
    };
    const handleClearTool = () => {
        setSelectedTool(null);
    };
    return (_jsx(Layout, { style: { minHeight: '100vh', padding: 10 }, children: _jsxs(Content, { children: [_jsxs(Row, { gutter: [16, 16], children: [_jsx(Col, { flex: "120px", children: _jsx(BlockPalette, { onSelectTool: handleSelectTool }) }), _jsx(Col, { flex: "auto", children: _jsx(EditorCanvas, { selectedTool: selectedTool, onClearTool: handleClearTool, onSelect: setSelectedElement, system: system, setSystem: setSystem, massIdCounter: massIdCounter, setMassIdCounter: setMassIdCounter, springIdCounter: springIdCounter, setSpringIdCounter: setSpringIdCounter, damperIdCounter: damperIdCounter, setDamperIdCounter: setDamperIdCounter, fixedIdCounter: fixedIdCounter, setFixedIdCounter: setFixedIdCounter }) }), _jsx(Col, { flex: "240px", children: _jsx(PropertyEditor, { selected: selectedElement, onChange: (updated) => {
                                    console.log('Updated element:', updated);
                                    setSystem((prev) => {
                                        if (updated.type === 'mass') {
                                            return {
                                                ...prev,
                                                masses: prev.masses.map((m) => m.id === updated.data.id ? updated.data : m),
                                            };
                                        }
                                        else if (updated.type === 'spring') {
                                            return {
                                                ...prev,
                                                springs: prev.springs.map((s) => s.id === updated.data.id ? updated.data : s),
                                            };
                                        }
                                        else if (updated.type === 'damper') {
                                            return {
                                                ...prev,
                                                dampers: prev.dampers.map((d) => d.id === updated.data.id ? updated.data : d),
                                            };
                                        }
                                        else if (updated.type === 'fixed') {
                                            return {
                                                ...prev,
                                                fixedPoints: prev.fixedPoints.map((f) => f.id === updated.data.id ? updated.data : f),
                                            };
                                        }
                                        return prev;
                                    });
                                } }) })] }), _jsx(Row, { style: { marginTop: 16 }, children: _jsx(Col, { span: 24, children: _jsx(Card, { title: "Model Components", size: "small", children: _jsx(AntdTable, { dataSource: [
                                    ...system.masses.map((m) => ({
                                        key: m.id,
                                        id: m.id,
                                        type: 'mass',
                                        from: null,
                                        to: null,
                                        m: m.m,
                                        k: null,
                                        c: null,
                                        x: m.x,
                                        y: m.y,
                                    })),
                                    ...system.springs.map((s) => ({
                                        key: s.id,
                                        id: s.id,
                                        type: 'spring',
                                        from: s.from,
                                        to: s.to,
                                        m: null,
                                        k: s.k,
                                        c: null,
                                    })),
                                    ...system.dampers.map((d) => ({
                                        key: d.id,
                                        id: d.id,
                                        type: 'damper',
                                        from: d.from,
                                        to: d.to,
                                        m: null,
                                        k: null,
                                        c: d.c,
                                    })),
                                    ...system.fixedPoints.map((f) => ({
                                        key: f.id,
                                        id: f.id,
                                        type: 'fixed',
                                        from: null,
                                        to: null,
                                        m: null,
                                        k: null,
                                        c: null,
                                        x: f.x,
                                        y: f.y,
                                    })),
                                ], columns: [
                                    {
                                        title: 'ID',
                                        dataIndex: 'id',
                                        key: 'id',
                                        width: 80,
                                        render: (val) => val
                                            ?.replace(/^mass-/, '')
                                            .replace(/^spring-/, '')
                                            .replace(/^damper-/, '')
                                            .replace(/^fixed-/, ''),
                                    },
                                    {
                                        title: 'Type',
                                        dataIndex: 'type',
                                        key: 'type',
                                        width: 80,
                                    },
                                    {
                                        title: 'From',
                                        dataIndex: 'from',
                                        key: 'from',
                                        width: 80,
                                        render: (val) => (val ? val.replace(/^mass-/, '') : '-'),
                                    },
                                    {
                                        title: 'To',
                                        dataIndex: 'to',
                                        key: 'to',
                                        width: 80,
                                        render: (val) => (val ? val.replace(/^mass-/, '') : '-'),
                                    },
                                    {
                                        title: 'Mass (M)',
                                        dataIndex: 'm',
                                        key: 'm',
                                        width: 100,
                                        render: (val, record) => record.type === 'mass' ? (_jsx(InputNumber, { min: 0, value: val, size: "small", style: { width: '100%' }, onChange: (newVal) => {
                                                setSystem((prev) => ({
                                                    ...prev,
                                                    masses: prev.masses.map((m) => m.id === record.id
                                                        ? { ...m, m: newVal || 0 }
                                                        : m),
                                                }));
                                            } })) : '-',
                                    },
                                    {
                                        title: 'Spring Const (K)',
                                        dataIndex: 'k',
                                        key: 'k',
                                        width: 140,
                                        render: (val, record) => record.type === 'spring' ? (_jsx(InputNumber, { min: 0, value: val, size: "small", style: { width: '100%' }, onChange: (newVal) => {
                                                setSystem((prev) => ({
                                                    ...prev,
                                                    springs: prev.springs.map((s) => s.id === record.id
                                                        ? { ...s, k: newVal || 0 }
                                                        : s),
                                                }));
                                            } })) : '-',
                                    },
                                    {
                                        title: 'Damping (C)',
                                        dataIndex: 'c',
                                        key: 'c',
                                        width: 140,
                                        render: (val, record) => record.type === 'damper' ? (_jsx(InputNumber, { min: 0, value: val, size: "small", style: { width: '100%' }, onChange: (newVal) => {
                                                setSystem((prev) => ({
                                                    ...prev,
                                                    dampers: prev.dampers.map((d) => d.id === record.id
                                                        ? { ...d, c: newVal || 0 }
                                                        : d),
                                                }));
                                            } })) : '-',
                                    },
                                    {
                                        title: 'X',
                                        dataIndex: 'x',
                                        key: 'x',
                                        width: 80,
                                        render: (val, record) => record.type === 'fixed' || record.type === 'mass'
                                            ? val?.toFixed(1)
                                            : '-',
                                    },
                                    {
                                        title: 'Y',
                                        dataIndex: 'y',
                                        key: 'y',
                                        width: 80,
                                        render: (val, record) => record.type === 'fixed' || record.type === 'mass'
                                            ? val?.toFixed(1)
                                            : '-',
                                    },
                                ], pagination: false, size: "small", scroll: { x: 'max-content', y: 400 } }) }) }) }), _jsx(Row, { style: { marginTop: 16 }, children: _jsx(Col, { span: 24, children: _jsx(ModalAnalysisPanel, { system: system, modalResults: modalResults, onRunModal: (numModes) => {
                                const result = modalAnalysis(system, numModes);
                                console.log('Modal Result:', result);
                                setModalResults(result);
                            } }) }) }), _jsx(Row, { style: { marginTop: 16 }, children: _jsx(Col, { span: 24, children: _jsx(HarmonicAnalysisPanel, { system: system, modalResults: modalResults, setSystem: setSystem, onRunHarmonic: (result) => {
                                console.log("Harmonic Result:", result);
                                setHarmonicResults(result);
                            } }) }) }), harmonicResults && (_jsx(Row, { style: { marginTop: 16 }, children: _jsx(Col, { span: 24, children: _jsx(HarmonicResultsPanel, { result: harmonicResults }) }) })), harmonicResults && (_jsx(Row, { style: { marginTop: 16 }, children: _jsx(Col, { span: 24, children: _jsx(Card, { title: "Harmonic Response Results", size: "small", children: _jsx(AntdTable, { dataSource: harmonicResults.frequency.map((f, idx) => ({
                                    key: idx,
                                    freq: f.toFixed(2),
                                    mag: harmonicResults.magnitudeDB[0][idx]?.toFixed(2),
                                    phase: harmonicResults.phaseDeg[0][idx]?.toFixed(2),
                                })), columns: [
                                    { title: 'Freq (Hz)', dataIndex: 'freq', key: 'freq' },
                                    { title: 'Mag (dB)', dataIndex: 'mag', key: 'mag' },
                                    { title: 'Phase (deg)', dataIndex: 'phase', key: 'phase' },
                                ], pagination: false, size: "small", scroll: { y: 300 } }) }) }) })), _jsx(Row, { style: { marginTop: 16 }, children: _jsxs(Col, { span: 24, children: [_jsx(TransientAnalysisPanel, { nodes: system.masses, onDeleteForce: handleDeleteForce, onAddForce: (force) => {
                                    console.log("force added", force);
                                    setTransientForces((prev) => [...prev, force]);
                                }, onRunTransient: () => {
                                    try {
                                        if (transientForces.length === 0) {
                                            message.warning("No forces defined for transient analysis");
                                            return;
                                        }
                                        const maxDuration = Math.max(...transientForces.map(f => f.duration));
                                        const dt = Math.min(...transientForces.map(f => f.dt));
                                        const time = Array.from({ length: Math.floor(maxDuration / dt) + 1 }, (_, i) => i * dt);
                                        const forcesPerNode = {};
                                        transientForces.forEach(force => {
                                            if (!forcesPerNode[force.nodeId]) {
                                                forcesPerNode[force.nodeId] = new Array(time.length).fill(0);
                                            }
                                            for (let i = 0; i < time.length; i++) {
                                                const t = time[i];
                                                if (t <= force.duration) {
                                                    if (force.type === "function" && force.expression) {
                                                        const expr = math.compile(force.expression);
                                                        forcesPerNode[force.nodeId][i] = Number(expr.evaluate({ t }));
                                                    }
                                                    else if (force.type === "table" && force.timeArray && force.forceArray) {
                                                        // Simple linear interpolation
                                                        let forceValue = 0;
                                                        for (let j = 0; j < force.timeArray.length - 1; j++) {
                                                            if (force.timeArray[j] <= t && t <= force.timeArray[j + 1]) {
                                                                const slope = (force.forceArray[j + 1] - force.forceArray[j]) / (force.timeArray[j + 1] - force.timeArray[j]);
                                                                forceValue = force.forceArray[j] + slope * (t - force.timeArray[j]);
                                                                break;
                                                            }
                                                        }
                                                        forcesPerNode[force.nodeId][i] = forceValue;
                                                    }
                                                }
                                            }
                                        });
                                        const result = transientResponse(system, time, forcesPerNode);
                                        console.log("Transient Result:", result);
                                        setTransientResults(result);
                                        message.success("Transient Analysis Completed!");
                                    }
                                    catch (e) {
                                        console.error(e);
                                        message.error("Transient analysis failed!");
                                    }
                                }, forces: transientForces }), transientResults && (_jsx(Card, { title: "Transient Displacement", children: _jsx(Plot, { data: transientResults.displacement.map((d, i) => ({
                                        x: transientResults.time,
                                        y: d,
                                        type: "scatter",
                                        mode: "lines",
                                        name: `Node ${system.masses[i].id}`,
                                    })), layout: { title: { text: "Transient Response" } } }) }))] }) })] }) }));
};
export default MckLayout;
