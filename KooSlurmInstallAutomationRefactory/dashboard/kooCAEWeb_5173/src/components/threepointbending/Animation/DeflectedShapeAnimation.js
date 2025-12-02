import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import Plot from "react-plotly.js";
import ModelFormulaBox from "../../common/ModelFormulaBox";
const DeflectedShapeAnimation = ({ shapes, loads }) => {
    if (shapes.length === 0)
        return null;
    const initialShape = shapes[0];
    const frames = shapes.map((shape, i) => ({
        name: `P=${loads[i]}N`,
        data: [
            {
                x: shape.xPositions,
                y: shape.yPositions,
                type: "scatter",
                mode: "lines",
                line: { color: "blue" }
            }
        ]
    }));
    return (_jsxs(_Fragment, { children: [_jsx(ModelFormulaBox, { title: "\uBCC0\uD615 \uACE1\uC120 \uACC4\uC0B0\uC2DD", description: "\uACE1\uB960\uC744 \uC801\uBD84\uD558\uC5EC \uBCF4\uC758 \uBCC0\uD615 \uACE1\uC120\uC744 \uC5BB\uC2B5\uB2C8\uB2E4.", formulas: [
                    "\\theta(x) = \\int_0^x \\kappa(s) \\, ds",
                    "w(x) = \\int_0^x \\theta(s) \\, ds"
                ] }), _jsx(Plot, { data: [
                    {
                        x: initialShape.xPositions,
                        y: initialShape.yPositions,
                        type: "scatter",
                        mode: "lines",
                        name: "보 변형 형상",
                        line: { color: "blue" }
                    }
                ], layout: {
                    title: {
                        text: "보 변형 형상 애니메이션",
                        font: { size: 20 }
                    },
                    xaxis: {
                        title: {
                            text: "보 길이 방향 위치 (mm)",
                            font: { size: 16 }
                        }
                    },
                    yaxis: {
                        title: {
                            text: "변형량 (mm)",
                            font: { size: 16 }
                        }
                    },
                    margin: { l: 60, r: 20, t: 50, b: 50 },
                    legend: { orientation: "h" },
                    updatemenus: [
                        {
                            type: "buttons",
                            showactive: false,
                            y: 1.1,
                            x: 1,
                            xanchor: "right",
                            yanchor: "bottom",
                            buttons: [
                                {
                                    label: "Play",
                                    method: "animate",
                                    args: [null, {
                                            frame: { duration: 500, redraw: true },
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
                    ]
                }, frames: frames, style: { width: "100%", height: 400 }, useResizeHandler: true })] }));
};
export default DeflectedShapeAnimation;
