import React from "react";
import Plot from "react-plotly.js";

interface Props {
  span: number;
  load: number;
}

const UdlLoadDistributionChart: React.FC<Props> = ({
  span,
  load
}) => {
  const numPoints = 100;
  const dx = span / (numPoints - 1);

  const xPositions = Array.from(
    { length: numPoints },
    (_, i) => i * dx
  );

  const q = load / span;
  const yValues = xPositions.map(() => q);

  return (
    <Plot
      data={[
        {
          x: xPositions,
          y: yValues,
          type: "scatter",
          mode: "lines",
          name: "UDL 분포",
          line: { shape: "hv" }
        }
      ]}
      layout={{
        title: {
          text: "균등 분포 하중 (UDL)",
          font: { size: 20 }
        },
        xaxis: {
          title: {
            text: "보 길이 위치 (mm)",
            font: { size: 16 }
          }
        },
        yaxis: {
          title: {
            text: "하중 강도 (N/mm)",
            font: { size: 16 }
          }
        },
        margin: { l: 60, r: 20, t: 50, b: 50 },
        legend: { orientation: "h" }
      }}
      style={{ width: "100%", height: 300 }}
      useResizeHandler={true}
    />
  );
};

export default UdlLoadDistributionChart;
