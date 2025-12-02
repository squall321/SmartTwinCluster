// src/components/mck/HarmonicPlot.tsx
import React from 'react';
import Plot from 'react-plotly.js';
import { Card } from 'antd';

interface HarmonicPlotProps {
  frequencies: number[];
  magnitudeDB: number[][];
  phaseDeg: number[][];
  forceLabels: string[];
}

const colors = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd'];

const HarmonicPlot: React.FC<HarmonicPlotProps> = ({
  frequencies,
  magnitudeDB,
  phaseDeg,
  forceLabels,
}) => {
  const magTraces = magnitudeDB.map((mag, idx) => ({
    x: frequencies,
    y: mag,
    type: 'scatter',
    mode: 'lines',
    name: `${forceLabels[idx]} Mag`,
    line: { color: colors[idx % colors.length] },
  }));

  const phaseTraces = phaseDeg.map((phase, idx) => ({
    x: frequencies,
    y: phase,
    type: 'scatter',
    mode: 'lines',
    name: `${forceLabels[idx]} Phase`,
    line: {
      color: colors[idx % colors.length],
      dash: 'dot',
    },
    yaxis: 'y2',
  }));

  return (
    <Card title="Harmonic Response" style={{ marginTop: 16 }}>
      <Plot
        data={[...magTraces, ...phaseTraces] as any}
        layout={{
          xaxis: { title: 'Frequency (Hz)', range: [0, 200] },
          yaxis: { title: 'Magnitude (dB)', range: [-100, 20] },
          yaxis2: {
            title: 'Phase (deg)',
            overlaying: 'y',
            side: 'right',
            range: [-180, 180],
          },
          legend: { orientation: 'h' },
          height: 500,
        } as any}
      />
    </Card>
  );
};

export default HarmonicPlot;
