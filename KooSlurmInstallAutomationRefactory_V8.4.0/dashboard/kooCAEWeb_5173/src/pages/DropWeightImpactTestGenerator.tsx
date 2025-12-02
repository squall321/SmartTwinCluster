import React, { useState, useEffect } from 'react';
import { Typography, Form, InputNumber, Select, Input, Divider, Button, Row, Col, Card } from 'antd';
const { Text } = Typography;

import BaseLayout from '../layouts/BaseLayout';
import DynaFilePartVisualizerComponent from '../components/DynaFilePartVisualizerComponent';
import ImpactorSelectorComponent from '../components/downloader/ImpactSelectorComponent';
import MultipleStlViewerComponent from '../components/MultipleStlViewerComponent';
import * as BABYLON from '@babylonjs/core';


const { Title, Paragraph } = Typography;

interface OnReadyPayload {
  kfile: File;
  partId: string;
  stlUrl: string;
}

interface ImpactPoint {
  dx: number;
  dy: number;
}

const DropWeightImpactTestGenerator: React.FC = () => {
  const [kfile, setKFile] = useState<File | null>(null);
  const [partId, setPartId] = useState<string | null>(null);
  const [stlUrl, setStlUrl] = useState<string | null>(null);
  const [impactorUrl, setImpactorUrl] = useState<string | null>(null);
  const [impactPoints, setImpactPoints] = useState<ImpactPoint[]>([]);
  const [heights, setHeights] = useState<number[]>([]);
  const [targetBoundingBox, setTargetBoundingBox] = useState<{ min: BABYLON.Vector3, max: BABYLON.Vector3 } | null>(null);

  const [tFinal, setTFinal] = useState(0.001);
  const [youngModulus, setYoungModulus] = useState(201e9);
  const [poissonRatio, setPoissonRatio] = useState(0.3);
  const [density, setDensity] = useState(2700);
  const [youngModulusDamper, setYoungModulusDamper] = useState(70e9);
  const [poissonRatioDamper, setPoissonRatioDamper] = useState(0.3);
  const [densityDamper, setDensityDamper] = useState(7800);
  const [type, setType] = useState<'Sphere' | 'Cylinder'>('Sphere');
  const [dimension, setDimension] = useState(0.008);
  const [dimensionDamper, setDimensionDamper] = useState<[number, number, number]>([0.0001, 0.0001, 0.01]);
  const [meshSize, setMeshSize] = useState(0.001);

  const [offsetDistance, setOffsetDistance] = useState(0.00001);
  const [youngModulusFront, setYoungModulusFront] = useState(50e6);
  const [densityFront, setDensityFront] = useState(2000);
  const [poissonRatioFront, setPoissonRatioFront] = useState(0.3);
  const [youngModulusWall, setYoungModulusWall] = useState(70e9);
  const [densityWall, setDensityWall] = useState(7800);
  const [poissonRatioWall, setPoissonRatioWall] = useState(0.3);
  const [cylinderDimensions, setCylinderDimensions] = useState<[number, number, number, number, number]>([0.008, 0.01, 0.005, 0.02, 0.012]);


  useEffect(() => {
    if (!stlUrl) return;
    const engine = new BABYLON.NullEngine();
    const scene = new BABYLON.Scene(engine);
    BABYLON.SceneLoader.ImportMeshAsync(null, '', stlUrl, scene, undefined, '.stl')
      .then(result => {
        const mesh = result.meshes[0] as BABYLON.Mesh;
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
    if (!kfile || !impactPoints.length) return;

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
      lines.push(
        `YoungModulusImpactorFront,${youngModulusFront}`,
        `DensityImpactorFront,${densityFront}`,
        `PoissonRatioImpactorFront,${poissonRatioFront}`,
        `YoungModulusWall,${youngModulusWall}`,
        `DensityWall,${densityWall}`,
        `PoissonRatioWall,${poissonRatioWall}`,
      );
      lines.push(`Dimension,${cylinderDimensions.join(',')}`);
    } else {
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

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>⚙️ 부분 충격 생성기</Title>
        <Paragraph>
          LS-DYNA의 K 파일로부터 특정 Part를 선택하고, 해당 영역에 대한 부분 충격 시험을 생성하기 위한 STL 형상을 추출 및 시각화할 수 있습니다.
        </Paragraph>

        <DynaFilePartVisualizerComponent
          onReady={({ kfile, partId, stlUrl }: OnReadyPayload) => {
            setKFile(kfile);
            setPartId(partId);
            setStlUrl(stlUrl);
          }}
        />

        {kfile && partId && stlUrl && (
          <Paragraph type="secondary" style={{ marginTop: 24 }}>
            현재 선택된 파일: <strong>{kfile.name}</strong><br />
            선택된 Part ID: <strong>{partId}</strong><br />
          </Paragraph>
        )}

        <ImpactorSelectorComponent
          onChange={(url, points) => {
            setImpactorUrl(url);
            setImpactPoints(points);
          }}
          targetBoundingBox={targetBoundingBox}
        />

        {impactorUrl && impactPoints.length > 0 && stlUrl && (
          <MultipleStlViewerComponent
            viewDirection="top"
            models={[
              {
                url: `${impactorUrl}`,
                positions: impactPoints.map(p => new BABYLON.Vector3(p.dx, 0, p.dy)),
              },
              {
                url: `${stlUrl}`,
                positions: [
                  new BABYLON.Vector3(
                    0,
                    targetBoundingBox ? -5 * targetBoundingBox.max.z : -100,
                    0,
                  ),
                ],
              },
            ]}
          />
        )}

        <Divider />
        <Title level={4}>⚙️ 충격 조건 및 시뮬레이션 입력파일 생성</Title>

        {impactPoints.map((p, idx) => (
  <Card
    key={idx}
    size="small"
    style={{ marginBottom: 12, background: '#fafafa', borderColor: '#d9d9d9' }}
  >
    <Row align="middle" gutter={16}>
      <Col flex="auto">
        <Text strong>#{idx + 1}</Text> ➤ (x: {p.dx.toFixed(4)}, y: {p.dy.toFixed(4)})
      </Col>
      <Col>
        <InputNumber
          value={heights[idx]}
          min={0}
          step={0.01}
          addonBefore="Height (m)"
          onChange={(val) =>
            setHeights((prev) => prev.map((v, i) => (i === idx ? val || 0 : v)))
          }
        />
      </Col>
    </Row>
  </Card>
))}
 <Divider orientation="left">🔨 충격자 설정 (Impactor)</Divider>
<Col span={6}>
  <Form.Item label="Impactor Type (충격자 종류)">
    <Select value={type} onChange={setType} style={{ width: '100%' }}>
      <Select.Option value="Sphere">Sphere</Select.Option>
      <Select.Option value="Cylinder">Cylinder</Select.Option>
    </Select>
  </Form.Item>
</Col>

<Form layout="vertical" style={{ marginTop: 16 }}>
  <Row gutter={16}>
    <Col span={6}>
      <Form.Item label="⏱️ tFinal (총 해석 시간)">
        <InputNumber value={tFinal} step={0.0001} onChange={(val) => setTFinal(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
  </Row>

  <Divider orientation="left">🧱 재료 속성 (Target Material)</Divider>
  <Row gutter={16}>
    <Col span={6}>
      <Form.Item label="Young's Modulus (재료 영률)">
        <InputNumber value={youngModulus} onChange={(val) => setYoungModulus(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
    <Col span={6}>
      <Form.Item label="Poisson's Ratio (재료 포아송비)">
        <InputNumber value={poissonRatio} onChange={(val) => setPoissonRatio(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
    <Col span={6}>
      <Form.Item label="Density (재료 밀도)">
        <InputNumber value={density} onChange={(val) => setDensity(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
  </Row>

  <Divider orientation="left">🧽 댐퍼 속성 (Damper Material)</Divider>
  <Row gutter={16}>
    <Col span={6}>
      <Form.Item label="Young's Modulus (댐퍼 영률)">
        <InputNumber value={youngModulusDamper} onChange={(val) => setYoungModulusDamper(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
    <Col span={6}>
      <Form.Item label="Poisson's Ratio (댐퍼 포아송비)">
        <InputNumber value={poissonRatioDamper} onChange={(val) => setPoissonRatioDamper(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
    <Col span={6}>
      <Form.Item label="Density (댐퍼 밀도)">
        <InputNumber value={densityDamper} onChange={(val) => setDensityDamper(val || 0)} style={{ width: '100%' }} />
      </Form.Item>
    </Col>
  </Row>

  {type === 'Cylinder' && (
    <>
      <Divider orientation="left">⚙️ Cylinder 옵션</Divider>
      <Row gutter={16}>
        <Col span={6}>
          <Form.Item label="Offset Distance (위치 오프셋)">
            <InputNumber value={offsetDistance} onChange={v => setOffsetDistance(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
      </Row>

      <Divider orientation="left">🧱 Impactor Front 물성 (전면 재료)</Divider>
      <Row gutter={16}>
        <Col span={6}>
          <Form.Item label="Young's Modulus (전면 영률)">
            <InputNumber value={youngModulusFront} onChange={v => setYoungModulusFront(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
        <Col span={6}>
          <Form.Item label="Density (전면 밀도)">
            <InputNumber value={densityFront} onChange={v => setDensityFront(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
        <Col span={6}>
          <Form.Item label="Poisson's Ratio (전면 포아송비)">
            <InputNumber value={poissonRatioFront} onChange={v => setPoissonRatioFront(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
      </Row>

      <Divider orientation="left">🧱 Wall 물성 (충돌 벽체 재료)</Divider>
      <Row gutter={16}>
        <Col span={6}>
          <Form.Item label="Young's Modulus (벽체 영률)">
            <InputNumber value={youngModulusWall} onChange={v => setYoungModulusWall(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
        <Col span={6}>
          <Form.Item label="Density (벽체 밀도)">
            <InputNumber value={densityWall} onChange={v => setDensityWall(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
        <Col span={6}>
          <Form.Item label="Poisson's Ratio (벽체 포아송비)">
            <InputNumber value={poissonRatioWall} onChange={v => setPoissonRatioWall(v || 0)} style={{ width: '100%' }} />
          </Form.Item>
        </Col>
      </Row>

      <Divider orientation="left">📏 Cylinder Dimensions (r, outerR, h1, h2, backR)</Divider>
      <Row gutter={16}>
        {['반지름 r', '외부 반지름 outerR', '높이 h1', '높이 h2', '후면 반지름 backR'].map((label, index) => (
          <Col span={4} key={label}>
            <Form.Item label={label}>
              <InputNumber
                value={cylinderDimensions[index]}
                min={0}
                step={0.001}
                onChange={(val) => {
                  const updated = [...cylinderDimensions] as [number, number, number, number, number];
                  updated[index] = val ?? 0;
                  setCylinderDimensions(updated);
                }}
              />
            </Form.Item>
          </Col>
        ))}
      </Row>
    </>
  )}

  {type === 'Sphere' && (
    <Row gutter={16}>
      <Col span={6}>
        <Form.Item label="Impactor Radius (구체 반지름)">
          <Input value={dimension.toString()} onChange={e => setDimension(parseFloat(e.target.value))} />
        </Form.Item>
      </Col>
      <Col span={6}>
        <Form.Item label="Damper Size (댐퍼 크기: width, height, offsetDistance)">
          <Input value={dimensionDamper.join(',')} onChange={e => {
            const parts = e.target.value.split(',').map(Number);
            if (parts.length === 3) setDimensionDamper([parts[0], parts[1], parts[2]]);
          }} />
        </Form.Item>
      </Col>
      <Col span={6}>
        <Form.Item label="Mesh Size (메시 해상도)">
          <InputNumber value={meshSize} onChange={(val) => setMeshSize(val || 0)} style={{ width: '100%' }} />
        </Form.Item>
      </Col>
    </Row>
  )}

  <Button type="primary" onClick={handleDownload} style={{ marginTop: 24 }}>
    📄 입력파일 저장
  </Button>
</Form>
      </div>
    </BaseLayout>
  );
};

export default DropWeightImpactTestGenerator;