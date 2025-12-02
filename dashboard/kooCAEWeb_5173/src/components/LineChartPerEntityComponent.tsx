import React, { useState } from 'react';
import Plot from 'react-plotly.js';
import { Checkbox, Select, Typography } from 'antd';

const { Option } = Select;
const { Title } = Typography;

interface MeasurementDB {
  entities: string[];
  conditions: { [key: string]: number }[];
  values: Float32Array;
  getValue(entityIdx: number, condIdx: number): number;
  setValue(entityIdx: number, condIdx: number, value: number): void;
}

interface LineChartPerEntityProps {
  data: MeasurementDB;
  title?: string;
  xLabelKeys?: string[]; // ex: ['roll', 'pitch', 'yaw']
  selectedEntities?: string[]; // 초기 선택값
}

const LineChartPerEntityComponent: React.FC<LineChartPerEntityProps> = ({
  data,
  title = 'Line Chart per Entity',
  xLabelKeys,
  selectedEntities,
}) => {
  const numEntities = data.entities.length;
  const numConditions = data.conditions.length;

  const [selected, setSelected] = useState<string[]>(selectedEntities ?? data.entities);
  const [useSubplot, setUseSubplot] = useState(false);

  const xLabels = data.conditions.map((cond, i) => {
    if (xLabelKeys && xLabelKeys.length > 0) {
      return xLabelKeys.map((key) => `${key}:${cond[key]?.toFixed(1) ?? '?'}`).join(', ');
    }
    return `Cond_${i}`;
  });

  // x 레이블의 평균 길이로 subplot rowgap 동적 조절
  const avgLabelLength = xLabels.reduce((sum, label) => sum + label.length, 0) / xLabels.length;
  const rowGap = Math.min(0.5, Math.max(0.05, avgLabelLength / 100));

  const traces: Plotly.Data[] = [];
  const subplotLayouts: Partial<Plotly.Layout> = {
    grid: useSubplot
      ? ({
          rows: selected.length,
          columns: 1,
          pattern: 'independent',
          rowgap: rowGap,
        } as any)
      : undefined,
  };

  const axisLayout: Partial<Plotly.Layout> = {};

  selected.forEach((entity, i) => {
    const entityIdx = data.entities.indexOf(entity);
    if (entityIdx === -1) return;
    const yValues: number[] = [];
    for (let j = 0; j < numConditions; j++) {
      yValues.push(data.getValue(entityIdx, j));
    }
    traces.push({
      x: xLabels,
      y: yValues,
      name: entity,
      type: 'scatter',
      mode: 'lines+markers',
      xaxis: useSubplot ? `x${i + 1}` : 'x',
      yaxis: useSubplot ? `y${i + 1}` : 'y',
    });

    if (useSubplot) {
      (axisLayout as any)[`xaxis${i + 1}`] = {
        title: i === selected.length - 1 ? { text: xLabelKeys ? xLabelKeys.join(' + ') : 'Condition Index' } : undefined,
        tickangle: -45,
        automargin: true,
        showticklabels: i === selected.length - 1, // 마지막만 x축 눈금 표시
      };
      (axisLayout as any)[`yaxis${i + 1}`] = {
        title: { text: entity },
        automargin: true,
      };
    }
  });

  return (
    <div style={{ width: '100%' }}>
      <Title level={4} style={{ textAlign: 'center' }}>{title}</Title>

      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16 }}>
        <Select
          mode="multiple"
          allowClear
          style={{ minWidth: 300 }}
          placeholder="Select entities"
          value={selected}
          onChange={setSelected}
        >
          {data.entities.map((e) => (
            <Option key={e} value={e}>{e}</Option>
          ))}
        </Select>
        <Checkbox checked={useSubplot} onChange={(e) => setUseSubplot(e.target.checked)}>
          개별 subplot 보기
        </Checkbox>
      </div>

      <Plot
        data={traces}
        layout={{
          autosize: true,
          height: 400 + selected.length * 100,
          margin: { l: 60, r: 30, b: 150, t: 30 },
          showlegend: !useSubplot,
          ...subplotLayouts,
          ...axisLayout,
          xaxis: useSubplot ? undefined : {
            title: { text: xLabelKeys ? xLabelKeys.join(' + ') : 'Condition Index' },
            tickangle: -45,
            automargin: true,
          },
          yaxis: useSubplot ? undefined : {
            title: { text: 'Value' },
            automargin: true,
          },
        }}
        config={{ responsive: true, displayModeBar: true }}
        style={{ width: '100%' }}
      />
    </div>
  );
};

export default LineChartPerEntityComponent;