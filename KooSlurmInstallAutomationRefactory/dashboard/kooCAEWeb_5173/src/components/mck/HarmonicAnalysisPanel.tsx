import React, { useState } from 'react';
import { Card, Form, InputNumber, Select, Button, Table, Space } from 'antd';
import { MCKSystem, Force } from '../../types/mck/modelTypes';
import { harmonicResponse } from '../../services/mck/mckSolver';
import { ModeResult } from '../../types/mck/simulationTypes';

interface HarmonicAnalysisPanelProps {
  system: MCKSystem;
  modalResults: ModeResult | null;
  onRunHarmonic: (result: any) => void;
  setSystem: React.Dispatch<React.SetStateAction<MCKSystem>>;
}

const HarmonicAnalysisPanel: React.FC<HarmonicAnalysisPanelProps> = ({
  system,
  modalResults,
  onRunHarmonic,
  setSystem,
}) => {
  const [selectedMassId, setSelectedMassId] = useState<string | null>(null);
  const [magnitude, setMagnitude] = useState<number>(1);
  const [frequency, setFrequency] = useState<number>(1);
  const [phase, setPhase] = useState<number>(0);
  const [freqStep, setFreqStep] = useState<number>(1);
  const [rangeFrom, setRangeFrom] = useState<number>(0);
  const [rangeTo, setRangeTo] = useState<number>(100);

  const handleAddForce = () => {
    if (!selectedMassId) return;

    const newForce: Force = {
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

  const handleDeleteForce = (forceId: string) => {
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

  return (
    <Card title="Harmonic Analysis" size="small">
      <Form layout="inline">
        <Form.Item label="Target Mass Node">
          <Select
            value={selectedMassId}
            onChange={setSelectedMassId}
            style={{ width: 120 }}
            placeholder="Select Node"
          >
            {system.masses.map((m) => (
              <Select.Option key={m.id} value={m.id}>
                {m.id.replace(/^mass-/, '')}
              </Select.Option>
            ))}
          </Select>
        </Form.Item>
        <Form.Item label="Magnitude">
          <InputNumber value={magnitude} onChange={(v) => setMagnitude(v || 0)} />
        </Form.Item>
        <Form.Item label="Frequency">
          <InputNumber value={frequency} onChange={(v) => setFrequency(v || 0)} />
        </Form.Item>
        <Form.Item label="Phase (deg)">
          <InputNumber value={phase} onChange={(v) => setPhase(v || 0)} />
        </Form.Item>
        <Form.Item>
          <Button type="primary" onClick={handleAddForce}>
            Add Force
          </Button>
        </Form.Item>
      </Form>

      <Table
        dataSource={system.forces}
        columns={[
          { title: 'Mass Node', dataIndex: 'targetMassId', key: 'targetMassId',
            render: (id: string) => id.replace(/^mass-/, '') },
          { title: 'Mag', dataIndex: 'magnitude', key: 'magnitude' },
          { title: 'Freq', dataIndex: 'frequency', key: 'frequency' },
          { title: 'Phase', dataIndex: 'phase', key: 'phase' },
          {
            title: 'Action',
            key: 'action',
            render: (_, record) => (
              <Button danger size="small" onClick={() => handleDeleteForce(record.id)}>
                Delete
              </Button>
            )
          },
        ]}
        rowKey="id"
        size="small"
        style={{ marginTop: 10 }}
        pagination={false}
      />

      <Space style={{ marginTop: 16 }}>
        <Form.Item label="Freq From">
          <InputNumber value={rangeFrom} onChange={(v) => setRangeFrom(v || 0)} />
        </Form.Item>
        <Form.Item label="Freq To">
          <InputNumber value={rangeTo} onChange={(v) => setRangeTo(v || 0)} />
        </Form.Item>
        <Form.Item label="Step">
          <InputNumber value={freqStep} onChange={(v) => setFreqStep(v || 1)} />
        </Form.Item>
        <Button type="primary" onClick={runHarmonic}>
          Run Harmonic Analysis
        </Button>
      </Space>
    </Card>
  );
};

export default HarmonicAnalysisPanel;
