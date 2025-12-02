import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJaxContext } from "better-react-mathjax";
const { Title, Paragraph, Text } = Typography;
const Chapter12 = () => {
    return (_jsx(MathJaxContext, { version: 3, config: {
            tex: {
                packages: { '[+]': ['ams', 'bm'] },
                inlineMath: [
                    ["$", "$"],
                    ["\\(", "\\)"]
                ],
                displayMath: [
                    ["$$", "$$"],
                    ["\\[", "\\]"]
                ]
            }
        }, children: _jsxs("div", { className: "space-y-6", children: [_jsx(Paragraph, { children: "\uBA40\uD2F0\uD53C\uC9C1\uC2A4\uB294 \uB450 \uAC1C \uC774\uC0C1\uC758 \uBB3C\uB9AC \uD604\uC0C1\uC744 \uB3D9\uC2DC\uC5D0 \uACE0\uB824\uD558\uC5EC \uBCF5\uD569\uC801\uC778 \uC2DC\uC2A4\uD15C\uC744 \uD574\uC11D\uD558\uB294 \uAE30\uBC95\uC785\uB2C8\uB2E4. \uBCF8 \uC7A5\uC5D0\uC11C\uB294 \uC5F4-\uAE30\uACC4(thermo-mechanical), \uC720\uCCB4-\uAD6C\uC870(fsi), \uC804\uC790\uAE30-\uAE30\uACC4(em-mechanical) \uB4F1 \uB2E4\uC591\uD55C \uC0B0\uC5C5 \uC751\uC6A9\uC744 FEM \uD504\uB808\uC784\uC6CC\uD06C \uB0B4\uC5D0\uC11C \uC5B4\uB5BB\uAC8C \uD1B5\uD569\uD558\uB294\uC9C0\uB97C \uB2E4\uB8F9\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "1. \uC5F4-\uAE30\uACC4 \uC5F0\uC131 \uBB38\uC81C" }), _jsx(ModelFormulaBox, { title: "\uC5F4 \uC804\uB2EC \uBC29\uC815\uC2DD", description: "\uC6B0\uC120 \uC5F4 \uD574\uC11D\uC740 \uB2E4\uC74C \uC9C0\uBC30 \uBC29\uC815\uC2DD\uC744 \uB530\uB985\uB2C8\uB2E4.", formulas: ["\\nabla \\cdot (k \\nabla T) + Q = \\rho c \\frac{\\partial T}{\\partial t}"] }), _jsx(ModelFormulaBox, { title: "\uC5F4 \uD33D\uCC3D\uC73C\uB85C \uC778\uD55C \uAE30\uACC4 \uD558\uC911", description: "\uC5F4 \uC751\uB825\uC740 \uB2E4\uC74C\uACFC \uAC19\uC774 \uD33D\uCC3D\uACC4\uC218 \\(\\alpha\\)\uC640 \uC628\uB3C4\uCC28 \\(\\Delta T\\)\uB85C\uBD80\uD130 \uACC4\uC0B0\uB429\uB2C8\uB2E4.", formulas: ["{\\sigma}_\\text{thermal} = -E \\alpha \\Delta T {I}"] }), _jsx(Paragraph, { children: "\uC774\uC640 \uAC19\uC774 \uC5F4 \uC804\uB2EC \uD574\uC11D \uD6C4 \uC628\uB3C4\uC7A5 \\(T(x,t)\\)\uC744 \uAE30\uACC4 \uD574\uC11D\uC758 \uD558\uC911\uC73C\uB85C \uB118\uACA8\uC8FC\uB294 \uBC29\uC2DD\uC73C\uB85C \uC5F0\uC131\uC774 \uAD6C\uD604\uB429\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "2. \uC720\uCCB4-\uAD6C\uC870 \uC5F0\uC131 (FSI)" }), _jsx(Paragraph, { children: "\uC720\uCCB4\uC640 \uAD6C\uC870\uAC00 \uC0C1\uD638\uC791\uC6A9\uD558\uB294 \uACBD\uC6B0, \uC720\uCCB4\uB294 \uAD6C\uC870\uC5D0 \uD798\uC744 \uAC00\uD558\uACE0 \uAD6C\uC870\uB294 \uC720\uB3D9 \uC601\uC5ED\uC758 \uACBD\uACC4\uB97C \uBC14\uAFB8\uB294 \uC2DD\uC73C\uB85C \uC5F0\uC131\uB429\uB2C8\uB2E4." }), _jsx(ModelFormulaBox, { title: "\uC720\uCCB4 \uC601\uC5ED: Navier-Stokes \uBC29\uC815\uC2DD", description: "\uBD88\uC548\uC815 \uBE44\uC555\uCD95 \uC720\uCCB4\uC758 \uC6B4\uB3D9\uC744 \uC124\uBA85\uD569\uB2C8\uB2E4.", formulas: ["\\rho \\left( \\frac{\\partial \\mathbf{v}}{\\partial t} + \\mathbf{v} \\cdot \\nabla \\mathbf{v} \\right) = -\\nabla p + \\mu \\nabla^2 \\mathbf{v} + \\mathbf{f}"] }), _jsx(ModelFormulaBox, { title: "\uACBD\uACC4 \uC5F0\uC131 \uC870\uAC74", description: "FSI\uC5D0\uC11C\uB294 \uB2E4\uC74C\uACFC \uAC19\uC740 \uC870\uAC74\uC774 \uACBD\uACC4\uBA74\uC5D0\uC11C \uD544\uC694\uD569\uB2C8\uB2E4.", formulas: ["\\mathbf{v}_\\text{fluid} = \\frac{\\partial \\mathbf{u}_\\text{solid}}{\\partial t}, ", "{\\sigma}_\\text{fluid} \\cdot \\mathbf{n} = {\\sigma}_\\text{solid} \\cdot \\mathbf{n}"] }), _jsx(Divider, { orientation: "left", children: "3. \uC0B0\uC5C5 \uC608\uC81C \uBC0F \uD574\uC11D \uD750\uB984" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uC5F4-\uAE30\uACC4 \uC608\uC81C", children: _jsx(List, { dataSource: [
                                        "반도체 패키지 열팽창으로 인한 변형 및 응력 해석",
                                        "브레이크 디스크의 마찰열에 따른 변형 분석"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "FSI \uC608\uC81C", children: _jsx(List, { dataSource: [
                                        "자동차 외피의 공력 해석",
                                        "동맥 벽과 혈류의 연성 시뮬레이션"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) })] }), _jsx(Divider, { orientation: "left", children: "4. \uC5F0\uC131 \uD574\uC11D \uC804\uB7B5" }), _jsx(List, { header: _jsx("b", { children: "\uB450 \uAC00\uC9C0 \uC8FC\uC694 \uC804\uB7B5" }), dataSource: [
                        "강연성(Strong Coupling): 두 물리현상을 동시에 계산 (monolithic)",
                        "약연성(Weak Coupling): 각 물리 계산을 분리 후 교환 (partitioned)"
                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }), _jsx(Paragraph, { children: "\uC5F0\uC131 \uBC29\uC2DD\uC758 \uC120\uD0DD\uC740 \uD574\uC758 \uC815\uD655\uB3C4, \uC548\uC815\uC131, \uACC4\uC0B0 \uBE44\uC6A9\uC5D0 \uD070 \uC601\uD5A5\uC744 \uBBF8\uCE69\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "5. \uC694\uC57D" }), _jsx(Paragraph, { children: "\uBCF8 \uC7A5\uC5D0\uC11C\uB294 \uB2E4\uC591\uD55C \uBA40\uD2F0\uD53C\uC9C1\uC2A4 \uD574\uC11D \uC2DC\uB098\uB9AC\uC624\uB97C \uC18C\uAC1C\uD558\uACE0, FEM \uB0B4 \uC5F0\uC131 \uAD6C\uD604 \uBC29\uC2DD\uACFC \uC218\uC2DD \uAD6C\uC870, \uC2E4\uC81C \uC0B0\uC5C5 \uC801\uC6A9 \uC608\uC81C\uB97C \uC124\uBA85\uD588\uC2B5\uB2C8\uB2E4. \uB2E4\uC74C \uC7A5\uC5D0\uC11C\uB294 \uACE0\uCC28 \uC694\uC18C\uB97C \uD3EC\uD568\uD55C \uACE0\uC815\uBC00 FEM \uAE30\uBC95\uC744 \uB2E4\uB8F9\uB2C8\uB2E4." })] }) }));
};
export default Chapter12;
