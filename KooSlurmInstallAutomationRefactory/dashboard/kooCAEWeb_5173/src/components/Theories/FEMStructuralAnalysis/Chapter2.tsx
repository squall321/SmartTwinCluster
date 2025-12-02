import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter2: React.FC = () => {
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
          본 장에서는 1차원 연속체(막대 또는 열전도체)를 대상으로 유한 요소법을 적용하여 근사 해를 구하는 전 과정을 설명합니다. 특히, 약한 형식의 유도, shape function의 정의, 요소 강성 행렬 구성, 전역 시스템 조립, 경계 조건 적용까지의 수치적 흐름을 다룹니다.
        </Paragraph>

        <Divider orientation="left">1. 지배 방정식 정의</Divider>
        <ModelFormulaBox
          title="1차원 연속체의 지배 방정식"
          description="막대의 정역학 평형 혹은 1차원 열전도 문제는 다음의 2차 미분 방정식으로 표현됩니다:"
          formulas={["-\\frac{d}{dx}(AE \\frac{du}{dx}) = f(x)"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( u(x) \\)"}</MathJax>: 변위 또는 온도</li>
            <li><MathJax inline>{"\\( A(x) \\)"}</MathJax>: 단면적</li>
            <li><MathJax inline>{"\\( E(x) \\)"}</MathJax>: 탄성 계수 또는 열전도율</li>
            <li><MathJax inline>{"\\( f(x) \\)"}</MathJax>: 체적 하중 또는 열원</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">2. 약한 형식 유도</Divider>
        <ModelFormulaBox
          title="가중 잔차식"
          description="시험 함수 $w(x)$를 곱한 뒤 전체 영역에 대해 적분하여 다음과 같이 작성됩니다:"
          formulas={["\\int_\\Omega w(x) \\left[-\\frac{d}{dx}(AE \\frac{du}{dx})\\right] dx = \\int_\\Omega w(x) f(x) dx"]}
        />

        <ModelFormulaBox
          title="부분적분을 통한 약한 형식"
          description="부분적분을 통해 미분 연산을 시험 함수에 이전시키면, 다음과 같은 약한 형식을 얻게 됩니다:"
          formulas={["\\int_\\Omega AE \\frac{dw}{dx} \\cdot \\frac{du}{dx} dx = \\int_\\Omega w(x) f(x) dx + \\left[ w AE \\frac{du}{dx} \\right]_\\partial\\Omega"]}
        />

        <Divider orientation="left">3. 요소 내 유한 요소 근사</Divider>
        <ModelFormulaBox
          title="Shape Function을 통한 근사"
          description="요소 내부에서는 선형 shape function $N_1(x), N_2(x)$를 사용하여 $u(x)$와 $w(x)$를 다음과 같이 근사합니다:"
          formulas={["u(x) = N_1(x) u_1 + N_2(x) u_2", "w(x) = N_1(x) w_1 + N_2(x) w_2"]}
        />

        <Divider orientation="left">4. 요소 강성 행렬 도출</Divider>
        <ModelFormulaBox
          title="선형 요소의 강성 행렬"
          description="선형 요소에서 미분은 상수가 되며, 정적분을 통해 다음 행렬이 도출됩니다:"
          formulas={["k^{(e)} = \\frac{AE}{L} \\begin{bmatrix} 1 & -1 \\ \\ -1 & 1 \\end{bmatrix}"]}
        />

        <Divider orientation="left">5. 전역 시스템 조립</Divider>
        <Paragraph>
          각 요소에서 얻은 강성 행렬과 하중 벡터를 전체 시스템의 자유도에 맞추어 조립하면, 다음과 같은 전역 선형 시스템을 얻게 됩니다:
        </Paragraph>
        <ModelFormulaBox
          title="전역 선형 시스템"
          description="조립 후 전체 시스템은 다음과 같은 행렬 방정식 형태를 가집니다:"
          formulas={["\\mathbf{K} \\cdot \\mathbf{u} = \\mathbf{F}"]}
        />

        <Divider orientation="left">6. 경계 조건 적용 및 해</Divider>
        <Paragraph>
          경계 조건은 두 가지로 분류됩니다:
          <ul>
            <li><Text strong>Dirichlet 조건:</Text> 특정 노드에 대한 <MathJax inline>{"\\( u(x) \\)"}</MathJax> 값을 지정 → <MathJax inline>{"\\( \\mathbf{u} \\)"}</MathJax>에 직접 반영</li>
            <li><Text strong>Neumann 조건:</Text> <MathJax inline>{"\\( \\left. -AE \\frac{du}{dx} \\right| \\)"}</MathJax> 값을 통해 하중 벡터 <MathJax inline>{"\\( \\mathbf{F} \\)"}</MathJax>에 간접 반영</li>
          </ul>
        </Paragraph>
        <Paragraph>
          Dirichlet 조건은 시스템의 행과 열을 제거하거나 계수를 수정하는 방식으로 적용되며, Neumann 조건은 주어진 경계 하중을 <MathJax inline>{"\\( \\mathbf{F} \\)"}</MathJax>에 추가합니다.
        </Paragraph>

        <Divider orientation="left">7. 예제: 균일 하중을 받는 막대</Divider>
        <Paragraph>
          길이 <MathJax inline>{"\\( L=1 \\)"}</MathJax>, 단면적 <MathJax inline>{"\\( A=1 \\)"}</MathJax>, 탄성계수 <MathJax inline>{"\\( E=1 \\)"}</MathJax>, 균일 하중 <MathJax inline>{"\\( f(x)=1 \\)"}</MathJax>인 막대를 2개 요소로 분할하여 FEM으로 근사해를 구하는 예제를 생각해봅니다.
        </Paragraph>
        <ModelFormulaBox
          title="예제의 요소 강성 행렬 및 하중"
          description="각 요소의 강성 행렬은 위의 공식을 이용하여 구하고, 하중 벡터는 선형 shape function에 기반하여 적분하여 구성합니다."
          formulas={["k^{(e)} = \\begin{bmatrix} 1 & -1 \\ \\ -1 & 1 \\end{bmatrix}, \\quad f^{(e)} = \\begin{bmatrix} 0.5 \\ \\ 0.5 \\end{bmatrix}"]}
        />

        <Divider orientation="left">8. 요약</Divider>
        <Paragraph>
          본 장에서는 1차원 연속체에 FEM을 적용하는 전체 절차를 다루었습니다. 약한 형식의 유도, shape function을 활용한 근사, 요소 및 전역 시스템 조립, 경계 조건 처리 등 FEM의 핵심 흐름을 실제 수식 기반으로 설명했습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter2;
