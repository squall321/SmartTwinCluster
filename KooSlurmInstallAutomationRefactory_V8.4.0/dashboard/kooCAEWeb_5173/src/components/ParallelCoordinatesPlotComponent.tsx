import React from 'react';
import Plot from 'react-plotly.js';

/**
 * MeasurementDB: 20 entities × 30 conditions
 */
interface MeasurementDB {
  entities: string[];
  conditions: { [key: string]: number }[]; // length 30, keys: roll, pitch, yaw ...
  values: Float32Array;                    // length = entities.length * conditions.length
  getValue(entityIdx: number, condIdx: number): number;
  setValue(entityIdx: number, condIdx: number, value: number): void;
}

interface ParallelCoordsProps {
  data: MeasurementDB;
  angleKeys?: string[];     // 기본: ['roll', 'pitch', 'yaw']
  valueKey?: string;        // 기본: 'stress'
  title?: string;
}

/**
 * 🔷  ParallelCoordinatesPlotComponent
 *   - 축 : roll, pitch, yaw, stress
 *   - 색 : entity index를 기반으로 연속형 색상 매핑
 */
const ParallelCoordinatesPlotComponent: React.FC<ParallelCoordsProps> = ({
  data,
  angleKeys = ['roll', 'pitch', 'yaw'],
  valueKey = 'stress',
  title = 'Parallel Coordinates Plot',
}) => {
  const numEntities = data.entities.length;
  const numConditions = data.conditions.length;

  const records: any[] = [];
  const entityIndices: number[] = [];

  data.entities.forEach((entity, pIdx) => {
    for (let cIdx = 0; cIdx < numConditions; cIdx++) {
      const rec: any = {};
      angleKeys.forEach((k) => (rec[k] = data.conditions[cIdx][k]));
      rec[valueKey] = data.getValue(pIdx, cIdx);
      records.push(rec);
      entityIndices.push(pIdx); // 각 조합의 엔티티 인덱스 저장
    }
  });

  const dimensions = [
    ...angleKeys.map((k) => ({
      label: k,
      values: records.map((r) => r[k]),
    })),
    {
      label: valueKey,
      values: records.map((r) => r[valueKey]),
    },
  ];

  return (
    <div style={{ width: '100%' }}>
      <h3 style={{ textAlign: 'center' }}>{title}</h3>
      <Plot
        data={[
          {
            type: 'parcoords',
            line: {
              color: entityIndices,
              colorscale: 'Jet',
              showscale: true,
              colorbar: {
                title: 'Part Index',
              },
            },
            dimensions: dimensions,
          } as any,
        ]}
        layout={{
          autosize: true,
          height: 500,
          margin: { l: 60, r: 30, b: 40, t: 40 },
        }}
        config={{ responsive: true }}
        style={{ width: '100%' }}
      />
    </div>
  );
};

export default ParallelCoordinatesPlotComponent;
