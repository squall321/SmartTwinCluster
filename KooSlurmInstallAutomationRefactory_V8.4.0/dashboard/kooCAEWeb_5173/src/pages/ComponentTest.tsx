import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import ColoredScatter2DComponent from '../components/ColoredScatter2DComponent';
import Scatter3DComponent from '../components/Scatter3DComponent';
import ColoredScatter3DComponent from '../components/ColoredScatter3DComponent';
import HeatmapMatrixComponent from '../components/HeatmapMatrixComponent';
import LineChartPerEntityComponent from '../components/LineChartPerEntityComponent';
import ParallelCoordinatesPlotComponent from '../components/ParallelCoordinatesPlotComponent';

const { Title, Paragraph } = Typography;

type AngleSet = { roll: number; pitch: number; yaw: number };

interface MeasurementDB {
    entities: string[]; // 예: ['Part_1', ..., 'Part_20']
    conditions: { [key: string]: number }[]; // 예: { roll, pitch, yaw }
    values: Float32Array;
    getValue(entityIdx: number, condIdx: number): number;
    setValue(entityIdx: number, condIdx: number, value: number): void;
  }
  


const ComponentTestPage = () => {


    
    /////////////// Scatter Data Test Set
    const data: (string | number)[][] = [
        ['x', 'y', 'z', 'w', 'v'],
        ...Array.from({ length: 30 }, () => {
          const x = +(Math.random() * 100).toFixed(2);
          const y = +(Math.random() * 100).toFixed(2);
          const z = +(Math.random() * 100).toFixed(2);
          const w = +(x * y + z).toFixed(2);
          const v = +Math.sin(x + y + z).toFixed(4);
          return [x, y, z, w, v];
        }),
      ];
      
      
    ///////////// StressDB Test Set
    const NUM_PARTS = 20;
    const NUM_ANGLES = 30;
    // 1) 부품 ID
    const parts = Array.from({ length: NUM_PARTS }, (_, i) => `Part_${i + 1}`);

    // 2) 오일러 각 30개 (임의 분포 예시)
    const angleSets = Array.from({ length: NUM_ANGLES }, () => ({
    roll:  (Math.random() * 360 - 180).toFixed(2),   // -180° ~ 180°
    pitch: (Math.random() * 180 -  90).toFixed(2),   //  -90° ~  90°
    yaw:   (Math.random() * 360 - 180).toFixed(2),   // -180° ~ 180°
    })).map(a => ({ roll: +a.roll, pitch: +a.pitch, yaw: +a.yaw }));

    // 3) 응력 값  (예:  0 ~ 500 MPa   난수)
    const stress = new Float32Array(NUM_PARTS * NUM_ANGLES);
    for (let p = 0; p < NUM_PARTS; p++) {
    for (let a = 0; a < NUM_ANGLES; a++) {
        const idx = p * NUM_ANGLES + a;
        stress[idx] = +(Math.random() * 500).toFixed(2);
    }
    }

    // 4) helper
    const db: MeasurementDB = {
    entities: parts,
    conditions: angleSets,
    values: stress,
    getValue: (p, a) => stress[p * NUM_ANGLES + a],
    setValue: (p, a, v) => { stress[p * NUM_ANGLES + a] = v; },
    };

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      width: '100%',
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>📦 Component Test</Title>
        <Paragraph>
          새로 개발된 Component를 테스트하기 위한 페이지입니다.
        </Paragraph>
        <div style={{ padding: '20px' }}>
        <div style={{ marginBottom: '30px' }}>
          <ColoredScatter2DComponent title="Colored Scatter 2D Component" data={data} />
        </div>
        <div style={{ marginBottom: '30px' }}>
          <Scatter3DComponent title="Scatter 3D Component" data={data} />
        </div>
        <div style={{ marginBottom: '30px' }}>
          <ColoredScatter3DComponent title="Colored Scatter 3D Component" data={data} />
        </div>
        <div style={{ marginBottom: '30px' }}>
          <HeatmapMatrixComponent title="Heatmap Matrix Component" data={db} xLabelKeys={['roll', 'pitch', 'yaw']} />
        </div>
        <div style={{ marginBottom: '30px' }}>
          <LineChartPerEntityComponent title="Line Chart Per Entity Component" data={db} xLabelKeys={['roll', 'pitch', 'yaw']} />
        </div>
        <div style={{ marginBottom: '30px' }}>
          <ParallelCoordinatesPlotComponent
            data={db}
            angleKeys={['roll', 'pitch', 'yaw']}
            valueKey="stress"
            title="Euler Angles & Stress — Parallel Coordinates"
          />
        </div>
      
      </div>

      </div>
    </BaseLayout>
  );
};

export default ComponentTestPage;
