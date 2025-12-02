import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
const { Title, Paragraph, Text } = Typography;
const Chapter11 = () => {
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
        }, children: _jsxs("div", { className: "space-y-6", children: [_jsx(Paragraph, { children: "\uBCF8 \uC7A5\uC5D0\uC11C\uB294 \uC720\uD55C \uC694\uC18C \uD574\uC11D\uC5D0\uC11C \uC811\uCD09(Contact)\uACFC \uB9C8\uCC30(Friction)\uC744 \uBAA8\uB378\uB9C1\uD558\uB294 \uBC29\uBC95\uC744 \uB2E4\uB8F9\uB2C8\uB2E4. \uC774\uB294 \uAD6C\uC870\uBB3C \uAC04 \uC0C1\uD638\uC791\uC6A9, \uCDA9\uB3CC, \uC131\uD615 \uD574\uC11D \uB4F1 \uB2E4\uC591\uD55C \uC0B0\uC5C5 \uBD84\uC57C\uC5D0\uC11C \uC911\uC694\uD55C \uC5ED\uD560\uC744 \uD569\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "1. \uC811\uCD09\uC758 \uC218\uD559\uC801 \uBAA8\uB378\uB9C1" }), _jsx(Paragraph, { children: "\uB450 \uBB3C\uCCB4\uAC00 \uC811\uCD09\uD558\uB294 \uACBD\uC6B0, \uC11C\uB85C \uCE68\uD22C\uD558\uC9C0 \uC54A\uC544\uC57C \uD55C\uB2E4\uB294 \uBE44\uCE68\uD22C \uC870\uAC74\uC744 \uB9CC\uC871\uD574\uC57C \uD569\uB2C8\uB2E4. \uC774\uB97C \uC218\uD559\uC801\uC73C\uB85C \uD45C\uD604\uD558\uBA74 \uB2E4\uC74C\uACFC \uAC19\uC2B5\uB2C8\uB2E4:" }), _jsx(ModelFormulaBox, { title: "\uBE44\uCE68\uD22C \uC870\uAC74", description: "\uC811\uCD09\uBA74\uC5D0\uC11C \uC8FC \uD45C\uBA74\uACFC \uC885\uC18D \uD45C\uBA74 \uC0AC\uC774\uC758 \uAC04\uACA9 $g_n$\uB294 \uD56D\uC0C1 0 \uC774\uC0C1\uC774\uC5B4\uC57C \uD569\uB2C8\uB2E4.", formulas: ["g_n \\geq 0, \\quad \\lambda_n \\geq 0, \\quad g_n \\cdot \\lambda_n = 0"] }), _jsxs(Paragraph, { children: ["\uC5EC\uAE30\uC11C ", _jsx(MathJax, { inline: true, children: "\\( \\lambda_n \\)" }), "\uC740 \uC811\uCD09\uBA74\uC5D0 \uC791\uC6A9\uD558\uB294 \uBC95\uC120 \uBC29\uD5A5 \uC811\uCD09\uB825\uC785\uB2C8\uB2E4. \uC774 \uC870\uAC74\uC744 Karush-Kuhn-Tucker(KKT) \uC870\uAC74\uC774\uB77C \uD569\uB2C8\uB2E4."] }), _jsx(Divider, { orientation: "left", children: "2. \uC811\uCD09 \uAD6C\uD604 \uBC29\uBC95" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "1. Penalty Method", children: _jsx(List, { size: "small", dataSource: [
                                        "침투 시 강한 반발력을 통해 접촉력을 근사",
                                        "단순 구현이 가능하나 penalty 계수 설정이 중요",
                                        "침투 오차 존재 가능"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "2. Lagrange Multiplier Method", children: _jsx(List, { size: "small", dataSource: [
                                        "비침투 조건을 엄격히 만족",
                                        "추가 자유도 (multipliers)가 필요",
                                        "희소 행렬 크기 증가, saddle point 문제 발생"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) })] }), _jsx(Divider, { orientation: "left", children: "3. \uB9C8\uCC30 \uBAA8\uB378\uB9C1" }), _jsx(ModelFormulaBox, { title: "Coulomb \uB9C8\uCC30 \uBC95\uCE59", description: "\uB9C8\uCC30\uB825\uC740 \uC811\uCD09\uB825\uACFC \uB9C8\uCC30\uACC4\uC218\uC5D0 \uBE44\uB840\uD558\uBA70, \uC784\uACC4\uAC12 \uC774\uB0B4\uC5D0\uC11C\uB294 stick, \uADF8 \uC774\uC0C1\uC774\uBA74 slip\uC774 \uBC1C\uC0DD\uD569\uB2C8\uB2E4.", formulas: ["|\\lambda_t| \\leq \\mu \\cdot \\lambda_n"] }), _jsxs(Paragraph, { children: ["- ", _jsx(MathJax, { inline: true, children: "\\( \\mu \\)" }), "\uB294 \uB9C8\uCC30\uACC4\uC218, ", _jsx(MathJax, { inline: true, children: "\\( \\lambda_t \\)" }), "\uB294 \uC811\uC120\uBC29\uD5A5 \uB9C8\uCC30\uB825\uC785\uB2C8\uB2E4.", _jsx("br", {}), "- Stick/slip \uC0C1\uD0DC\uB97C \uACE0\uB824\uD55C \uBE44\uC120\uD615 \uC811\uCD09 \uBB38\uC81C\uB85C \uC774\uC5B4\uC9D1\uB2C8\uB2E4."] }), _jsx(Divider, { orientation: "left", children: "4. \uBE44\uC120\uD615\uC131\uACFC \uBC18\uBCF5\uD574\uBC95" }), _jsx(Paragraph, { children: "\uC811\uCD09 \uBC0F \uB9C8\uCC30 \uBB38\uC81C\uB294 \uBCF8\uC9C8\uC801\uC73C\uB85C **\uBE44\uC120\uD615 \uBB38\uC81C**\uC774\uBA70, \uBC18\uBCF5\uC801\uC778 \uD574\uC11D \uAE30\uBC95 (\uC608: Newton-Raphson + Active Set \uC804\uB7B5)\uC744 \uD544\uC694\uB85C \uD569\uB2C8\uB2E4. \uC811\uCD09 \uC0C1\uD0DC\uAC00 \uBCC0\uD654\uD558\uBA70 \uACC4\uAC00 \uBCC0\uB3D9\uB418\uBBC0\uB85C, \uBC18\uBCF5\uC801\uC73C\uB85C \uC0C1\uD0DC\uB97C \uC5C5\uB370\uC774\uD2B8\uD558\uBA70 \uC218\uB834\uD574\uC57C \uD569\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "5. FEM \uB0B4\uC5D0\uC11C\uC758 \uAD6C\uD604 \uD750\uB984" }), _jsx(List, { bordered: true, dataSource: [
                        "접촉 후보 탐색 (contact detection)",
                        "접촉면 간 간격 및 상대 속도 계산",
                        "접촉 조건 및 마찰 조건 평가",
                        "접촉 강성 행렬 또는 힘 계산",
                        "전체 시스템에 반영 후 반복 수렴"
                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }), _jsx(Divider, { orientation: "left", children: "6. \uAC04\uB2E8\uD55C \uC608\uC81C" }), _jsx(Paragraph, { children: "\uB450 \uBE14\uB85D\uC774 \uCDA9\uB3CC\uD558\uC5EC \uC811\uCD09\uD558\uB294 \uBB38\uC81C\uB97C \uACE0\uB824\uD569\uB2C8\uB2E4. Penalty \uBC29\uC2DD\uC73C\uB85C \uC811\uCD09\uB825\uC744 \uBAA8\uB378\uB9C1\uD558\uACE0, \uB9C8\uCC30\uACC4\uC218\uB97C \uC870\uC808\uD558\uBA70 \uD574\uC11D \uACB0\uACFC\uB97C \uBE44\uAD50\uD569\uB2C8\uB2E4. \uC811\uCD09\uB825\uC758 \uBC1C\uC0DD, \uCE68\uD22C\uB7C9 \uBCC0\uD654, \uB9C8\uCC30\uB825 \uBC29\uD5A5\uC758 \uBCC0\uD654 \uB4F1\uC744 \uC2DC\uAC01\uD654\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "7. \uC694\uC57D" }), _jsx(Paragraph, { children: "\uC811\uCD09\uACFC \uB9C8\uCC30\uC740 FEM\uC5D0\uC11C \uD544\uC218\uC801\uC778 \uD655\uC7A5 \uAE30\uB2A5\uC73C\uB85C, \uB2E4\uC591\uD55C \uD574\uC11D\uC5D0 \uB110\uB9AC \uC0AC\uC6A9\uB429\uB2C8\uB2E4. \uBE44\uC120\uD615\uC131\uACFC \uC870\uAC74\uBD80 \uC81C\uC57D\uC744 \uB2E4\uB8E8\uB294 \uC218\uCE58\uAE30\uBC95\uC744 \uC798 \uC774\uD574\uD558\uACE0 \uC801\uC6A9\uD558\uB294 \uAC83\uC774 \uC911\uC694\uD569\uB2C8\uB2E4." })] }) }));
};
export default Chapter11;
