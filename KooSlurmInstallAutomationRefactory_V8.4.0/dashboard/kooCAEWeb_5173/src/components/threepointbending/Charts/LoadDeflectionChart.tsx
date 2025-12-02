import React from "react";
import Plot from "react-plotly.js";
import ModelFormulaBox from "../../common/ModelFormulaBox";

interface Props {
  loads: number[];
  deflections: number[];
}

const LoadDeflectionChart: React.FC<Props> = ({
  loads,
  deflections
}) => (
  <>
    <ModelFormulaBox
      title="하중 vs 처짐 이론식"
      description="단순지지보 중앙하중의 처짐 공식입니다."
      formulas={[
        "\\delta = \\frac{P \\cdot a \\cdot b (L^2 - a b)}{3 L E I}"
      ]}
    />

    <Plot
      data={[
        {
          x: loads,
          y: deflections,
          type: "scatter",
          mode: "lines+markers",
          name: "하중-처짐 곡선",
          line: { shape: "spline" }
        }
      ]}
      layout={{
        title: {
          text: "하중 vs 처짐 곡선",
          font: { size: 20 }
        },
        xaxis: {
          title: {
            text: "하중 (N)",
            font: { size: 16 }
          }
        },
        yaxis: {
          title: {
            text: "중심 처짐 (mm)",
            font: { size: 16 }
          }
        },
        margin: { l: 60, r: 20, t: 50, b: 50 },
        legend: { orientation: "h" }
      }}
      style={{ width: "100%", height: 400 }}
      useResizeHandler={true}
    />
  </>
);

export default LoadDeflectionChart;
