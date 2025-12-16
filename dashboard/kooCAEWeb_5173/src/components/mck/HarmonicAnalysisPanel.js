import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import { Card, Form, InputNumber, Select, Button, Table, Space } from 'antd';
import { harmonicResponse } from '../../services/mck/mckSolver';
const HarmonicAnalysisPanel = ({ system, modalResults, onRunHarmonic, setSystem, }) => {
    const [selectedMassId, setSelectedMassId] = useState(null);
    const [magnitude, setMagnitude] = useState(1);
    const [frequency, setFrequency] = useState(1);
    const [phase, setPhase] = useState(0);
    const [freqStep, setFreqStep] = useState(1);
    const [rangeFrom, setRangeFrom] = useState(0);
    const [rangeTo, setRangeTo] = useState(100);
    const handleAddForce = () => {
        if (!selectedMassId)
            return;
        const newForce = {
            id: `force-${system.forces.length + 1}`,
            targetMassId: selectedMassId,
            magnitude,
            frequency,
            phase,
        };
        setSystem((prev) => ({
            ...prev,
            forces: [...prev.forces, newForce],
        }));
        // Reset inputs
        setSelectedMassId(null);
        setMagnitude(1);
        setFrequency(1);
        setPhase(0);
    };
    const handleDeleteForce = (forceId) => {
        setSystem((prev) => ({
            ...prev,
            forces: prev.forces.filter((f) => f.id !== forceId),
        }));
    };
    const runHarmonic = () => {
        const result = harmonicResponse(system, [rangeFrom, rangeTo], freqStep);
        console.log("Harmonic Result:", result);
        onRunHarmonic(result);
    };
    return (_jsxs(Card, { title: "Harmonic Analysis", size: "small", children: [_jsxs(Form, { layout: "inline", children: [_jsx(Form.Item, { label: "Target Mass Node", children: _jsx(Select, { value: selectedMassId, onChange: setSelectedMassId, style: { width: 120 }, placeholder: "Select Node", children: system.masses.map((m) => (_jsx(Select.Option, { value: m.id, children: m.id.replace(/^mass-/, '') }, m.id))) }) }), _jsx(Form.Item, { label: "Magnitude", children: _jsx(InputNumber, { value: magnitude, onChange: (v) => setMagnitude(v || 0) }) }), _jsx(Form.Item, { label: "Frequency", children: _jsx(InputNumber, { value: frequency, onChange: (v) => setFrequency(v || 0) }) }), _jsx(Form.Item, { label: "Phase (deg)", children: _jsx(InputNumber, { value: phase, onChange: (v) => setPhase(v || 0) }) }), _jsx(Form.Item, { children: _jsx(Button, { type: "primary", onClick: handleAddForce, children: "Add Force" }) })] }), _jsx(Table, { dataSource: system.forces, columns: [
                    { title: 'Mass Node', dataIndex: 'targetMassId', key: 'targetMassId',
                        render: (id) => id.replace(/^mass-/, '') },
                    { title: 'Mag', dataIndex: 'magnitude', key: 'magnitude' },
                    { title: 'Freq', dataIndex: 'frequency', key: 'frequency' },
                    { title: 'Phase', dataIndex: 'phase', key: 'phase' },
                    {
                        title: 'Action',
                        key: 'action',
                        render: (_, record) => (_jsx(Button, { danger: true, size: "small", onClick: () => handleDeleteForce(record.id), children: "Delete" }))
                    },
                ], rowKey: "id", size: "small", style: { marginTop: 10 }, pagination: false }), _jsxs(Space, { style: { marginTop: 16 }, children: [_jsx(Form.Item, { label: "Freq From", children: _jsx(InputNumber, { value: rangeFrom, onChange: (v) => setRangeFrom(v || 0) }) }), _jsx(Form.Item, { label: "Freq To", children: _jsx(InputNumber, { value: rangeTo, onChange: (v) => setRangeTo(v || 0) }) }), _jsx(Form.Item, { label: "Step", children: _jsx(InputNumber, { value: freqStep, onChange: (v) => setFreqStep(v || 1) }) }), _jsx(Button, { type: "primary", onClick: runHarmonic, children: "Run Harmonic Analysis" })] })] }));
};
export default HarmonicAnalysisPanel;
