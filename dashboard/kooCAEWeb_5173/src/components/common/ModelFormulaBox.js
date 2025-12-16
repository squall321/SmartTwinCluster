import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Card, Typography } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
const { Paragraph } = Typography;
const ModelFormulaBox = ({ title, description, formulas }) => (_jsx(MathJaxContext, { version: 3, config: {
        tex: {
            inlineMath: [["$", "$"], ["\\(", "\\)"]],
            displayMath: [["$$", "$$"], ["\\[", "\\]"]],
        },
    }, children: _jsxs(Card, { size: "small", title: title, style: { marginBottom: 16 }, children: [_jsx(MathJax, { dynamic: true, children: _jsx(Paragraph, { children: description }) }), formulas.map((formula, i) => (_jsx(Paragraph, { children: _jsx(MathJax, { dynamic: true, inline: false, children: `\\[ ${formula} \\]` }) }, i)))] }) }));
export default ModelFormulaBox;
