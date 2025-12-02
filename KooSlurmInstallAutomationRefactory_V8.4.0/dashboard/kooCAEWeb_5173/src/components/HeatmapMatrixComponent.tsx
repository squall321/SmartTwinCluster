import React from 'react';
import Plot from 'react-plotly.js';

interface MeasurementDB {
  entities: string[];
  conditions: { [key: string]: number }[];
  values: Float32Array;
  getValue(entityIdx: number, condIdx: number): number;
  setValue(entityIdx: number, condIdx: number, value: number): void;
}

interface HeatmapMatrixProps {
  data: MeasurementDB;
  title?: string;
  xLabelKeys?: string[]; // ex: ['roll', 'pitch', 'yaw'] → 조합 라벨 생성용
}

const HeatmapMatrixComponent: React.FC<HeatmapMatrixProps> = ({ data, title = 'Measurement Heatmap', xLabelKeys }) => {
  const numEntities = data.entities.length;
  const numConditions = data.conditions.length;

  // x축 라벨: 조건 조합 문자열 생성
  const xLabels = data.conditions.map((cond, i) => {
    if (xLabelKeys && xLabelKeys.length > 0) {
      return xLabelKeys.map((key) => `${key}:${cond[key]?.toFixed(1) ?? '?'}`).join(', ');
    }
    return `Cond_${i}`;
  });

  // y축 라벨: entity 이름
  const yLabels = data.entities;

  // z값 구성 (행: entity, 열: condition)
  const zValues: number[][] = [];
  for (let i = 0; i < numEntities; i++) {
    const row: number[] = [];
    for (let j = 0; j < numConditions; j++) {
      row.push(data.getValue(i, j));
    }
    zValues.push(row);
  }

  return (
    <div>
      <h3 style={{ textAlign: 'center' }}>{title}</h3>
      <Plot
        data={[
          {
            z: zValues,
            x: xLabels,
            y: yLabels,
            type: 'heatmap',
            colorscale: 'Jet',
            colorbar: {
              title: { text: 'Value' },
            },
            hoverongaps: false,
          },
        ]}
        layout={{
          autosize: true,
          height: 500,
          margin: { l: 100, r: 50, b: 150, t: 30 },
          xaxis: {
            title: { text: xLabelKeys ? xLabelKeys.join(' + ') : 'Condition' },
            tickangle: -45,
            automargin: true,
          },
          yaxis: {
            title: { text: 'Entity' },
            automargin: true,
          },
        }}
        config={{ responsive: true }}
        style={{ width: '100%' }}
      />
    </div>
  );
};

export default HeatmapMatrixComponent;
