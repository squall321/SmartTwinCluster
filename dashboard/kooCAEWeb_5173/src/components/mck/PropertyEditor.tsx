// src/components/mck/PropertyEditor.tsx

import React from 'react';
import { Card, Form, InputNumber } from 'antd';
import {
  MassNode,
  SpringEdge,
  DamperEdge,
  Force,
} from '../../types/mck/modelTypes';

interface PropertyEditorProps {
  selected:
    | { type: 'mass'; data: MassNode }
    | { type: 'spring'; data: SpringEdge }
    | { type: 'damper'; data: DamperEdge }
    | { type: 'force'; data: Force }
    | null;
  onChange: (updated: any) => void;
}

const PropertyEditor: React.FC<PropertyEditorProps> = ({
  selected,
  onChange,
}) => {
  const handleChange = (field: string, value: number) => {
    if (!selected) return;
    const newData = { ...selected.data, [field]: value };
    onChange({ type: selected.type, data: newData });
  };

  return (
    <Card
      title="Property Editor"
      size="small"
      bodyStyle={{ padding: 12 }}
      style={{ marginBottom: 10 }}
    >
      {!selected && <p style={{ margin: 0 }}>Nothing selected</p>}

      {selected?.type === 'mass' && (
        <Form layout="inline">
          <Form.Item label="Mass (kg)" style={{ marginBottom: 0 }}>
            <InputNumber
              min={0}
              value={selected.data.m}
              size="small"
              onChange={(v) => handleChange('m', v || 0)}
            />
          </Form.Item>
        </Form>
      )}

      {selected?.type === 'spring' && (
        <Form layout="inline">
          <Form.Item label="Stiffness (N/m)" style={{ marginBottom: 0 }}>
            <InputNumber
              min={0}
              value={selected.data.k}
              size="small"
              onChange={(v) => handleChange('k', v || 0)}
            />
          </Form.Item>
        </Form>
      )}

      {selected?.type === 'damper' && (
        <Form layout="inline">
          <Form.Item label="Damping (Ns/m)" style={{ marginBottom: 0 }}>
            <InputNumber
              min={0}
              value={selected.data.c}
              size="small"
              onChange={(v) => handleChange('c', v || 0)}
            />
          </Form.Item>
        </Form>
      )}
    </Card>
  );
};

export default PropertyEditor;
