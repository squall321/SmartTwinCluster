import React from "react";
import { Typography, Divider } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter17: React.FC = () => {
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
          이 장에서는 유한 요소 해석에서의 오차 추정 및 적응형 메시 정련(adaptive mesh refinement) 기법을 다룹니다. 수치해의 신뢰도를 확보하고 자원 효율적인 해석을 위해 필수적인 주제입니다.
        </Paragraph>

        <Divider orientation="left">1. A Posteriori Error Estimation</Divider>
        <Paragraph>
          <Text strong>A posteriori</Text> 오차 추정은 해석 후 계산된 해를 기반으로 오차를 추정하는 기법입니다. 일반적으로 요소별 오차 분포를 제공하여 지역적 메시 개선에 활용됩니다.
        </Paragraph>

        <ModelFormulaBox
            title="에너지 노름 기반 오차"
            description={
                <>
                정확한 해 <MathJax inline>{"\\( u \\)"}</MathJax>와 근사 해 <MathJax inline>{"\\( u_h \\)"}</MathJax> 사이의 에너지 노름 오차
                </>
            }
            formulas={[
                "\\| u - u_h \\|_E = \\left( \\int_\\Omega (\\nabla u - \\nabla u_h)^T D (\\nabla u - \\nabla u_h) \\, d\\Omega \\right)^{1/2}"
            ]}
            />


        <Divider orientation="left">2. Residual-Based vs. Recovery-Based Estimation</Divider>
        <Paragraph>
          <Text strong>Residual-based</Text> 방법은 요소 및 경계에서의 지배 방정식 잔차를 기반으로 오차를 추정합니다.
        </Paragraph>
        <ModelFormulaBox
        title="요소 잔차 기반 오차 추정"
        description={
            <>
            요소 내부 잔차 <MathJax inline>{"\\( R_K \\)"}</MathJax>와 경계 잔차 <MathJax inline>{"\\( J_e \\)"}</MathJax>를 기반으로 오차 상한을 구성
            </>
        }
        formulas={[
            "\\eta_K^2 = h_K^2 \\| R_K \\|^2 + \\sum_{e \\in \\partial K} h_e \\| J_e \\|^2"
        ]}
        />


        <Paragraph>
          <Text strong>Recovery-based</Text> 방법은 주어진 해의 그래디언트를 보정(smoothing)하여 오차를 추정합니다. 대표적으로 Zienkiewicz-Zhu 방법이 사용됩니다.
        </Paragraph>

        <ModelFormulaBox
            title="Gradient Recovery 방법"
            description={
                <>
                향상된 그래디언트 <MathJax inline>{"\\( \\nabla^* u_h \\)"}</MathJax>와 기존 그래디언트{" "}
                <MathJax inline>{"\\( \\nabla u_h \\)"}</MathJax>의 차이를 기반으로 오차를 추정
                </>
            }
            formulas={[
                "\\eta^2 = \\int_\\Omega (\\nabla^* u_h - \\nabla u_h)^T D (\\nabla^* u_h - \\nabla u_h) \\ d\\Omega"
            ]}
            />


        <Divider orientation="left">3. Adaptivity: h-, p-, hp- 전략</Divider>
        <Paragraph>
          오차가 큰 영역을 중심으로 mesh를 자동 정련하는 기법이 <Text strong>적응형 해석</Text>입니다.
        </Paragraph>
        <ul>
          <li><Text code>h-adaptivity</Text>: 요소 크기를 줄여 해상도를 높임</li>
          <li><Text code>p-adaptivity</Text>: 요소 차수를 높여 해의 정밀도를 향상</li>
          <li><Text code>hp-adaptivity</Text>: 두 전략을 혼합하여 효율적 정밀도 확보</li>
        </ul>

        <Paragraph>
          이러한 정련은 일반적으로 각 요소에 대한 오차 지표 <MathJax inline>{"\\( \\eta_K \\)"}</MathJax>에 기반하여 수행됩니다.
        </Paragraph>

        <Divider orientation="left">4. Adaptive Algorithm Framework</Divider>
        <Paragraph>
          Adaptive FEM은 다음과 같은 반복 과정을 통해 구현됩니다:
        </Paragraph>
        <ol>
          <li>초기 메시 생성 및 해석 수행</li>
          <li>A posteriori 오차 추정 수행</li>
          <li>정련 기준에 따라 메시 수정 (refinement/coarsening)</li>
          <li>새로운 메시에 대해 해석 반복</li>
        </ol>

        <Paragraph>
        수렴성 보장을 위해 각 반복에서 오차 감소율을 분석하며, 정지 조건&nbsp;
        <MathJax inline>{"\\( \\eta < \\varepsilon \\)"}</MathJax>
        에 도달할 때까지 반복합니다.
        </Paragraph>


        <Divider orientation="left">5. 요약</Divider>
        <Paragraph>
          Adaptive FEM은 해석 정확도 향상과 계산 효율의 균형을 위한 강력한 도구입니다. 잔차 기반 및 복구 기반 오차 추정기법은 적절한 정련 전략(h/p/hp)을 유도하며, 자동화된 FEM 해석에 핵심 역할을 합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter17;