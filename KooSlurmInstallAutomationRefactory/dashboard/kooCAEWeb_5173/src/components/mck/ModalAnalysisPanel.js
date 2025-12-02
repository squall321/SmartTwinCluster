import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// src/components/mck/ModalAnalysisPanel.tsx
import { useState, useEffect, useRef } from 'react';
import { Card, Form, InputNumber, Button, Table } from 'antd';
import { Stage, Layer, Rect, Line } from 'react-konva';
const ModalAnalysisPanel = ({ system, modalResults, onRunModal, }) => {
    const [numModes, setNumModes] = useState(5);
    const [selectedMode, setSelectedMode] = useState(null);
    const [time, setTime] = useState(0);
    const animRef = useRef(0);
    useEffect(() => {
        if (selectedMode === null)
            return;
        let t = 0;
        const animate = () => {
            t += 0.02;
            setTime(t);
            animRef.current = requestAnimationFrame(animate);
        };
        animate();
        return () => {
            if (animRef.current)
                cancelAnimationFrame(animRef.current);
        };
    }, [selectedMode]);
    const A = 40;
    const columns = [
        { title: 'Mode', dataIndex: 'mode', key: 'mode' },
        { title: 'Freq (Hz)', dataIndex: 'frequency', key: 'frequency' },
        { title: 'Damp (%)', dataIndex: 'damping', key: 'damping' },
    ];
    const dataSource = modalResults?.frequencies.map((f, idx) => ({
        key: idx,
        mode: idx + 1,
        frequency: f.toFixed(2),
        damping: (modalResults.dampingRatios[idx] * 100).toFixed(2),
    })) || [];
    return (_jsxs(Card, { title: "Modal Analysis", size: "small", bodyStyle: { padding: 12 }, style: { height: '100%', overflowY: 'auto' }, children: [_jsxs(Form, { layout: "inline", style: { marginBottom: 12 }, children: [_jsx(Form.Item, { label: "Number of Modes", children: _jsx(InputNumber, { min: 1, value: numModes, onChange: (v) => setNumModes(v || 1), style: { width: 80 } }) }), _jsx(Button, { type: "primary", onClick: () => onRunModal(numModes), children: "Run" })] }), _jsx(Table, { size: "small", columns: columns, dataSource: dataSource, pagination: false, onRow: (record) => ({
                    onClick: () => setSelectedMode(record.key),
                }), rowClassName: (record) => selectedMode === record.key ? 'ant-table-row-selected' : '' }), selectedMode !== null && modalResults && (_jsx(Stage, { width: 500, height: 150, style: { marginTop: 12 }, children: _jsxs(Layer, { children: [Array.from({ length: system.masses.length }).map((_, i) => {
                            const phi = modalResults.modeShapes[selectedMode][i];
                            const yOffset = A *
                                phi *
                                Math.sin(2 * Math.PI * modalResults.frequencies[selectedMode] * time);
                            return (_jsx(Rect, { x: 80 + i * 70, y: 80 + yOffset, width: 30, height: 30, fill: "#3498db", stroke: "black", strokeWidth: 1 }, i));
                        }), Array.from({ length: system.masses.length - 1 }).map((_, i) => {
                            const phi1 = modalResults.modeShapes[selectedMode][i];
                            const phi2 = modalResults.modeShapes[selectedMode][i + 1];
                            const y1 = 80 +
                                A *
                                    phi1 *
                                    Math.sin(2 *
                                        Math.PI *
                                        modalResults.frequencies[selectedMode] *
                                        time);
                            const y2 = 80 +
                                A *
                                    phi2 *
                                    Math.sin(2 *
                                        Math.PI *
                                        modalResults.frequencies[selectedMode] *
                                        time);
                            const x1 = 80 + i * 70 + 30;
                            const x2 = 80 + (i + 1) * 70;
                            return (_jsx(Line, { points: [x1, y1 + 15, x2, y2 + 15], stroke: "#2ecc71", strokeWidth: 3 }, i));
                        })] }) }))] }));
};
export default ModalAnalysisPanel;
