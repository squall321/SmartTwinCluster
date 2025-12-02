import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter8: React.FC = () => {
  return (
    <MathJaxContext
      version={3}
      config={{
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
      }}
    >
      <div className="space-y-6">
       
        <Paragraph>
          본 장에서는 시간에 따라 변화하는 동적 시스템의 해석을 위한 유한 요소 기법을 소개합니다. 질량, 감쇠, 외력 등을 고려하여 동적 거동을 수치적으로 해석하는 과정을 설명합니다.
        </Paragraph>

        <Divider orientation="left">1. 운동 방정식</Divider>
        <ModelFormulaBox
          title="운동 방정식의 기본 형태"
          description="질량 행렬, 감쇠 행렬, 강성 행렬, 외력을 포함하는 운동 방정식은 다음과 같습니다:"
          formulas={["\\mathbf{M} \\ddot{\\mathbf{u}} + \\mathbf{C} \\dot{\\mathbf{u}} + \\mathbf{K} \\mathbf{u} = \\mathbf{F}(t)"]}
        />

        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{M} \\)"}</MathJax>: 질량 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{C} \\)"}</MathJax>: 감쇠 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{K} \\)"}</MathJax>: 강성 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{F}(t) \\)"}</MathJax>: 시간에 따라 변하는 외력</li>
            <li><MathJax inline>{"\\( \\mathbf{u} \\)"}</MathJax>: 변위 벡터, <MathJax inline>{"\\( \\dot{\\mathbf{u}}, \\ddot{\\mathbf{u}} \\)"}</MathJax>: 속도 및 가속도</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">2. 시간 적분 기법</Divider>
        <ModelFormulaBox
          title="Newmark 방법의 기본식"
          description="Newmark-beta 방법은 다음 식을 기반으로 시간 적분을 수행합니다."
          formulas={["\\mathbf{u}_{n+1} = \\mathbf{u}_n + \\Delta t \\dot{\\mathbf{u}}_n + \\frac{\\Delta t^2}{2}[(1-2\\beta) \\ddot{\\mathbf{u}}_n + 2\\beta \\ddot{\\mathbf{u}}_{n+1}]"]}
        />

        <Paragraph>
          통상적으로 $\beta = 0.25$, $\gamma = 0.5$를 사용하면 무조건 안정 조건을 만족합니다 (이른바 average acceleration method).
        </Paragraph>

        <Divider orientation="left">3. 모드 해석과 응답 해석</Divider>
        <ModelFormulaBox
          title="자유 진동 해석"
          description="고유값 문제로 변환하여 자유 진동 모드를 계산할 수 있습니다."
          formulas={["\\mathbf{K} \\phi_i = \\omega_i^2 \\mathbf{M} \\phi_i"]}
        />

        <Paragraph>
          고유 진동수 $\omega_i$, 모드형상 $\phi_i$를 통해 시스템의 진동 특성을 파악할 수 있으며, 모달 해석 기반으로 응답 해석을 효율화할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">4. 감쇠 모델</Divider>
        <ModelFormulaBox
          title="Rayleigh 감쇠"
          description="다음과 같이 질량 및 강성 비례 감쇠 모델을 사용할 수 있습니다."
          formulas={["\\mathbf{C} = \\alpha \\mathbf{M} + \\beta \\mathbf{K}"]}
        />

        <Paragraph>
          상수 $\alpha$, $\beta$는 모드 감쇠 비율로부터 추정 가능하며, 특정 진동수 범위에서의 감쇠 제어에 유리합니다.
        </Paragraph>

        <Divider orientation="left">5. 요약</Divider>
        <Paragraph>
          동적 해석은 정적 해석보다 복잡하지만, 구조물의 진동 응답, 지진 하중, 충격 등 다양한 실제 조건을 반영하기 위해 필수적입니다. 시간 적분 기법과 모달 해석, 감쇠 모델을 적절히 조합하면 효과적인 해석이 가능합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter8;