import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter9: React.FC = () => {
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
          비선형 유한 요소 해석은 선형 해석의 한계를 넘어 더 복잡한 물리적 현상을 다루기 위해 필요합니다.
          본 장에서는 기하학적 비선형성, 재료 비선형성, 접촉 비선형성 등의 개념을 다루고, Newton-Raphson 반복법을 통한 해석 기법을 소개합니다.
        </Paragraph>

        <Divider orientation="left">1. 비선형 해석의 필요성</Divider>
        <Paragraph>
          다음과 같은 조건에서는 선형 해석이 부정확해집니다:
          <ul>
            <li>큰 변형(large deformation)이 발생하는 경우</li>
            <li>소성변형, 크리프 등 재료 거동이 선형이 아닌 경우</li>
            <li>접촉 조건 등 비선형 경계 조건을 포함하는 경우</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">2. 일반적인 비선형 방정식</Divider>
        <ModelFormulaBox
          title="비선형 시스템의 형식"
          description="비선형 해석에서는 시스템 방정식이 다음과 같은 형태로 기술됩니다:"
          formulas={["\\mathbf{R}(\\mathbf{u}) = \\mathbf{F}_{\\text{ext}} - \\mathbf{F}_{\\text{int}}(\\mathbf{u}) = 0"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{F}_{\\text{ext}} \\)"}</MathJax>: 외력 벡터</li>
            <li><MathJax inline>{"\\( \\mathbf{F}_{\\text{int}}(\\mathbf{u}) \\)"}</MathJax>: 현재 변위에 따른 내부력</li>
            <li><MathJax inline>{"\\( \\mathbf{R}(\\mathbf{u}) \\)"}</MathJax>: 잔차 벡터</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">3. Newton-Raphson 방법</Divider>
        <ModelFormulaBox
          title="Newton-Raphson 반복법"
          description="선형화된 형태의 시스템을 반복적으로 풀어 다음 식을 만족하도록 업데이트합니다:"
          formulas={["\\mathbf{K}_{\\text{T}}^{(i)} \\Delta \\mathbf{u}^{(i)} = -\\mathbf{R}^{(i)}"]}
        />
        <Paragraph>
          반복 과정에서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{K}_\\text{T} \\)"}</MathJax>: 접선 강성 행렬 (Tangent Stiffness Matrix)</li>
            <li><MathJax inline>{"\\( \\Delta \\mathbf{u}^{(i)} \\)"}</MathJax>: 현재 반복의 변위 증가량</li>
            <li><MathJax inline>{"\\( \\mathbf{u}^{(i+1)} = \\mathbf{u}^{(i)} + \\Delta \\mathbf{u}^{(i)} \\)"}</MathJax></li>
          </ul>
        </Paragraph>

        <Divider orientation="left">4. 접선 강성 행렬 구성</Divider>
        <Paragraph>
          접선 강성 행렬은 다음과 같은 구성 요소를 포함합니다:
          <ul>
            <li>재료 강성: <MathJax inline>{"\\( \\partial \\mathbf{F}_{\\text{int}} / \\partial {\\varepsilon} \\)"}</MathJax></li>
            <li>기하학적 강성: 변형된 형상에 따른 추가 항</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">5. 수렴 조건 및 인크리멘탈 로딩</Divider>
        <Paragraph>
          비선형 해석은 한 번의 해로 수렴하지 않기 때문에 하중을 나누어 점진적으로 적용하고, 반복 알고리즘의 수렴 조건을 설정해야 합니다. 일반적인 수렴 조건은 다음과 같습니다:
          <ul>
            <li><MathJax inline>{"\\( \\| \\mathbf{R}^{(i)} \\| < \\epsilon \\)"}</MathJax></li>
            <li><MathJax inline>{"\\( \\| \\Delta \\mathbf{u}^{(i)} \\| < \\delta \\)"}</MathJax></li>
          </ul>
        </Paragraph>

        <Divider orientation="left">6. 응용 예제</Divider>
        <Paragraph>
          큰 변형을 겪는 고무 재료나 압축에 따른 좌굴 문제가 대표적인 비선형 해석 예제입니다. 이러한 경우에는:
          <ul>
            <li>Hyperelastic 재료 모델</li>
            <li>Arc-length 기법을 활용한 안정적 해 구하기</li>
          </ul>
          등이 고려됩니다.
        </Paragraph>

        <Divider orientation="left">7. 요약</Divider>
        <Paragraph>
          비선형 유한 요소 해석은 반복적이고 복잡한 계산이 필요하지만, 실제 엔지니어링 문제에 필수적인 기법입니다. 본 장에서는 Newton-Raphson 방법을 중심으로 기초 개념과 구성 요소를 이해했습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter9;
