import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter22: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 비선형 재료 모델 중 하나인 <Text strong>소성(Plasticity)</Text>과 <Text strong>손상(Damage)</Text> 모델을 다룹니다.
          외력에 의해 항복 후에도 변형이 누적되거나 재료 강도가 저하되는 거동은 일반적인 선형 탄성으로 설명할 수 없으며, 별도의 이론 및 수치 알고리즘이 필요합니다.
        </Paragraph>

        <Divider orientation="left">1. J2 소성 이론</Divider>
        <Paragraph>
          등방성 소성 재료의 대표적 모델인 <Text strong>J2 흐름 규칙(J2 flow rule)</Text>은 등방성 항복 조건과 연성 재료의 소성 변형 거동을 설명합니다.
          소성 포텐셜 함수 기반의 유도와 함께, 등방/운동 경화 법칙이 적용됩니다.
        </Paragraph>

        <ModelFormulaBox
          title="J2 흐름 규칙 (Prandtl-Reuss)"
          description={
            <>
              Von Mises 항복 조건을 기반으로 한 등방성 소성 모델에서, 
              소성 변형률 속도 <MathJax inline>{"\\( \\dot{\\varepsilon}^p \\)"}</MathJax>는 소성 포텐셜의 그래디언트 방향으로 발생합니다.
            </>
          }
          formulas={["\\dot{\\varepsilon}^p = \\dot{\\lambda} \\dfrac{3}{2} \\dfrac{s}{\\| s \\|}"]}
        />

        <Divider orientation="left">2. 경화 모델</Divider>
        <Paragraph>
          항복 곡선이 진화하는 방식에 따라 <Text strong>등방 경화</Text>와 <Text strong>운동 경화</Text>로 나뉩니다. 실제 재료는 두 모델의 조합으로 표현되며,
          <Text strong>혼합 경화 모델</Text>도 존재합니다.
        </Paragraph>

        <ModelFormulaBox
          title="Isotropic + Kinematic Hardening"
          description={
            <>
              소성 후 응력 증가와 항복 표면의 이동을 동시에 고려한 모델로, 
              총 변형률에서 소성 변형률을 제거하여 탄성 응력을 계산합니다.
            </>
          }
          formulas={["\\sigma = \\mathbb{C} : (\\varepsilon - \\varepsilon^p)"]}
        />

        <Divider orientation="left">3. UMAT 및 사용자 정의 재료 모델</Divider>
        <Paragraph>
          <Text strong>UMAT</Text>은 상용 해석기에서 사용자 정의 재료 모델을 구현하기 위한 인터페이스입니다.
          사용자 정의 소성 모델을 UMAT 형식으로 구현하면 다양한 소성/손상 모델을 직접 적용할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">4. 손상 역학과 파괴</Divider>
        <Paragraph>
          <Text strong>손상 이론</Text>은 재료 내부의 미세 균열, 공극 등에 의해 거시적인 강도가 감소하는 현상을 모델링합니다.
          <Text strong>Softening</Text> 현상은 수치적으로 해의 <em>localization</em>을 야기하므로 <Text strong>정규화 기법(regularization)</Text>이 필요합니다.
        </Paragraph>

        <ModelFormulaBox
          title="손상 변수와 응력"
          description={
            <>
              스칼라 손상 변수 <MathJax inline>{"\\( D \\in [0, 1] \\)"}</MathJax>를 통해, 
              유효 응력은 탄성 응력에서 손상 효과를 반영하여 계산됩니다.
            </>
          }
          formulas={["\\sigma = (1 - D) \\mathbb{C} : \\varepsilon^e"]}
        />

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 J2 소성 모델, 경화 모델, UMAT 사용자 구현, 손상 역학 및 해의 국소화 문제에 대해 다루었습니다.
          이러한 모델은 금속 재료의 항복 및 파괴를 수치적으로 예측하는 데 필수적입니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter22;   