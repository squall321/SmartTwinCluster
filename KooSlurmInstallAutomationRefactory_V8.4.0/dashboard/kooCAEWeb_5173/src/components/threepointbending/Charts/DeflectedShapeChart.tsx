import React from "react";
import Plot from "react-plotly.js";

interface Props {
  deflections: number[];
}

const DeflectedShapeChart: React.FC<Props> = ({
  deflections
}) => {
  const numPoints = deflections.length;
  const span = 200;
  const dx = span / (numPoints - 1);

  const xPositions = Array.from(
    { length: numPoints },
    (_, i) => i * dx
  );

  return (
    <Plot
      data={[
        {
          x: xPositions,
          y: deflections,
          type: "scatter",
          mode: "lines",
          name: "Deflected Shape",
          line: { shape: "spline" }
        }
      ]}
      layout={{
        title: "Deflected Shape",
        xaxis: { title: "Beam Length (mm)" },
        yaxis: { title: "Deflection (mm)" },
        margin: { l: 60, r: 20, t: 50, b: 50 },
        legend: { orientation: "h" }
      } as any}
      style={{ width: "100%", height: 400 }}
      useResizeHandler={true}
    />
  );
};

export default DeflectedShapeChart;
