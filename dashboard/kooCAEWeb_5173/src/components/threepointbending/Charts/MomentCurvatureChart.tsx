import React from "react";
import Plot from "react-plotly.js";
import ModelFormulaBox from "../../common/ModelFormulaBox";

interface Props {
  curvatures: number[];
  moments: number[];
}

const MomentCurvatureChart: React.FC<Props> = ({
  curvatures,
  moments
}) => (
  <>
    <ModelFormulaBox
      title="모멘트 vs 곡률 관계식"
      description="단순 탄성 휨 해석에서 모멘트-곡률 관계는 아래와 같습니다."
      formulas={[
        "M = E \\cdot I \\cdot \\kappa"
      ]}
    />

    <Plot
      data={[
        {
          x: curvatures,
          y: moments,
          type: "scatter",
          mode: "lines+markers",
          name: "모멘트-곡률 곡선",
          line: { shape: "spline" }
        }
      ]}
      layout={{
        title: {
          text: "모멘트 vs 곡률 곡선",
          font: { size: 20 }
        },
        xaxis: {
          title: {
            text: "곡률 (rad/m)",
            font: { size: 16 }
          }
        },
        yaxis: {
          title: {
            text: "모멘트 (Nm)",
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

export default MomentCurvatureChart;
