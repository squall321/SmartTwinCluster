import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";
const { Title, Paragraph, Text } = Typography;
const Chapter7 = () => {
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
        }, children: _jsxs("div", { className: "space-y-6", children: [_jsx(Paragraph, { children: "\uBCF8 \uC7A5\uC5D0\uC11C\uB294 \uC790\uC720 \uC9C4\uB3D9 \uD574\uC11D\uC744 \uC704\uD55C \uACE0\uC720\uCE58 \uBB38\uC81C\uB97C \uB2E4\uB8F9\uB2C8\uB2E4. \uAD6C\uC870\uBB3C\uC758 \uACE0\uC720\uC9C4\uB3D9\uC218\uC640 \uACE0\uC720\uD615\uC0C1(mode shape)\uC744 \uAD6C\uD558\uC5EC \uB3D9\uC801 \uD2B9\uC131\uC744 \uC774\uD574\uD558\uB294 \uB370 \uC911\uC694\uD55C \uAE30\uCD08\uB97C \uC81C\uACF5\uD569\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "1. \uC790\uC720 \uC9C4\uB3D9 \uBC29\uC815\uC2DD" }), _jsx(ModelFormulaBox, { title: "\uC9C8\uB7C9-\uAC15\uC131 \uC2DC\uC2A4\uD15C\uC758 \uC6B4\uB3D9 \uBC29\uC815\uC2DD (\uC790\uC720 \uC9C4\uB3D9)", description: "\uC678\uB825\uC774 \uC5C6\uB294 \uACBD\uC6B0, \uC6B4\uB3D9 \uBC29\uC815\uC2DD\uC740 \uB2E4\uC74C\uACFC \uAC19\uC2B5\uB2C8\uB2E4:", formulas: ["\\mathbf{M} \\ddot{\\mathbf{u}} + \\mathbf{K} \\mathbf{u} = 0"] }), _jsx(Divider, { orientation: "left", children: "2. \uACE0\uC720\uCE58 \uBB38\uC81C \uC815\uC2DD\uD654" }), _jsx(ModelFormulaBox, { title: "\uC870\uD654\uD574 \uAC00\uC815", description: "\uD574\uB97C \uB2E4\uC74C\uACFC \uAC19\uC740 \uC870\uD654\uC9C4\uB3D9 \uD615\uD0DC\uB85C \uAC00\uC815\uD569\uB2C8\uB2E4:", formulas: ["\\mathbf{u}(t) = \\mathbf{\\phi} e^{i \\omega t}"] }), _jsx(ModelFormulaBox, { title: "\uC77C\uBC18\uD654 \uACE0\uC720\uCE58 \uBB38\uC81C", description: "\uC774\uB97C \uC6B4\uB3D9 \uBC29\uC815\uC2DD\uC5D0 \uB300\uC785\uD558\uBA74 \uB2E4\uC74C\uACFC \uAC19\uC740 \uACE0\uC720\uCE58 \uBB38\uC81C\uAC00 \uC720\uB3C4\uB429\uB2C8\uB2E4:", formulas: ["(\\mathbf{K} - \\omega^2 \\mathbf{M}) \\mathbf{\\phi} = 0"] }), _jsxs(Paragraph, { children: ["\uC5EC\uAE30\uC11C:", _jsxs("ul", { children: [_jsxs("li", { children: [_jsx(MathJax, { inline: true, children: "\\( \\omega \\)" }), ": \uACE0\uC720\uC9C4\uB3D9\uC218 (rad/s)"] }), _jsxs("li", { children: [_jsx(MathJax, { inline: true, children: "\\( \\mathbf{\\phi} \\)" }), ": \uACE0\uC720\uD615\uC0C1 (mode shape)"] })] })] }), _jsx(Divider, { orientation: "left", children: "3. \uACE0\uC720\uCE58 \uD574\uC11D\uC758 \uBB3C\uB9AC\uC801 \uC758\uBBF8" }), _jsx(Paragraph, { children: "\uAD6C\uC870\uBB3C\uC740 \uAC01 \uACE0\uC720\uC9C4\uB3D9\uC218\uC5D0 \uD574\uB2F9\uD558\uB294 \uACE0\uC720\uD615\uC0C1\uC73C\uB85C \uC9C4\uB3D9\uD560 \uC218 \uC788\uC73C\uBA70, \uC678\uB825\uC774 \uD574\uB2F9 \uC8FC\uD30C\uC218\uC640 \uC77C\uCE58\uD560 \uACBD\uC6B0 \uACF5\uC9C4 \uD604\uC0C1\uC774 \uBC1C\uC0DD\uD569\uB2C8\uB2E4. \uACE0\uC720\uD615\uC0C1\uC740 \uC77C\uBC18\uC801\uC73C\uB85C \uC815\uADDC\uD654(normalization)\uB418\uC5B4 \uD45C\uD604\uB429\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "4. \uC218\uCE58 \uD574\uBC95" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uACE0\uC720\uCE58 \uD574\uC11D \uAE30\uBC95", children: _jsx(List, { size: "small", dataSource: [
                                        "Inverse Iteration",
                                        "Subspace Iteration",
                                        "Lanczos Method",
                                        "QR Algorithm"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "\uC8FC\uC694 \uD2B9\uC9D5", children: _jsx(List, { size: "small", dataSource: [
                                        "가장 작은 혹은 큰 고유치부터 계산 가능",
                                        "모드 수 제한 가능",
                                        "정규 직교성 이용한 후처리"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) })] }), _jsx(Divider, { orientation: "left", children: "5. \uC815\uADDC\uD654 \uC870\uAC74" }), _jsx(ModelFormulaBox, { title: "\uBAA8\uB4DC \uC815\uADDC\uD654", description: "\uD574\uC11D \uBC0F \uBE44\uAD50\uB97C \uC704\uD574 \uB2E4\uC74C\uACFC \uAC19\uC774 \uC815\uADDC\uD654\uD569\uB2C8\uB2E4:", formulas: ["\\mathbf{\\phi}_i^T \\mathbf{M} \\mathbf{\\phi}_j = \\delta_{ij}", "\\mathbf{\\phi}_i^T \\mathbf{K} \\mathbf{\\phi}_j = \\omega_i^2 \\delta_{ij}"] }), _jsx(Divider, { orientation: "left", children: "6. \uC751\uC6A9 \uBC0F \uC608\uC2DC" }), _jsx(Paragraph, { children: "\uACE0\uC720\uC9C4\uB3D9\uC218\uB294 \uC124\uACC4\uC5D0\uC11C \uAD6C\uC870\uBB3C\uC758 \uACF5\uC9C4 \uC8FC\uD30C\uC218\uB97C \uD53C\uD558\uAC70\uB098 \uC81C\uC5B4\uC7A5\uCE58\uC758 \uC870\uC728 \uB4F1\uC5D0 \uC0AC\uC6A9\uB429\uB2C8\uB2E4. \uC608\uB97C \uB4E4\uC5B4 \uC2A4\uB9C8\uD2B8\uD3F0\uC758 \uC9C4\uB3D9\uBAA8\uD130 \uC124\uACC4, \uACE0\uCE35\uAC74\uBB3C\uC758 \uB3D9\uC801 \uC751\uB2F5 \uBD84\uC11D \uB4F1\uC5D0 \uD65C\uC6A9\uB429\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "7. \uC694\uC57D" }), _jsx(Paragraph, { children: "\uACE0\uC720\uCE58 \uD574\uC11D\uC740 \uB3D9\uC801 \uD574\uC11D\uC758 \uD575\uC2EC \uC694\uC18C\uB85C\uC11C, \uC9C8\uB7C9 \uBC0F \uAC15\uC131\uC758 \uACE0\uC720 \uD2B9\uC131\uC73C\uB85C\uBD80\uD130 \uC2DC\uC2A4\uD15C\uC758 \uC9C4\uB3D9 \uD2B9\uC131\uC744 \uADDC\uBA85\uD560 \uC218 \uC788\uAC8C \uD574\uC90D\uB2C8\uB2E4." })] }) }));
};
export default Chapter7;
