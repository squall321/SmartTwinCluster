import React from "react";
import { Typography, Divider } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter16: React.FC = () => {
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

        <Divider orientation="left">1. 다중 스케일 문제의 필요성</Divider>
        <Paragraph>
          이 장에서는 다양한 스케일을 갖는 물리적 문제를 유한 요소 해석에 효과적으로 통합하기 위한 다중 스케일 기법과 동질화(Homogenization) 방법론을 다룹니다. 미시구조의 복잡성을 고려하면서도 계산 효율성을 확보할 수 있는 중요한 접근 방식입니다.
        </Paragraph>

        <Paragraph>
          복합재료, 다층 구조, 결정 미세조직 등에서는 미시 스케일의 특성이 거시적 물성에 직접 영향을 미칩니다. 하지만 전체 구조를 미시 스케일까지 정밀하게 해석하는 것은 계산 자원이 과도하게 요구되므로, 다중 스케일 접근이 필요합니다.
        </Paragraph>

        <Divider orientation="left">2. Representative Volume Element (RVE)</Divider>
        <Paragraph>
          RVE는 전체 재료의 평균적인 특성을 대표할 수 있는 최소 단위로, 미시 해석에서 사용됩니다. RVE 해석을 통해 얻은 유효 물성은 거시 해석에 적용됩니다.
        </Paragraph>

        <ModelFormulaBox
            title="동질화 기본 식"
            description={
                <>
                미시 구조 해석을 통해 계산된 평균 응력과 변형률을 사용하여 유효 재료 특성을 정의합니다:{" "}
                <MathJax inline>{"\\( \\bar{\\mathbf{\\sigma}} = \\mathbb{C}^{\\text{eff}} : \\bar{\\mathbf{\\varepsilon}} \\)"}</MathJax>
                </>
            }
            formulas={["\\bar{\\mathbf{\\sigma}} = \\mathbb{C}^{\\text{eff}} : \\bar{\\mathbf{\\varepsilon}}"]}
            />

        <Divider orientation="left">3. FE<sup>2</sup> 방법</Divider>
        <Paragraph>
          FE<sup>2</sup>는 Finite Element squared 방법으로, 각 거시적 적분점마다 독립적인 미시 모델(FEM)을 할당하여 동질화 물성을 계산하는 multiscale 방식입니다.
        </Paragraph>

        <ModelFormulaBox
        title="FE² 개념적 흐름"
        description={
            <>
            거시 해석의 적분점에서{" "}
            <MathJax inline>{"\\( \\bar{\\mathbf{\\varepsilon}} \\)"}</MathJax>
            을 입력으로 RVE 해석을 수행하고, 산출된{" "}
            <MathJax inline>{"\\( \\bar{\\mathbf{\\sigma}} \\)"}</MathJax>
            를 거시 해석에 전달
            </>
        }
        formulas={[]}
        />


        <Divider orientation="left">4. 비선형 다중 스케일</Divider>
        <Paragraph>
          다중 스케일 해석은 선형 거동뿐 아니라 소성, 크리프, 손상 등 비선형 물성에도 확장됩니다. 이때 RVE는 점탄성 또는 손상 모델을 포함할 수 있으며, 시간 이력 및 내부 상태 변수의 관리가 중요합니다.
        </Paragraph>

        <Divider orientation="left">5. Scale Transition 방법</Divider>
        <Paragraph>
          미시-거시 간 변환 방법으로 평균화(Hill-Mandel 조건), 연속 경계조건(Periodic BC), Dirichlet/Neumann 혼합 경계조건 등이 사용됩니다.
        </Paragraph>

        <ModelFormulaBox
          title="Hill-Mandel 조건"
          description="거시적 에너지 밀도와 미시적 에너지 밀도는 같아야 함을 의미합니다:"
          formulas={["\\bar{\\boldsymbol{\\sigma}} : \\bar{\\boldsymbol{\\varepsilon}} = \\frac{1}{|\Omega|} \\int_\\Omega \\boldsymbol{\\sigma}(x) : \\boldsymbol{\\varepsilon}(x) \\, dx"]}
        />

        <Divider orientation="left">6. 요약</Divider>
        <Paragraph>
          Multi-scale 해석은 미세 구조의 물성을 정밀하게 반영하면서도 전체 구조에 대한 효율적인 해석을 가능하게 하는 고급 FEM 기법입니다. RVE 기반 동질화, FE<sup>2</sup> 방식, 다양한 경계조건 모델링이 실제 재료 시뮬레이션에서 활용되고 있습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter16;