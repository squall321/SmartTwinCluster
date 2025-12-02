import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter19: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 소성 및 비선형 거동 이전에 나타나는 <Text strong>기하학적 비선형성</Text>에 대해 다룹니다. 변형이 작지 않은 경우에는 선형 가정이 성립하지 않으며, 변형률 및 응력 정의가 수정되어야 합니다. 본 장에서는 Green-Lagrange 변형률, 2차 Piola-Kirchhoff 응력, 총괄 라그랑지(Total Lagrangian) 및 업데이트 라그랑지(Updated Lagrangian) 형식, 회전 처리 기법, 쉘/빔의 대변형 해석 등을 소개합니다.
        </Paragraph>

        <Divider orientation="left">1. 변형률과 응력 텐서</Divider>
        <Paragraph>
          <Text strong>Green-Lagrange 변형률</Text>은 큰 변형을 고려하는 2차 텐서이며, 초기 구성에서 정의됩니다. 이에 대응되는 응력은 <Text strong>2차 Piola-Kirchhoff 응력</Text>입니다.
        </Paragraph>

        <ModelFormulaBox
          title="Green-Lagrange 변형률"
          description={
            <>
              초기 좌표계에서 정의된 비선형 변형률 텐서로, 변형 그라디언트
              <MathJax inline>{"\\( \\mathbf{F} \\)"}</MathJax>를 기반으로 계산됩니다. 이 변형률은
              선형 구성에서는 나타나지 않는 2차 항을 포함하므로, 큰 변형 문제에서 필수적입니다.
            </>
          }
          formulas={["\\mathbf{E} = \\frac{1}{2} (\\mathbf{F}^T \\mathbf{F} - \\mathbf{I})"]}
        />

        <ModelFormulaBox
          title="2차 Piola-Kirchhoff 응력"
          description={
            <>
              Lagrangian 구성에서 사용하는 에너지 기반 응력으로,
              변형 에너지 밀도 함수 <MathJax inline>{"\\( \\Psi \\)"}</MathJax>의 변형률에 대한 편미분으로 정의됩니다.
              이 응력은 초기 형상에서 정의되며, Green-Lagrange 변형률과 에너지 일관성이 있습니다.
            </>
          }
          formulas={["\\mathbf{S} = \\frac{\\partial \\Psi}{\\partial \\mathbf{E}}"]}
        />

        <Divider orientation="left">2. Total vs. Updated Lagrangian</Divider>
        <Paragraph>
          <Text strong>Total Lagrangian</Text> 형식은 모든 물리량을 초기 형상 기준으로 표현하며,
          <Text strong>Updated Lagrangian</Text> 형식은 직전 단계의 변형 형상을 기준으로 표현합니다.
          두 방법 모두 비선형 해석에서 사용되며 선택은 문제의 특성과 수렴 안정성에 따라 달라집니다.
        </Paragraph>

        <Divider orientation="left">3. 회전 처리 및 Corotational 방법</Divider>
        <Paragraph>
          큰 회전이 존재하지만 변형은 작을 경우, <Text strong>Corotational 방법</Text>이 유용합니다.
          요소의 강체 회전을 분리하여 계산 효율성과 정확도를 확보할 수 있습니다.
        </Paragraph>

        <ModelFormulaBox
          title="Deformation Gradient 분해"
          description={
            <>
              변형 그라디언트 <MathJax inline>{"\\( \\mathbf{F} \\)"}</MathJax>는
              정규 직교 회전 텐서 <MathJax inline>{"\\( \\mathbf{R} \\)"}</MathJax>와
              대칭 신장 텐서 <MathJax inline>{"\\( \\mathbf{U} \\)"}</MathJax>의 곱으로 분해됩니다. 이 과정을
              <Text strong>Polar Decomposition</Text>이라 하며, 회전 성분과 순수 변형을 분리하는 데 사용됩니다.
            </>
          }
          formulas={["\\mathbf{F} = \\mathbf{R} \\mathbf{U}"]}
        />

        <Divider orientation="left">4. 쉘/빔의 대변형 FEM</Divider>
        <Paragraph>
          쉘 및 빔 요소에서도 대변형을 고려해야 하는 경우가 많으며, 이때는 회전 및 곡률 효과까지 고려한
          <Text strong>대변형 쉘 이론</Text>이 필요합니다. 일반적인 선형 쉘 이론은 작은 회전/변형 가정에 기반하므로,
          각도 변화가 큰 문제에서는 적절한 확장이 필요합니다.
        </Paragraph>

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 기하학적 비선형성의 주요 구성 요소인 Green-Lagrange 변형률,
          2차 Piola-Kirchhoff 응력, 라그랑지 형식의 차이점, corotational 처리 기법,
          대변형 쉘 및 빔 해석을 다루었습니다. 이러한 이론은 복잡한 구조물의 대변형 해석에서 필수적입니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter19;
