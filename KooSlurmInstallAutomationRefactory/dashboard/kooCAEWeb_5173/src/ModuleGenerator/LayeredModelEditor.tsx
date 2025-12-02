// LayeredModelEditor.tsx (2D Plotly + AntD, extended features)
import React, { useState } from 'react';
import { Row, Col, List, Button, Form, InputNumber, Input, Typography, Modal, Popconfirm, Space, Divider } from 'antd';
import Plot from 'react-plotly.js';
import { Table } from 'antd';

const { Title } = Typography;

interface CylinderData {
  x: number;
  y: number;
  r: number;
  active?: boolean;
}

interface Layer {
  name: string;
  location: [number, number];
  length: [number, number];
  thickness: number;
  meshType: 'Tetra' | 'Hexa';
  meshPath: string;
  materialID: number;
  mirror: boolean;
  rotation: number;
  isTop: boolean;
  surfaceTension: number;
  cylinders: CylinderData[];
  boxes: any[];
}

const defaultLayer = (): Layer => ({
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

const LayeredModelEditor: React.FC = () => {
  const [layers, setLayers] = useState<Layer[]>([]);
  const [selectedIndex, setSelectedIndex] = useState<number>(-1);
  const [patternModalOpen, setPatternModalOpen] = useState(false);
  const [patternCols, setPatternCols] = useState(4);
  const [patternRows, setPatternRows] = useState(4);
  const [patternPitchX, setPatternPitchX] = useState(0.35);
  const [patternPitchY, setPatternPitchY] = useState(0.35);
  const [patternRadius, setPatternRadius] = useState(0.1);
  const [zoomRange, setZoomRange] = useState<{
    x?: [number, number];
    y?: [number, number];
  }>({});
  const addLayer = () => {
    const newLayer = defaultLayer();
    setLayers([...layers, newLayer]);
    setSelectedIndex(layers.length);
  };

  const removeLayer = (idx: number) => {
    const newLayers = layers.filter((_, i) => i !== idx);
    setLayers(newLayers);
    if (selectedIndex === idx) setSelectedIndex(-1);
    else if (selectedIndex > idx) setSelectedIndex(selectedIndex - 1);
  };

  const renameLayer = (idx: number, name: string) => {
    const newLayers = [...layers];
    newLayers[idx].name = name;
    setLayers(newLayers);
  };

  const updateLayer = (index: number, updated: Partial<Layer>) => {
    const newLayers = [...layers];
    newLayers[index] = { ...newLayers[index], ...updated };
    setLayers(newLayers);
  };

  const addSingleCylinder = () => {
    const current = layers[selectedIndex];
    const newCyl = { x: 0, y: 0, r: 0.1, active: true };
    updateLayer(selectedIndex, { cylinders: [...current.cylinders, newCyl] });
  };

  const toggleCylinder = (index: number) => {
    const layer = layers[selectedIndex];
    const newCylinders = [...layer.cylinders];
    newCylinders[index].active = !newCylinders[index].active;
    updateLayer(selectedIndex, { cylinders: newCylinders });
  };

  const generatePattern = () => {
    const baseX = -((patternCols - 1) * patternPitchX) / 2;
    const baseY = -((patternRows - 1) * patternPitchY) / 2;
    const newCylinders: CylinderData[] = [];
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
    if (selectedIndex < 0) return [];
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

  const handlePointClick = (e: any) => {
    if (!e.points || e.points.length === 0) return;
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

  return (
    <Row gutter={16}>
      {/* Layer List */}
      <Col span={4}>
        <Title level={4}>Layers</Title>
        <List
          bordered
          dataSource={layers}
          renderItem={(item, idx) => (
            <List.Item style={{ background: selectedIndex === idx ? '#e6f7ff' : '' }}>
              <Space style={{ width: '100%', justifyContent: 'space-between' }}>
                <Input
                  value={item.name}
                  onChange={e => renameLayer(idx, e.target.value)}
                  onClick={() => setSelectedIndex(idx)}
                  size="small"
                />
                <Popconfirm title="Delete this layer?" onConfirm={() => removeLayer(idx)}>
                  <Button size="small" danger>Delete</Button>
                </Popconfirm>
              </Space>
            </List.Item>
          )}
        />
        <Button type="primary" block onClick={addLayer} style={{ marginTop: 8 }}>+ Add Layer</Button>
      </Col>
  
      {/* Layer Settings + Cylinder Table */}
      <Col span={10}>
        {selectedIndex >= 0 && (
          <>
            <Title level={4}>Layer Settings</Title>
            <Form layout="vertical">
              <Row gutter={8}>
                <Col span={12}>
                  <Form.Item label="Location (X, Y)">
                    <Input.Group compact>
                      <InputNumber
                        value={layers[selectedIndex].location[0]}
                        onChange={v => updateLayer(selectedIndex, {
                          location: [v ?? 0, layers[selectedIndex].location[1]],
                        })}
                        style={{ width: '50%' }}
                      />
                      <InputNumber
                        value={layers[selectedIndex].location[1]}
                        onChange={v => updateLayer(selectedIndex, {
                          location: [layers[selectedIndex].location[0], v ?? 0],
                        })}
                        style={{ width: '50%' }}
                      />
                    </Input.Group>
                  </Form.Item>
                </Col>
                <Col span={12}>
                  <Form.Item label="Length (X, Y)">
                    <Input.Group compact>
                      <InputNumber
                        value={layers[selectedIndex].length[0]}
                        onChange={v => updateLayer(selectedIndex, {
                          length: [v ?? 1, layers[selectedIndex].length[1]],
                        })}
                        style={{ width: '50%' }}
                      />
                      <InputNumber
                        value={layers[selectedIndex].length[1]}
                        onChange={v => updateLayer(selectedIndex, {
                          length: [layers[selectedIndex].length[0], v ?? 1],
                        })}
                        style={{ width: '50%' }}
                      />
                    </Input.Group>
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item label="Thickness">
                    <InputNumber
                      value={layers[selectedIndex].thickness}
                      onChange={val => updateLayer(selectedIndex, { thickness: val ?? 0.01 })}
                      style={{ width: '100%' }}
                    />
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item label="Surface Tension">
                    <InputNumber
                      value={layers[selectedIndex].surfaceTension}
                      onChange={val => updateLayer(selectedIndex, { surfaceTension: val ?? 0 })}
                      style={{ width: '100%' }}
                    />
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item label="Cylinders">
                    <Space direction="vertical" style={{ width: '100%' }}>
                      <Button onClick={() => setPatternModalOpen(true)} block>
                        Add Pattern
                      </Button>
                      <Button onClick={addSingleCylinder} block>
                        + Single
                      </Button>
                    </Space>
                  </Form.Item>
                </Col>
              </Row>
            </Form>
  
            <Divider />
  
            <Title level={5}>Cylinder Editor</Title>
            <Table
              size="small"
              scroll={{ y: 250 }}
              rowKey={(_, idx) => `${idx}`}
              dataSource={layers[selectedIndex].cylinders.map((c, idx) => ({ ...c, key: idx }))}
              pagination={false}
              columns={[
                {
                  title: 'X',
                  dataIndex: 'x',
                  render: (value, _, idx) => (
                    <InputNumber
                      value={value}
                      onChange={(val) => {
                        const newCyls = [...layers[selectedIndex].cylinders];
                        newCyls[idx].x = val ?? 0;
                        updateLayer(selectedIndex, { cylinders: newCyls });
                      }}
                    />
                  ),
                },
                {
                  title: 'Y',
                  dataIndex: 'y',
                  render: (value, _, idx) => (
                    <InputNumber
                      value={value}
                      onChange={(val) => {
                        const newCyls = [...layers[selectedIndex].cylinders];
                        newCyls[idx].y = val ?? 0;
                        updateLayer(selectedIndex, { cylinders: newCyls });
                      }}
                    />
                  ),
                },
                {
                  title: 'R',
                  dataIndex: 'r',
                  render: (value, _, idx) => (
                    <InputNumber
                      value={value}
                      onChange={(val) => {
                        const newCyls = [...layers[selectedIndex].cylinders];
                        newCyls[idx].r = val ?? 0.01;
                        updateLayer(selectedIndex, { cylinders: newCyls });
                      }}
                    />
                  ),
                },
                {
                  title: 'Active',
                  dataIndex: 'active',
                  render: (value, _, idx) => (
                    <Button
                      type={value ? 'primary' : 'default'}
                      size="small"
                      onClick={() => toggleCylinder(idx)}
                    >
                      {value ? 'On' : 'Off'}
                    </Button>
                  ),
                },
                {
                  title: 'Action',
                  render: (_, __, idx) => (
                    <Button
                      danger
                      size="small"
                      onClick={() => {
                        const newCyls = layers[selectedIndex].cylinders.filter((_, i) => i !== idx);
                        updateLayer(selectedIndex, { cylinders: newCyls });
                      }}
                    >
                      Delete
                    </Button>
                  ),
                },
              ]}
            />
          </>
        )}
      </Col>
  
      {/* 2D View */}
      <Col span={10}>
        <Title level={4}>2D View</Title>
        <div style={{ padding: '0 12px' }}>
        <Plot
            data={getPlotData() as any}
            onClick={handlePointClick}
            onRelayout={(event) => {
                const x = event['xaxis.range[0]'] !== undefined && event['xaxis.range[1]'] !== undefined
                ? [event['xaxis.range[0]'], event['xaxis.range[1]']] as [number, number]
                : zoomRange.x;
                const y = event['yaxis.range[0]'] !== undefined && event['yaxis.range[1]'] !== undefined
                ? [event['yaxis.range[0]'], event['yaxis.range[1]']] as [number, number]
                : zoomRange.y;
                setZoomRange({ x, y });
            }}
            layout={{
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
            }}
            config={{ responsive: true }}
            />

        </div>
      </Col>
  
      {/* Script Output */}
      <Col span={24} style={{ marginTop: 16 }}>
        <Title level={4}>Generated Script</Title>
        <Input.TextArea rows={10} value={generateScript()} readOnly />
      </Col>
  
      {/* Pattern Modal */}
      <Modal
        open={patternModalOpen}
        onCancel={() => setPatternModalOpen(false)}
        onOk={generatePattern}
        title="Cylinder Pattern Generator"
      >
        <Form layout="vertical">
          <Form.Item label="Columns">
            <InputNumber min={1} value={patternCols} onChange={val => setPatternCols(val || 1)} />
          </Form.Item>
          <Form.Item label="Rows">
            <InputNumber min={1} value={patternRows} onChange={val => setPatternRows(val || 1)} />
          </Form.Item>
          <Form.Item label="Pitch X">
            <InputNumber step={0.01} value={patternPitchX} onChange={val => setPatternPitchX(val || 0.01)} />
          </Form.Item>
          <Form.Item label="Pitch Y">
            <InputNumber step={0.01} value={patternPitchY} onChange={val => setPatternPitchY(val || 0.01)} />
          </Form.Item>
          <Form.Item label="Radius">
            <InputNumber step={0.01} value={patternRadius} onChange={val => setPatternRadius(val || 0.01)} />
          </Form.Item>
        </Form>
      </Modal>
    </Row>
  );
  
};

export default LayeredModelEditor;
