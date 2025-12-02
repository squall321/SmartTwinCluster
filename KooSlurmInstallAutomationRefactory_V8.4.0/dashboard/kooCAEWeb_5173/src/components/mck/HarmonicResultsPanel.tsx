import React from 'react';
import { Card } from 'antd';
import { Line } from '@ant-design/plots';
import { HarmonicResult } from '../../types/mck/simulationTypes';

interface HarmonicResultsPanelProps {
  result: HarmonicResult;
}

const HarmonicResultsPanel: React.FC<HarmonicResultsPanelProps> = ({ result }) => {
  const data: any[] = [];

  result.frequency.forEach((freq, idx) => {
    result.magnitudeDB.forEach((magArr, massIdx) => {
      data.push({
        freq,
        value: magArr[idx],
        series: `Node ${massIdx + 1}`,
      });
    });
  });

  const config = {
    data,
    xField: 'freq',
    yField: 'value',
    seriesField: 'series',
    smooth: true,
    height: 300,
    yAxis: {
      title: { text: 'Magnitude (dB)' },
    },
    xAxis: {
      title: { text: 'Frequency (Hz)' },
    },
  };

  return (
    <Card title="Harmonic Response Result" size="small" style={{ marginTop: 16 }}>
      <Line {...config} />
    </Card>
  );
};

export default HarmonicResultsPanel;
