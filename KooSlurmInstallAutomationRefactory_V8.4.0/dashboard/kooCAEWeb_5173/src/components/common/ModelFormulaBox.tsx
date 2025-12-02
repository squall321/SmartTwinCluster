import React from "react";
import { Card, Typography } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Paragraph } = Typography;

interface Props {
  title: string;
  description: string | React.ReactNode;
  formulas: string[];
}

const ModelFormulaBox: React.FC<Props> = ({ title, description, formulas }) => (
  <MathJaxContext
    version={3}
    config={{
      tex: {
        inlineMath: [["$", "$"], ["\\(", "\\)"]],
        displayMath: [["$$", "$$"], ["\\[", "\\]"]],
      },
    }}
  >
    <Card size="small" title={title} style={{ marginBottom: 16 }}>
      {/* 수식 포함 설명도 MathJax로 렌더링 */}
      <MathJax dynamic>
        <Paragraph>{description}</Paragraph>
      </MathJax>
      {formulas.map((formula, i) => (
        <Paragraph key={i}>
          <MathJax dynamic inline={false}>{`\\[ ${formula} \\]`}</MathJax>
        </Paragraph>
      ))}
    </Card>
  </MathJaxContext>
);

export default ModelFormulaBox;
