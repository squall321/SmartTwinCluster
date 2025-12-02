import React from 'react';
import Plot from 'react-plotly.js';

interface BarChartProps {
  data: { name: string; number: number }[];
  title?: string;
  color?: string;         // 👉 기본 색 (사용하지 않아도 됨)
  unitLabel?: string;     // 🔹 단위 라벨 ("코어", "건수" 등)
}

const generateColorMap = (names: string[]) => {
  const distinctColors = [
    '#1890ff', '#52c41a', '#f5222d', '#faad14', '#13c2c2', '#722ed1',
    '#eb2f96', '#a0d911', '#2f54eb', '#fa8c16', '#262626', '#b37feb',
  ];
  const map: Record<string, string> = {};
  names.forEach((name) => {
    const hash = [...name].reduce((acc, c) => acc + c.charCodeAt(0), 0);
    map[name] = distinctColors[hash % distinctColors.length];
  });
  return map;
};

const BarChartComponent: React.FC<BarChartProps> = ({
  data,
  title = '막대 차트',
  unitLabel = '',
}) => {
  const names = data.map((d) => d.name);
  const numbers = data.map((d) => d.number);

  const colorMap = generateColorMap(names);
  const colors = names.map((name) => colorMap[name]);

  return (
    <Plot
      data={[
        {
          type: 'bar',
          x: numbers,
          y: names,
          orientation: 'h',
          marker: { color: colors },
          text: numbers.map((v) => unitLabel ? `${v} ${unitLabel}` : `${v}`),
          textposition: 'auto',
        },
      ]}
      layout={{
        title: { text: title, font: { size: 18 }, x: 0.02 },
        margin: { l: 100, r: 20, t: 40, b: 40 },
        height: 500,
        yaxis: { automargin: true },
        xaxis: { title: { text: unitLabel || '', font: { size: 18 } }, showgrid: true },
      }}
      config={{ displayModeBar: false }}
      style={{ width: '100%' }}
    />
  );
};

export default BarChartComponent;
