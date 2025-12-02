import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter6: React.FC = () => {
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
          동적 해석에서는 질량과 감쇠를 포함한 운동 방정식을 다루게 됩니다. 시간에 따라 시스템이 어떻게 거동하는지를 예측하기 위해 시간 적분 기법이 필요합니다.
        </Paragraph>

        <Divider orientation="left">1. 운동 방정식</Divider>
        <ModelFormulaBox
          title="일반적인 운동 방정식"
          description="FEM 기반 구조 동역학의 기본 방정식은 다음과 같습니다."
          formulas={[
            "\\mathbf{M} \\ddot{\\mathbf{u}} + \\mathbf{C} \\dot{\\mathbf{u}} + \\mathbf{K} \\mathbf{u} = \\mathbf{F}(t)"
          ]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{M} \\)"}</MathJax>: 질량 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{C} \\)"}</MathJax>: 감쇠 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{K} \\)"}</MathJax>: 강성 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{F}(t) \\)"}</MathJax>: 시간 의존 하중</li>
            <li><MathJax inline>{"\\( \\mathbf{u}, \\dot{\\mathbf{u}}, \\ddot{\\mathbf{u}} \\)"}</MathJax>: 변위, 속도, 가속도</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">2. 시간 적분 개요</Divider>
        <Paragraph>
          시간 적분은 위의 운동 방정식을 이산화하여, 시간 스텝마다 상태 변수들을 갱신하는 과정입니다. 대표적인 방식으로 Newmark-$\beta$, 중앙차분법, 평균 가속도법 등이 있습니다.
        </Paragraph>

        <Divider orientation="left">3. Newmark-$\beta$ 방법</Divider>
        <ModelFormulaBox
          title="Newmark 방법의 일반식"
          description="변위 및 속도는 다음 식을 통해 시간 스텝마다 예측됩니다."
          formulas={[
            "\\mathbf{u}_{n+1} = \\mathbf{u}_n + \\Delta t \\dot{\\mathbf{u}}_n + \\frac{\\Delta t^2}{2} ((1 - 2\\beta) \\ddot{\\mathbf{u}}_n + 2\\beta \\ddot{\\mathbf{u}}_{n+1})",
            "\\dot{\\mathbf{u}}_{n+1} = \\dot{\\mathbf{u}}_n + \\Delta t ((1 - \gamma) \\ddot{\\mathbf{u}}_n + \gamma \\ddot{\\mathbf{u}}_{n+1})"
          ]}
        />
        <Paragraph>
          $\beta = 1/4$, $\gamma = 1/2$인 경우 평균 가속도법(무조건 안정)이며, $\beta = 0$, $\gamma = 1/2$은 중앙차분법(조건부 안정성)입니다.
        </Paragraph>

        <Divider orientation="left">4. 시스템 방정식 재구성</Divider>
        <ModelFormulaBox
          title="유효 강성 행렬 및 하중"
          description="각 시간 스텝에서 다음의 선형 시스템을 풉니다:"
          formulas={[
            "\\mathbf{K}_{eff} \\mathbf{u}_{n+1} = \\mathbf{F}_{eff}"
          ]}
        />
        <Paragraph>
          유효 강성 행렬 및 하중은 다음과 같이 정의됩니다:
        </Paragraph>
        <ModelFormulaBox
          title="유효 강성 행렬 및 하중"
          description="유효 강성 행렬 및 하중은 다음과 같이 정의됩니다:"
          formulas={[
            "\\mathbf{K}_{eff} = \\mathbf{K} + \\frac{\\gamma}{\\beta \\Delta t} \\mathbf{C} + \\frac{1}{\\beta \\Delta t^2} \\mathbf{M}",
            "\\mathbf{F}_{eff} = \\mathbf{F}_{n+1} + \\mathbf{M} \\mathbf{a}^* + \\mathbf{C} \\mathbf{v}^*"
          ]}
        />
        <Paragraph>
          여기서 <MathJax inline>{"\\( \\mathbf{a}^* \\)"}</MathJax>, <MathJax inline>{"\\( \\mathbf{v}^* \\)"}</MathJax>는 이전 시간 스텝의 값으로부터 유도된 예측 가속도 및 속도입니다.
        </Paragraph>

        <Divider orientation="left">5. 초기 조건 및 시뮬레이션 절차</Divider>
        <Paragraph>
          <MathJax inline>{"\\( t = 0 \\)"}</MathJax>에서 주어진 초기 조건 <MathJax inline>{"\\( \\mathbf{u}_0 \\)"}</MathJax>, <MathJax inline>{"\\( \\dot{\\mathbf{u}}_0 \\)"}</MathJax>로부터 다음 순서대로 진행됩니다:
          <ol>
            <li><MathJax inline>{"\\( \\mathbf{a}_0 = \\mathbf{M}^{-1}(\\mathbf{F}_0 - \\mathbf{C} \\dot{\\mathbf{u}}_0 - \\mathbf{K} \\mathbf{u}_0) \\)"}</MathJax> 계산</li>
            <li>다음 스텝까지 유효 시스템 계산 및 해 구하기</li>
            <li><MathJax inline>{"\\( \\dot{\\mathbf{u}}_{n+1}, \\ddot{\\mathbf{u}}_{n+1} \\)"}</MathJax> 갱신</li>
            <li>지정된 시간까지 반복</li>
          </ol>
        </Paragraph>

        <Divider orientation="left">6. 감쇠 모델링</Divider>
        <Paragraph>
          Rayleigh 감쇠를 자주 사용하며, 다음과 같이 정의됩니다:
        </Paragraph>
        <ModelFormulaBox
          title="Rayleigh 감쇠"
          description="Rayleigh 감쇠는 다음과 같이 정의됩니다:"
          formulas={["\\mathbf{C} = \\alpha \\mathbf{M} + \\beta \\mathbf{K}"]}
        />

        <Divider orientation="left">7. 요약</Divider>
        <Paragraph>
          본 장에서는 시간에 따른 구조 동역학 문제 해결을 위한 시간 적분 방법을 다루었습니다. 다음 장에서는 자유 진동 및 고유치 해석을 통해 구조물의 고유진동수를 계산하는 방법을 설명합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter6;
