import React from "react";
import Plot from "react-plotly.js";
import { MotorLevelSimulationResults } from "../types/motorLevelSimulation";

interface Props {
  results: MotorLevelSimulationResults;
}

const MotorLevelResultCharts: React.FC<Props> = ({ results }) => {
  const {
    time,
    a_B_average,
    rmsValue,
    r_O_global,
    gridXVals,
    gridYVals,
    magnitudeGrid
  } = results;

  // 평균 가속도 Plot 그대로 유지
  const avgAccPlot = (
    <Plot
      data={[
        {
          x: time,
          y: a_B_average,
          type: "scatter",
          mode: "lines+markers",
          name: "Avg Acceleration (G)",
          line: { color: "blue" }
        }
      ]}
              layout={{
          title: "Average Acceleration Over Time",
          xaxis: { title: "Time (s)" },
          yaxis: { title: "Acceleration (G)" },
          height: 400
        } as any}
    />
  );

  // ICR Plot 그대로 유지
  const icrPlot = (
    <Plot
      data={[
        {
          x: r_O_global.map(pos => pos[0]),
          y: r_O_global.map(pos => pos[1]),
          type: "scatter",
          mode: "lines+markers",
          name: "ICR Path",
          line: { color: "magenta" }
        }
      ]}
              layout={{
          title: "ICR Path (Top View)",
          xaxis: { title: "X (mm)" },
          yaxis: {
            title: "Y (mm)",
            scaleanchor: "x",
            scaleratio: 1
          },
          height: 400
        } as any}
    />
  );

  // Prepare frames for animation
  const frames = magnitudeGrid.map((frame, i) => ({
    name: String(i),
    data: [
      {
        z: frame,
        x: gridXVals,
        y: gridYVals,
        type: "heatmap",
        colorscale: [
          [0, "blue"],
          [0.5, "white"],
          [1, "red"]
        ],
        zmin: 0,
        zmax: 1.0,
        colorbar: { title: "Accel. (G)" }
      }
    ]
  }));

  const sliderSteps = magnitudeGrid.map((_, i) => ({
    method: "animate",
    label: `${time[i].toFixed(4)} s`,
    args: [[String(i)], {
      mode: "immediate",
      frame: { duration: 100, redraw: true }
    }]
  }));

  const layout = {
    title: "2D Vibration Contour Animation",
    xaxis: { title: "X (mm)" },
    yaxis: {
      title: "Y (mm)",
      scaleanchor: "x",
      scaleratio: 1
    },
    height: 500,
    updatemenus: [
      {
        type: "buttons",
        showactive: false,
        y: 1,
        x: 1.1,
        xanchor: "right",
        yanchor: "top",
        buttons: [
          {
            label: "Play",
            method: "animate",
            args: [null, {
              frame: { duration: 100, redraw: true },
              fromcurrent: true,
              mode: "immediate"
            }]
          },
          {
            label: "Pause",
            method: "animate",
            args: [[null], {
              mode: "immediate",
              frame: { duration: 0, redraw: false }
            }]
          }
        ]
      }
    ],
    sliders: [
      {
        steps: sliderSteps,
        active: 0
      }
    ]
  };

  return (
    <div>
      {avgAccPlot}
      {icrPlot}

      <h3 style={{ marginTop: 24 }}>Vibration Contour Animation</h3>
             <Plot
         data={frames[0].data as any}
         layout={layout as any}
         frames={frames as any}
       />
    </div>
  );
};

export default MotorLevelResultCharts;
