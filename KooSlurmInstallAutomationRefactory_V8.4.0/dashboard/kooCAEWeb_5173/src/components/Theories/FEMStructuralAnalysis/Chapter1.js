import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";
const { Title, Paragraph, Text } = Typography;
const Chapter1 = () => {
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
        }, children: _jsxs("div", { className: "space-y-6", children: [_jsx(Paragraph, { children: "\uBCF8 \uC7A5\uC5D0\uC11C\uB294 \uC720\uD55C \uC694\uC18C\uBC95(Finite Element Method, FEM)\uC758 \uC774\uB860\uC801 \uBC30\uACBD\uACFC \uC801\uC6A9 \uB3D9\uAE30\uB97C \uC0B4\uD3B4\uBCF4\uACE0, \uC218\uCE58 \uD574\uC11D \uAE30\uBC95\uC73C\uB85C\uC11C\uC758 FEM\uC758 \uC804\uBC18\uC801\uC778 \uAD6C\uC870\uC640 \uC808\uCC28\uB97C \uC124\uBA85\uD569\uB2C8\uB2E4." }), _jsx(Divider, { orientation: "left", children: "1. FEM\uC758 \uB4F1\uC7A5 \uBC30\uACBD\uACFC \uD544\uC694\uC131" }), _jsxs(Card, { size: "small", children: [_jsx(Paragraph, { children: "\uC2E4\uC0DD\uD65C\uC5D0\uC11C\uC758 \uB300\uBD80\uBD84\uC758 \uACF5\uD559 \uBB38\uC81C\uB294 \uC5F0\uC18D\uCCB4\uC758 \uAC70\uB3D9\uC744 \uAE30\uBC18\uC73C\uB85C \uBAA8\uB378\uB9C1\uB418\uBA70, \uC774\uB294 \uD3B8\uBBF8\uBD84 \uBC29\uC815\uC2DD\uC73C\uB85C \uAE30\uC220\uB429\uB2C8\uB2E4. \uD558\uC9C0\uB9CC \uB2E4\uC74C\uACFC \uAC19\uC740 \uBCF5\uC7A1\uC131 \uB54C\uBB38\uC5D0 \uD574\uC11D\uC801\uC73C\uB85C \uD480\uAE30 \uC5B4\uB835\uC2B5\uB2C8\uB2E4:" }), _jsx(List, { size: "small", bordered: true, dataSource: [
                                "복잡한 형상 (예: 곡면, 구멍, 경계) 및 재료 분포",
                                "하중의 비선형성 및 경계 조건의 다양성",
                                "시간에 따른 변화 및 다물리장 연성 (열+구조 등)"
                            ], renderItem: (item) => _jsx(List.Item, { children: item }) })] }), _jsx(Divider, { orientation: "left", children: "2. FEM\uC758 \uD575\uC2EC \uC544\uC774\uB514\uC5B4" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uAE30\uC874 \uD574\uC11D \uBC29\uC2DD", bordered: false, children: _jsx(List, { size: "small", dataSource: [
                                        "해석해 기반",
                                        "간단한 기하와 하중만 가능",
                                        "복잡성 증가 시 불가능"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "FEM\uC758 \uC811\uADFC \uBC29\uC2DD", bordered: false, children: _jsx(List, { size: "small", dataSource: [
                                        "도메인을 요소로 분할",
                                        "각 요소에서 근사 함수 사용",
                                        "전체 시스템으로 조립하여 근사 해 계산"
                                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }) }) })] }), _jsx(Divider, { orientation: "left", children: "3. \uC218\uD559\uC801 \uBC30\uACBD" }), _jsx(ModelFormulaBox, { title: "\uC5F0\uC18D\uCCB4 \uBB38\uC81C\uC758 \uC9C0\uBC30 \uBC29\uC815\uC2DD", description: "\uC77C\uBC18\uC801\uC778 \uAD6C\uC870 \uD574\uC11D \uBB38\uC81C\uB294 \uB2E4\uC74C\uACFC \uAC19\uC740 \uD3C9\uD615 \uBC29\uC815\uC2DD\uC73C\uB85C \uD45C\uD604\uB429\uB2C8\uB2E4:", formulas: ["-\\nabla \\cdot \\mathbf{\\sigma} = \\mathbf{b} \\quad \\text{in } \\Omega"] }), _jsxs(Paragraph, { children: ["\uC5EC\uAE30\uC11C:", _jsxs("ul", { children: [_jsxs("li", { children: [_jsx(MathJax, { inline: true, children: "\\( \\mathbf{\\sigma} \\)" }), ": \uC751\uB825 \uD150\uC11C"] }), _jsxs("li", { children: [_jsx(MathJax, { inline: true, children: "\\( \\mathbf{b} \\)" }), ": \uCCB4\uC801 \uD558\uC911 \uBCA1\uD130"] }), _jsxs("li", { children: [_jsx(MathJax, { inline: true, children: "\\( \\Omega \\)" }), ": \uD574\uC11D \uC601\uC5ED"] })] })] }), _jsx(Divider, { orientation: "left", children: "4. \uC57D\uD55C \uD615\uC2DD \uC720\uB3C4" }), _jsx(Paragraph, { children: "FEM\uC5D0\uC11C\uB294 \uC9C1\uC811\uC801\uC778 \uD574 \uB300\uC2E0 \uC57D\uD55C \uD615\uC2DD(Weak Form)\uC744 \uB3C4\uC785\uD558\uC5EC \uBB38\uC81C\uB97C \uC218\uCE58\uC801\uC73C\uB85C \uD480 \uC218 \uC788\uB3C4\uB85D \uD569\uB2C8\uB2E4." }), _jsx(ModelFormulaBox, { title: "\uAC00\uC911 \uC794\uCC28\uC2DD", description: "\uC2DC\uD5D8 \uD568\uC218 $w(x)$\uB97C \uACF1\uD558\uACE0 \uC801\uBD84\uD558\uC5EC \uBBF8\uBD84 \uCC28\uC218\uB97C \uB0AE\uCDA5\uB2C8\uB2E4.", formulas: ["\\int_\\Omega w (-\\nabla \\cdot \\mathbf{\\sigma}) d\\Omega = \\int_\\Omega w \\cdot \\mathbf{b} d\\Omega"] }), _jsx(ModelFormulaBox, { title: "\uBD80\uBD84\uC801\uBD84 \uD6C4 \uC57D\uD55C \uD615\uC2DD", description: "\uBD80\uBD84\uC801\uBD84\uC744 \uC218\uD589\uD558\uC5EC \uBBF8\uBD84 \uC5F0\uC0B0\uC744 \uC2DC\uD5D8 \uD568\uC218\uB85C \uC774\uB3D9\uC2DC\uD0B5\uB2C8\uB2E4.", formulas: ["\\int_\\Omega {\\epsilon}(w) : \\mathbf{\\sigma} \\ d\\Omega = \\int_\\Omega w \\cdot \\mathbf{b} \\ d\\Omega + \\int_{\\partial\\Omega} w \\cdot \\bar{\\mathbf{t}} \\ d\\Gamma"] }), _jsx(Divider, { orientation: "left", children: "5. FEM \uD574\uC11D \uC808\uCC28" }), _jsx(List, { size: "small", header: _jsx(Text, { strong: true, children: "FEM\uC740 \uB2E4\uC74C\uACFC \uAC19\uC740 \uC21C\uC11C\uB97C \uB530\uB985\uB2C8\uB2E4:" }), bordered: true, dataSource: [
                        "Mesh 생성: 도메인을 요소로 분할",
                        "Shape Function 정의: 각 요소 내 근사 함수 설정",
                        "요소 단위의 강성 행렬 구성",
                        "전역 행렬 조립",
                        "경계 조건 적용 및 해 계산"
                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }), _jsx(Divider, { orientation: "left", children: "6. \uAE30\uBCF8 \uD589\uB82C \uC2DC\uC2A4\uD15C" }), _jsx(ModelFormulaBox, { title: "\uC120\uD615 \uC2DC\uC2A4\uD15C", description: "\uC804\uC5ED \uC2DC\uC2A4\uD15C\uC740 \uB2E4\uC74C\uACFC \uAC19\uC740 \uD615\uD0DC\uB97C \uAC00\uC9D1\uB2C8\uB2E4:", formulas: ["\\mathbf{K} \\cdot \\mathbf{u} = \\mathbf{F}"] }), _jsx(Divider, { orientation: "left", children: "7. \uC7A5\uC810 \uBC0F \uB2E8\uC810" }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsx(Card, { title: "\uC7A5\uC810", bordered: false, children: _jsxs("ul", { children: [_jsx("li", { children: "\uBCF5\uC7A1\uD55C \uD615\uC0C1/\uC870\uAC74\uC5D0 \uC801\uC6A9 \uAC00\uB2A5" }), _jsx("li", { children: "\uB2E4\uC591\uD55C \uBB3C\uB9AC \uBD84\uC57C\uC5D0 \uD655\uC7A5 \uAC00\uB2A5" }), _jsx("li", { children: "\uACE0\uC815\uBC00 \uC218\uCE58 \uD574\uC11D \uAC00\uB2A5" })] }) }) }), _jsx(Col, { span: 12, children: _jsx(Card, { title: "\uB2E8\uC810", bordered: false, children: _jsxs("ul", { children: [_jsx("li", { children: "\uBA54\uC2DC \uD488\uC9C8\uC5D0 \uB530\uB77C \uD574 \uC815\uD655\uB3C4 \uC601\uD5A5" }), _jsx("li", { children: "\uBE44\uC120\uD615 \uBB38\uC81C \uC2DC \uACC4\uC0B0 \uC2DC\uAC04 \uC99D\uAC00" }), _jsx("li", { children: "\uC218\uB834\uC131 \uBB38\uC81C \uBC1C\uC0DD \uAC00\uB2A5" })] }) }) })] }), _jsx(Divider, { orientation: "left", children: "8. \uC801\uC6A9 \uBD84\uC57C" }), _jsx(Paragraph, { children: "FEM\uC740 \uB2E4\uC74C\uACFC \uAC19\uC740 \uB2E4\uC591\uD55C \uBD84\uC57C\uC5D0 \uC0AC\uC6A9\uB429\uB2C8\uB2E4:" }), _jsx(List, { size: "small", dataSource: [
                        "구조역학: 하중, 진동, 좌굴 등",
                        "열전달 해석",
                        "전자기장 분석",
                        "유체 흐름 및 다중 물리 연성"
                    ], renderItem: (item) => _jsx(List.Item, { children: item }) }), _jsx(Divider, { orientation: "left", children: "9. \uC694\uC57D \uBC0F \uB2E4\uC74C \uC7A5 \uC548\uB0B4" }), _jsx(Paragraph, { children: "\uBCF8 \uC7A5\uC5D0\uC11C\uB294 FEM\uC758 \uC774\uB860\uC801 \uB3D9\uAE30, \uC218\uD559\uC801 \uBAA8\uB378\uB9C1, \uC57D\uD55C \uD615\uC2DD \uC720\uB3C4, \uC808\uCC28 \uBC0F \uC751\uC6A9\uC5D0 \uB300\uD574 \uAC1C\uAD04\uC801\uC73C\uB85C \uC0B4\uD3B4\uBCF4\uC558\uC2B5\uB2C8\uB2E4. \uB2E4\uC74C \uC7A5\uC5D0\uC11C\uB294 \uAC00\uC7A5 \uB2E8\uC21C\uD55C \uD615\uD0DC\uC778 1\uCC28\uC6D0 \uC120\uD615 \uC694\uC18C\uB97C \uC0AC\uC6A9\uD558\uC5EC FEM \uD574\uC11D\uC744 \uC218\uCE58\uC801\uC73C\uB85C \uC218\uD589\uD558\uB294 \uACFC\uC815\uC744 \uBC30\uC6C1\uB2C8\uB2E4." })] }) }));
};
export default Chapter1;
