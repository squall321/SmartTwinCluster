import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter5: React.FC = () => {
  return (
    <MathJaxContext
      version={3}
      config={{
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
      }}
    >
      <div className="space-y-6">
        
        <Paragraph>
          본 장에서는 유한 요소 해석에서 자주 사용되는 수치적분(Numerical Integration)에 대해 설명합니다. Gaussian 적분을 중심으로, 요소 강성 행렬 계산 및 요소 내 적분 계산 시의 적용 방법을 다룹니다.
        </Paragraph>

        <Divider orientation="left">1. 수치 적분의 필요성</Divider>
        <Paragraph>
          유한 요소 해석에서 적분은 요소 강성 행렬 및 하중 벡터 계산 시 필수적으로 수행됩니다. 복잡한 shape function과 기하학적 요소를 고려할 때, 해석적 적분은 현실적으로 불가능하므로 수치적분을 활용합니다.
        </Paragraph>

        <Divider orientation="left">2. Gaussian 적분 (Gauss Quadrature)</Divider>
        <ModelFormulaBox
          title="1D Gauss 적분 일반식"
          description="1차원 구간 [-1, 1]에서 함수 $f(\xi)$의 적분은 다음과 같이 근사됩니다:"
          formulas={["\\int_{-1}^{1} f(\\xi) d\\xi \\approx \\sum_{i=1}^n w_i f(\\xi_i)"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\xi_i \\)"}</MathJax>: 적분점 (Gauss point)</li>
            <li><MathJax inline>{"\\( w_i \\)"}</MathJax>: 해당 적분점의 가중치</li>
            <li><MathJax inline>{"\\( n \\)"}</MathJax>: 사용할 적분점의 수 (정확도 향상 가능)</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">3. 2D 요소의 적분</Divider>
        <ModelFormulaBox
          title="사각형 요소에서의 2D Gauss 적분"
          description="자연 좌표계 $(\xi, \eta)$를 사용하는 2D 적분은 다음과 같이 근사됩니다:"
          formulas={["\\int_{-1}^{1} \\int_{-1}^{1} f(\\xi, \\eta) d\\xi d\\eta \\approx \\sum_{i=1}^n \\sum_{j=1}^n w_i w_j f(\\xi_i, \\eta_j)"]}
        />

        <Divider orientation="left">4. 요소 강성 행렬 계산 예시</Divider>
        <ModelFormulaBox
          title="등방성 선형 탄성체에서의 요소 강성 행렬"
          description="다음과 같이 수치 적분으로 계산됩니다:"
          formulas={["\\mathbf{k}^{(e)} = \\sum_{i=1}^n w_i \\cdot |J(\\xi_i)| \\cdot \\mathbf{B}^T(\\xi_i) \\mathbf{D} \\mathbf{B}(\\xi_i)"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li>$J(\xi_i)$: 자코비안 행렬의 행렬식</li>
            <li><MathJax inline>{"\\( \\mathbf{B}(\\xi_i) \\)"}</MathJax>: 변형률-변위 행렬 (적분점에서 평가)</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">5. 삼각형 요소에서의 적분</Divider>
        <Paragraph>
          삼각형 요소에서는 적분 영역이 단순 정사각형이 아니므로, 적절한 barycentric 적분점과 가중치를 사용한 삼각형 전용 Gauss 적분 규칙을 사용합니다. 대표적으로 1, 3, 7점 규칙 등이 있습니다.
        </Paragraph>

        <Divider orientation="left">6. 주의사항</Divider>
        <List
          size="small"
          header={<Text strong>정확한 수치 적분을 위한 팁</Text>}
          dataSource={[
            "자코비안 행렬의 부호와 크기를 정확히 계산해야 함",
            "고차 요소에서는 더 많은 적분점이 필요",
            "적분점에서 shape function, 미분값, B 행렬 등을 모두 평가"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">7. 요약</Divider>
        <Paragraph>
          본 장에서는 유한 요소 해석에서의 수치 적분 기법, 특히 Gaussian 적분법을 활용하여 요소 강성 행렬과 하중 벡터를 계산하는 과정을 설명했습니다. 다음 장에서는 시간에 따른 해석을 위한 동적 문제로 확장합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter5;
