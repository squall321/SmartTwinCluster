import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter13: React.FC = () => {
  return (
    <MathJaxContext
      version={3}
      config={{
        tex: {
          packages: { '[+]': ['ams', 'bm'] },
          inlineMath: [["$", "$"], ["\\(", "\\)"]],
          displayMath: [["$$", "$$"], ["\\[", "\\]"]],
        },
      }}
    >
      <div className="space-y-6">
        <Paragraph>
          본 장에서는 전통적인 유한 요소 방법이 가지는 수치적 불안정성과 정확도 저하 문제를 해결하기 위한 고급 기법들을 소개합니다. 대표적으로는 Locking 현상을 방지하기 위한 혼합 형식(Mixed Formulation), Petrov-Galerkin 접근, SUPG(Stabilized), Bubble Function 기반의 보완 기법 등이 있습니다.
        </Paragraph>

        <Divider orientation="left">1. Locking 현상</Divider>
        <Paragraph>
          Locking은 요소의 자유도가 부족하거나 제한되어 발생하는 수치적 경직 현상입니다. 대표적인 예는 낮은 차수 요소를 사용한 거의 비압축성 물질 해석이나 얇은 구조물에서 발생하는 전단 락킹(shear locking)입니다.
        </Paragraph>

        <ModelFormulaBox
          title="압축성 락킹 문제"
          description="Poisson 비가 0.5에 가까울수록 락킹 현상이 심해짐"
          formulas={["\\nabla \\cdot \\mathbf{u} = 0 \\quad \\text{(비압축성 조건)}"]}
        />

        <Divider orientation="left">2. Mixed Formulation</Divider>
        <Paragraph>
          혼합 형식은 기본 해(<MathJax inline>{"\\( u \\)"}</MathJax>) 외에 추가적인 변수를 도입하여 문제를 해결하는 방법입니다. 예를 들어 유체 문제에서는 속도(<MathJax inline>{"\\( \\mathbf{u} \\)"}</MathJax>)와 압력(<MathJax inline>{"\\( p \\)"}</MathJax>)을 동시에 푸는 mixed formulation을 사용합니다.
        </Paragraph>

        <ModelFormulaBox
          title="Stokes 문제의 혼합 형식"
          description="비압축성 유체에 대해 속도와 압력을 동시에 해석"
          formulas={["-\\mu \\nabla^2 \\mathbf{u} + \\nabla p = \\mathbf{f}", "\\nabla \\cdot \\mathbf{u} = 0"]}
        />

        <Paragraph>
          이러한 문제는 안정성을 확보하기 위해 <Text strong>LBB 조건</Text>을 만족하는 요소 조합이 필요합니다 (예: P2-P1 요소).
        </Paragraph>

        <Divider orientation="left">3. Petrov-Galerkin 및 SUPG</Divider>
        <Paragraph>
          Petrov-Galerkin 방법은 시험 함수와 보간 함수의 공간을 다르게 하여 수치적 안정성을 개선합니다. 이 중 SUPG(Streamline-Upwind Petrov-Galerkin)는 대류 지배 문제에서 특히 효과적입니다.
        </Paragraph>

        <ModelFormulaBox
          title="SUPG 안정화 용어"
          description="기존 약한 형식에 추가 항을 더하여 수치적 안정성을 확보"
          formulas={["\\int_\\Omega \\tau (\\mathbf{v} \\cdot \\nabla w)(\\mathbf{v} \\cdot \\nabla u) \\ d\\Omega"]}
        />

        <Paragraph>
          여기서 <MathJax inline>{"\\( \\tau \\)"}</MathJax>는 문제의 특성에 따라 정해지는 안정화 파라미터이며, 위 수식은 대류 방향으로 upwind 효과를 주는 역할을 합니다.
        </Paragraph>

        <Divider orientation="left">4. Bubble Function</Divider>
        <Paragraph>
          Bubble function은 요소 내부에만 정의된 추가 shape function으로, 특정한 안정화 효과를 줄 수 있습니다. 특히 압력 안정화 및 혼합 형식의 수렴성 향상에 유리합니다.
        </Paragraph>

        <ModelFormulaBox
          title="Bubble function 예시 (삼각형 요소)"
          description="중심 노드에 해당하는 함수: b(x,y) = 27 \\xi \\eta (1-\\xi-\\eta)"
          formulas={["N_b(\\xi, \\eta) = 27 \\xi \\eta (1 - \\xi - \\eta)"]}
        />
        <Paragraph>
          이 함수는 요소 내부에서만 활성화되어 전역 자유도에는 영향을 주지 않지만, 수렴성 및 안정성을 향상시킵니다.
        </Paragraph>

        <Divider orientation="left">5. 요약</Divider>
        <Paragraph>
          Stabilization 기법은 수치적 불안정성, 비압축성 조건에서의 압력-속도 적합 문제, 전단 락킹 등 다양한 FEM의 한계를 극복하기 위한 핵심 기법입니다. 본 장에서 소개한 SUPG, Bubble Function, 그리고 Mixed Formulation은 다양한 실제 문제에서 필수적인 해법입니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter13;
