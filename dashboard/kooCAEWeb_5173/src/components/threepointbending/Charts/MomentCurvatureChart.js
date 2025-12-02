import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import Plot from "react-plotly.js";
import ModelFormulaBox from "../../common/ModelFormulaBox";
const MomentCurvatureChart = ({ curvatures, moments }) => (_jsxs(_Fragment, { children: [_jsx(ModelFormulaBox, { title: "\uBAA8\uBA58\uD2B8 vs \uACE1\uB960 \uAD00\uACC4\uC2DD", description: "\uB2E8\uC21C \uD0C4\uC131 \uD728 \uD574\uC11D\uC5D0\uC11C \uBAA8\uBA58\uD2B8-\uACE1\uB960 \uAD00\uACC4\uB294 \uC544\uB798\uC640 \uAC19\uC2B5\uB2C8\uB2E4.", formulas: [
                "M = E \\cdot I \\cdot \\kappa"
            ] }), _jsx(Plot, { data: [
                {
                    x: curvatures,
                    y: moments,
                    type: "scatter",
                    mode: "lines+markers",
                    name: "모멘트-곡률 곡선",
                    line: { shape: "spline" }
                }
            ], layout: {
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
            }, style: { width: "100%", height: 400 }, useResizeHandler: true })] }));
export default MomentCurvatureChart;
