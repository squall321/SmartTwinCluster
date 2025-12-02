import { jsx as _jsx } from "react/jsx-runtime";
import Plot from "react-plotly.js";
const DeflectedShapeChart = ({ deflections }) => {
    const numPoints = deflections.length;
    const span = 200;
    const dx = span / (numPoints - 1);
    const xPositions = Array.from({ length: numPoints }, (_, i) => i * dx);
    return (_jsx(Plot, { data: [
            {
                x: xPositions,
                y: deflections,
                type: "scatter",
                mode: "lines",
                name: "Deflected Shape",
                line: { shape: "spline" }
            }
        ], layout: {
            title: "Deflected Shape",
            xaxis: { title: "Beam Length (mm)" },
            yaxis: { title: "Deflection (mm)" },
            margin: { l: 60, r: 20, t: 50, b: 50 },
            legend: { orientation: "h" }
        }, style: { width: "100%", height: 400 }, useResizeHandler: true }));
};
export default DeflectedShapeChart;
