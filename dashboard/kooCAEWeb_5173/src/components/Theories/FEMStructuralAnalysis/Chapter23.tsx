import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter23: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 <Text strong>확률론적 유한 요소 해석(Stochastic FEM)</Text>을 소개합니다.
          재료 특성, 경계 조건, 하중 등 입력의 불확실성이 구조 해석 결과에 미치는 영향을 정량화하고, 이를 통해 <Text strong>신뢰성 있는 설계</Text>를 수행할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">1. 불확실성 모델링</Divider>
        <Paragraph>
          입력 변수는 확률 변수로 모델링되며, 대표적인 불확실성 원천은 다음과 같습니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "재료 물성의 통계적 분포 (예: 탄성계수의 정규 분포)",
            "하중 조건의 변동성",
            "기하학적 오차와 생산 편차"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">2. 몬테카를로 시뮬레이션</Divider>
        <Paragraph>
          가장 널리 사용되는 방법은 <Text strong>몬테카를로 시뮬레이션</Text>으로, 확률 변수의 표본을 다수 생성하고 각 경우에 대해 FEM 해석을 반복 수행합니다.
        </Paragraph>

        <ModelFormulaBox
          title="통계적 기대값과 분산"
          description={
            <>출력 변수 <MathJax inline>{"\( u \)"}</MathJax>의 기대값과 분산을 샘플 평균으로 추정:</>
          }
          formulas={[
            "\\mathbb{E}[u] \\approx \\dfrac{1}{N} \\sum_{i=1}^N u^{(i)}",
            "\\text{Var}[u] \\approx \\dfrac{1}{N - 1} \\sum_{i=1}^N \\left( u^{(i)} - \\mathbb{E}[u] \\right)^2"
          ]}
        />

        <Divider orientation="left">3. Polynomial Chaos Expansion (PCE)</Divider>
        <Paragraph>
          <Text strong>PCE</Text>는 출력 변수를 직교 다항식 기반으로 확률 변수에 대해 전개하는 방법으로, 보다 적은 해석 횟수로 고차 통계량을 얻을 수 있습니다.
        </Paragraph>

        <ModelFormulaBox
          title="Polynomial Chaos 전개"
          description={
            <>출력 변수 <MathJax inline>{"\( u(\\xi) \)"}</MathJax>를 확률 변수 <MathJax inline>{"\( \\xi \)"}</MathJax>에 대해 직교 다항식으로 전개:</>
          }
          formulas={["u(\\xi) = \\sum_{k=0}^{P} c_k \\Psi_k(\\xi)"]}
        />

        <Divider orientation="left">4. 민감도 및 신뢰성 해석</Divider>
        <Paragraph>
          각 입력 변수에 따른 출력 민감도를 정량화하는 <Text strong>민감도 해석</Text>과,
          허용 한계를 초과할 확률을 계산하는 <Text strong>신뢰성 해석</Text>은 엔지니어링 설계에 필수적입니다.
        </Paragraph>

        <ModelFormulaBox
          title="신뢰성 지수 (Reliability Index)"
          description={
            <>1차 신뢰성 방법 (FORM)에서, 실패 확률은 신뢰성 지수 <MathJax inline>{"\( \beta \)"}</MathJax>로 근사됩니다:</>
          }
          formulas={["P_f \\approx \\Phi(-\\beta)"]}
        />

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 유한 요소 해석에서 불확실성을 정량화하는 다양한 방법을 다루었습니다. 몬테카를로 기법, PCE, 민감도 분석, 신뢰성 지수 등은 복잡한 공학 시스템의 설계 안정성과 신뢰도를 향상시키는 핵심 도구입니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter23;