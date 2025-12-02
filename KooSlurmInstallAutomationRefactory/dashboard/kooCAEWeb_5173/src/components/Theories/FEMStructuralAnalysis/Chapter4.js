import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJaxContext } from "better-react-mathjax";
const { Title, Paragraph, Text } = Typography;
const Chapter4 = () => {
    return (_jsx(MathJaxContext, { version: 3, config: {
            tex: {
                inlineMath: [
                    ["$", "$"],
                    ["\\(", "\\)"]
                ],
                displayMath: [
                    ["$$", "$$"],
                    ["\\[", "\\]"]
                ]
            }
        }, children: _jsxs("div", { className: "space-y-6", children: [_jsx(Paragraph, { children: "\uBCF8 \uC7A5\uC5D0\uC11C\uB294 \uB2E4\uC591\uD55C \uC694\uC18C \uD615\uC0C1\uC5D0 \uB300\uD574 \uC77C\uAD00\uB41C \uC218\uCE58 \uD574\uC11D\uC744 \uAC00\uB2A5\uD558\uAC8C \uD558\uB294 \uC774\uC18C\uD30C\uB77C\uBA54\uD2B8\uB9AD \uB9E4\uD551(Isoparametric Mapping) \uAE30\uBC95\uC744 \uB2E4\uB8F9\uB2C8\uB2E4. \uC774\uB294 \uC2E4\uC81C \uC88C\uD45C\uACC4\uC5D0\uC11C \uC790\uC5F0 \uC88C\uD45C\uACC4\uB85C \uBCC0\uD658\uD558\uC5EC \uC801\uBD84 \uBC0F \uD574\uC11D\uC744 \uC6A9\uC774\uD558\uAC8C \uD569\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "1. \uAC1C\uB150 \uC18C\uAC1C" }), _jsx(Paragraph, { children: "\uC774\uC18C\uD30C\uB77C\uBA54\uD2B8\uB9AD \uB9E4\uD551\uC740 \uC694\uC18C\uC758 \uD615\uC0C1 \uD568\uC218(Shape Function)\uB97C \uC0AC\uC6A9\uD558\uC5EC \uC2E4\uC81C \uC88C\uD45C\uACC4\uB97C \uC790\uC5F0 \uC88C\uD45C\uACC4\uB85C \uB9E4\uD551\uD569\uB2C8\uB2E4. \uC774\uB97C \uD1B5\uD574 \uBCC0\uC704, \uD558\uC911, \uAE30\uD558 \uAD6C\uC870\uB97C \uB3D9\uC77C\uD55C \uD568\uC218\uB85C \uD45C\uD604\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(ModelFormulaBox, { title: "Isoparametric Mapping", description: "\uC790\uC5F0 \uC88C\uD45C\uACC4 $(\\xi, \\eta)$\uC5D0\uC11C \uC2E4\uC81C \uC88C\uD45C $(x, y)$\uB294 \uB2E4\uC74C\uACFC \uAC19\uC774 \uD45C\uD604\uB429\uB2C8\uB2E4.", formulas: ["x = \\sum_{i=1}^n N_i(\\xi, \\eta) x_i", "y = \\sum_{i=1}^n N_i(\\xi, \\eta) y_i"] }), _jsx(Divider, { orientation: "left", children: "2. \uC790\uCF54\uBE44\uC548 \uD589\uB82C" }), _jsx(ModelFormulaBox, { title: "Jacobian Matrix", description: "\uC790\uC5F0 \uC88C\uD45C\uACC4\uC5D0\uC11C \uC2E4\uC81C \uC88C\uD45C\uACC4\uB85C\uC758 \uBCC0\uD654\uC728\uC744 \uB098\uD0C0\uB0B4\uB294 \uC790\uCF54\uBE44\uC548 \uD589\uB82C\uC740 \uB2E4\uC74C\uACFC \uAC19\uC2B5\uB2C8\uB2E4.", formulas: [
                        "J = \\begin{bmatrix} \\frac{\\partial x}{\\partial \\xi} & \\frac{\\partial x}{\\partial \\eta} \\\\ \\frac{\\partial y}{\\partial \\xi} & \\frac{\\partial y}{\\partial \\eta} \\end{bmatrix}"
                    ] }), _jsx(Paragraph, { children: "\uC790\uCF54\uBE44\uC548 \uD589\uB82C\uC744 \uC0AC\uC6A9\uD558\uBA74 \uBA74\uC801 \uC801\uBD84, \uAE30\uD558\uD559\uC801 \uBCC0\uD658, \uBCC0\uD615\uB960 \uACC4\uC0B0 \uB4F1\uC5D0 \uD575\uC2EC\uC801\uC73C\uB85C \uD65C\uC6A9\uB429\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "3. \uBA74\uC801 \uC801\uBD84 \uBCC0\uD658" }), _jsx(ModelFormulaBox, { title: "\uC801\uBD84 \uBCC0\uC218\uC758 \uBCC0\uD658", description: "\uC694\uC18C \uC601\uC5ED\uC758 \uC801\uBD84\uC740 \uC790\uCF54\uBE44\uC548 \uD589\uB82C\uC758 \uD589\uB82C\uC2DD\uC744 \uD65C\uC6A9\uD558\uC5EC \uB2E4\uC74C\uACFC \uAC19\uC774 \uBCC0\uD658\uB429\uB2C8\uB2E4.", formulas: ["\\int_{\\Omega^e} f(x, y) \\, dxdy = \\int_{-1}^{1} \\int_{-1}^{1} f(\\xi, \\eta) |J(\\xi, \\eta)| \\, d\\xi d\\eta"] }), _jsx(Divider, { orientation: "left", children: "4. \uC774\uC18C\uD30C\uB77C\uBA54\uD2B8\uB9AD \uC694\uC18C \uC608\uC2DC" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "4\uB178\uB4DC \uC0AC\uAC01\uD615 \uC694\uC18C", children: _jsx(List, { size: "small", dataSource: [
                                        "각 노드는 자연 좌표계 (-1, -1) ~ (1, 1)에 배치됨",
                                        "형상 함수는 이차원 곱 형태로 정의됨",
                                        "자코비안은 위치에 따라 일정하지 않음"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "3\uB178\uB4DC \uC0BC\uAC01\uD615 \uC694\uC18C", children: _jsx(List, { size: "small", dataSource: [
                                        "Barycentric 좌표계 사용",
                                        "선형 또는 곡선 요소 형상 표현 가능",
                                        "곡면 경계 요소에 유리함"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) })] }), _jsx(Divider, { orientation: "left", children: "5. \uC815\uB9AC" }), _jsx(Paragraph, { children: "\uC774\uC18C\uD30C\uB77C\uBA54\uD2B8\uB9AD \uB9E4\uD551\uC740 \uB2E4\uC591\uD55C \uC694\uC18C \uD615\uC0C1\uC5D0 \uB300\uD574 \uACF5\uD1B5\uB41C \uD574\uC11D \uD504\uB808\uC784\uC6CC\uD06C\uB97C \uC81C\uACF5\uD558\uBA70, \uBCF5\uC7A1\uD55C \uAE30\uD558\uD559\uC5D0 \uB300\uD55C \uC815\uD655\uD55C \uD45C\uD604\uACFC \uC218\uCE58 \uC801\uBD84\uC744 \uAC00\uB2A5\uD558\uAC8C \uD569\uB2C8\uB2E4. \uC774\uB294 2\uCC28\uC6D0 \uBC0F 3\uCC28\uC6D0 FEM\uC5D0\uC11C \uD575\uC2EC\uC801\uC778 \uC5ED\uD560\uC744 \uD558\uBA70, \uACE0\uCC28 \uC694\uC18C\uB098 \uACE1\uBA74 \uACBD\uACC4 \uCC98\uB9AC\uC5D0 \uB9E4\uC6B0 \uC720\uC6A9\uD569\uB2C8\uB2E4." })] }) }));
};
export default Chapter4;
