// 앞부분 동일
import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Input, Button, Table, Row, Col, Select, message, Typography } from 'antd';
import { DeleteOutlined, ArrowUpOutlined, ArrowDownOutlined, CopyOutlined, SearchOutlined } from '@ant-design/icons';
import { Bar } from '@ant-design/charts';

const { Title, Paragraph } = Typography;

interface Material {
  name: string;
  layers: Layer[];
}

interface Layer {
  name: string;
  modulus: number;
  thickness: number;
}

const predefinedMaterials: Material[] = [
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
  

const ABDCalculator: React.FC = () => {
  const [materials, setMaterials] = useState<Material[]>(predefinedMaterials);
  const [layers, setLayers] = useState<Layer[]>([]);
  const [selectedMaterial, setSelectedMaterial] = useState<string>('CU');

  const [abdMatrix, setAbdMatrix] = useState<number[][]>([]);
  const [searchTerm, setSearchTerm] = useState<string>('');

  const handleLayerChange = (index: number, key: keyof Layer, value: string | number) => {
    const newLayers = [...layers];
    if (key === 'modulus' || key === 'thickness') {
      const num = parseFloat(value as string);
      if (isNaN(num) || num < 0) {
        message.error('영률과 두께는 0 이상의 숫자여야 합니다.');
        return;
      }
      newLayers[index] = { ...newLayers[index], [key]: num };
    } else {
      newLayers[index] = { ...newLayers[index], [key]: value as string };
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
    const A: number[] = [];
    const B: number[] = [];
    const D: number[] = [];

    layers.forEach(layer => {
      const { modulus, thickness } = layer;
      A.push(modulus * thickness);
      B.push(modulus * thickness * thickness / 2);
      D.push(modulus * thickness * thickness * thickness / 3);
    });

    setAbdMatrix([A, B, D]);
  };

  const clearLayers = () => setLayers([]);
  const deleteLayer = (index: number) => setLayers(layers.filter((_, i) => i !== index));
  const moveLayerUp = (index: number) => {
    if (index === 0) return;
    const newLayers = [...layers];
    [newLayers[index - 1], newLayers[index]] = [newLayers[index], newLayers[index - 1]];
    setLayers(newLayers);
  };
  const moveLayerDown = (index: number) => {
    if (index === layers.length - 1) return;
    const newLayers = [...layers];
    [newLayers[index + 1], newLayers[index]] = [newLayers[index], newLayers[index + 1]];
    setLayers(newLayers);
  };
  const copyLayer = (index: number) => {
    const newLayer = { ...layers[index], name: `L${layers.length + 1}` };
    setLayers([...layers, newLayer]);
  };

  const filteredLayers = layers.filter(layer =>
    layer.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    layer.modulus.toString().includes(searchTerm) ||
    layer.thickness.toString().includes(searchTerm)
  );

  const colors = ['#1890ff', '#ff4d4f', '#52c41a', '#faad14', '#722ed1'];

  const columns = [
    {
      title: '층 이름',
      dataIndex: 'name',
      key: 'name',
      render: (text: string, record: Layer, index: number) => (
        <Input value={text} onChange={(e) => handleLayerChange(index, 'name', e.target.value)} />
      ),
    },
    {
      title: '영률',
      dataIndex: 'modulus',
      key: 'modulus',
      render: (text: number, record: Layer, index: number) => (
        <Input type="number" step="any" value={text} onChange={(e) => handleLayerChange(index, 'modulus', e.target.value)} />
      ),
    },
    {
      title: '두께',
      dataIndex: 'thickness',
      key: 'thickness',
      render: (text: number, record: Layer, index: number) => (
        <Input type="number" step="any" value={text} onChange={(e) => handleLayerChange(index, 'thickness', e.target.value)} />
      ),
    },
    {
      title: '작업',
      key: 'action',
      render: (text: any, record: Layer, index: number) => (
        <span>
          <Button icon={<ArrowUpOutlined />} onClick={() => moveLayerUp(index)} style={{ marginRight: 8 }} />
          <Button icon={<ArrowDownOutlined />} onClick={() => moveLayerDown(index)} style={{ marginRight: 8 }} />
          <Button icon={<CopyOutlined />} onClick={() => copyLayer(index)} style={{ marginRight: 8 }} />
          <Button icon={<DeleteOutlined />} onClick={() => deleteLayer(index)} danger />
        </span>
      ),
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
    const layerCenters: number[] = [];
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
    D_total += modulus * thickness * z * z;     // E * t * z^2
    I_total += thickness * z * z;               // t * z^2
    }
    const effectiveBendingModulus = D_total / I_total;  // GPa


  const abdTableData = abdMatrix.length > 0
  ? [   
      ...layers.map((_, i) => ({
        key: `L${i + 1}`,
        A: abdMatrix[0][i]?.toFixed(2),
        B: abdMatrix[1][i]?.toFixed(2),
        D: abdMatrix[2][i]?.toFixed(2),
      })),
      abdTotal  // 👈 총합 추가
    ]
  : [];


  return (
    <BaseLayout isLoggedIn={false}>        
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>복합재료 ABD 행렬 계산기</Title>
        <Paragraph>
        사전 정의된 재료를 불러오거나 직접 입력하여 적층 구조를 만들 수 있으며, 각 층의 영률과 두께를 기반으로 ABD 행렬과 유효 인장/굽힘 영률을 계산해줍니다. 시각적 단면 표시 및 물성 그래프도 함께 제공되어 구조 설계와 물성 분석을 직관적으로 도와줍니다.
        </Paragraph>
        <div style={{ marginBottom: '20px' }}>
          <Select
            placeholder="재료 선택"
            value={selectedMaterial}
            onChange={(value) => setSelectedMaterial(value)}
            style={{ width: 200, marginRight: 10 }}
          >
            {materials.map((material, index=0) => (
              <Select.Option key={index} value={material.name}>
                {material.name}
              </Select.Option>
            ))}
          </Select>
          <Button onClick={addPredefinedLayers}>층 추가</Button>
          <Button onClick={clearLayers} danger style={{ marginLeft: 10 }}>전체 삭제</Button>

          <Button onClick={calculateABD} style={{ marginLeft: 10 }}>ABD 계산</Button>
          <Input
            placeholder="검색"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            style={{ width: 200, marginLeft: 10 }}
            prefix={<SearchOutlined />}
          />
        </div>

        <Table
          dataSource={filteredLayers}
          columns={columns}
          rowKey={(_, i=0) => i.toString()}
          style={{ marginTop: 20 }}
        />

        <div style={{ position: 'relative', height: '400px', border: '1px solid #ccc', marginTop: 20 }}>
        {(() => {
            const totalThicknessForDisplay = layers.reduce((sum, layer) => sum + layer.thickness, 0);
            let currentTop = 0;

            return layers.map((layer, index = 0) => {
            const height = (layer.thickness / totalThicknessForDisplay) * 400;

            const layerDiv = (
                <div
                key={index}
                style={{
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
                }}
                >
                {layer.name}
                </div>
            );

            currentTop += height;
            return layerDiv;
            });
        })()}
        </div>

        {abdMatrix.length > 0 && (
        <div style={{ marginTop: 20 }}>
            <h3>ABD 행렬:</h3>
            <Table
            dataSource={abdTableData}
            columns={[
                { title: 'Layer', dataIndex: 'key', key: 'key' },
                { title: 'A', dataIndex: 'A', key: 'A' },
                { title: 'B', dataIndex: 'B', key: 'B' },
                { title: 'D', dataIndex: 'D', key: 'D' },
            ]}
            pagination={false}
            bordered
            size="small"
            />

            <div style={{ marginTop: 20 }}>
            <h4>유효 영률 계산:</h4>
            <p>인장 유효 영률 (E<sub>tensile</sub>): <strong>{effectiveTensileModulus?.toFixed(2)}</strong></p>
            <p>굽힘 유효 영률 (E<sub>bending</sub>): <strong>{effectiveBendingModulus?.toFixed(2)}</strong></p>
            </div>
        </div>
        )}

        <div style={{ marginTop: 20 }}>
          <h3>층별 물성 그래프:</h3>
          <Bar {...chartConfig} />
        </div>
      </div>
    </BaseLayout>
  );
};

export default ABDCalculator;
