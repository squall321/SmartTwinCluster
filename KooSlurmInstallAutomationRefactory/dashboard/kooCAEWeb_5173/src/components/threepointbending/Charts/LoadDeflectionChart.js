import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import Plot from "react-plotly.js";
import ModelFormulaBox from "../../common/ModelFormulaBox";
const LoadDeflectionChart = ({ loads, deflections }) => (_jsxs(_Fragment, { children: [_jsx(ModelFormulaBox, { title: "\uD558\uC911 vs \uCC98\uC9D0 \uC774\uB860\uC2DD", description: "\uB2E8\uC21C\uC9C0\uC9C0\uBCF4 \uC911\uC559\uD558\uC911\uC758 \uCC98\uC9D0 \uACF5\uC2DD\uC785\uB2C8\uB2E4.", formulas: [
                "\\delta = \\frac{P \\cdot a \\cdot b (L^2 - a b)}{3 L E I}"
            ] }), _jsx(Plot, { data: [
                {
                    x: loads,
                    y: deflections,
                    type: "scatter",
                    mode: "lines+markers",
                    name: "하중-처짐 곡선",
                    line: { shape: "spline" }
                }
            ], layout: {
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
            }, style: { width: "100%", height: 400 }, useResizeHandler: true })] }));
export default LoadDeflectionChart;
