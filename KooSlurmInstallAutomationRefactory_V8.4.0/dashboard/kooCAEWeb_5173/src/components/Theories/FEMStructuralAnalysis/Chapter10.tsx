import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter10: React.FC = () => {
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
          본 장에서는 시간 의존 해석을 위한 유한 요소 해석법을 다룹니다. 질량 행렬, 감쇠 행렬의 도입과 함께 운동 방정식의 구성 및 시간 적분 기법을 학습합니다.
        </Paragraph>

        <Divider orientation="left">1. 운동 방정식</Divider>
        <ModelFormulaBox
          title="2차 미분형 운동 방정식"
          description="동적 해석에서 구조물의 시간에 따른 응답은 다음과 같은 운동 방정식으로 표현됩니다."
          formulas={["\\mathbf{M} \\ddot{\\mathbf{u}} + \\mathbf{C} \\dot{\\mathbf{u}} + \\mathbf{K} \\mathbf{u} = \\mathbf{F}(t)"]}
        />

        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{M} \\)"}</MathJax>: 질량 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{C} \\)"}</MathJax>: 감쇠 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{K} \\)"}</MathJax>: 강성 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{u} \\)"}</MathJax>: 변위 벡터</li>
            <li><MathJax inline>{"\\( \\mathbf{F}(t) \\)"}</MathJax>: 시간 의존 외력</li>       
          </ul>
        </Paragraph>

        <Divider orientation="left">2. 질량 행렬</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="Lumped Mass Matrix">
              <p>질량이 노드에 집중된 형태로 계산 간단하고 diagonal 행렬을 구성함.</p>
            </Card>
          </Col>
          <Col span={12}>
            <Card title="Consistent Mass Matrix">
              <p>요소의 shape function을 기반으로 유도된 질량 분포를 반영하는 행렬.</p>
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">3. 감쇠 행렬</Divider>
        <ModelFormulaBox
          title="Rayleigh 감쇠"
          description="감쇠 행렬은 보통 다음의 조합으로 표현됩니다:"
          formulas={["\\mathbf{C} = \\alpha \\mathbf{M} + \\beta \\mathbf{K}"]}
        />

        <Paragraph>
          <MathJax inline>{"\\( \\alpha \\)"}</MathJax>, <MathJax inline>{"\\( \\beta \\)"}</MathJax>는 실험이나 모드 분석을 통해 결정됨. 감쇠가 시간 해석의 안정성 및 진동 감쇠에 영향.
        </Paragraph>

        <Divider orientation="left">4. 시간 적분 기법</Divider>
        <Card title="Explicit / Implicit Time Integration">
          <List
            size="small"
            dataSource={[
              "Explicit: 중앙 차분법 (Central Difference Method)",
              "Implicit: Newmark-β Method, Wilson-θ Method",
              "Implicit 방법은 안정하지만 계산량이 많음",
              "Explicit 방법은 간단하지만 시간 간격 제약 존재"
            ]}
            renderItem={(item) => <List.Item>{item}</List.Item>}
          />
        </Card>

        <ModelFormulaBox
          title="Newmark-β 식"
          description="암시적 시간 적분에서 많이 쓰이는 Newmark 방식의 일반식은 다음과 같습니다."
          formulas={[
            "\\mathbf{u}_{n+1} = \\mathbf{u}_n + \\Delta t \\dot{\\mathbf{u}}_n + \\frac{\\Delta t^2}{2}[(1 - 2\\beta) \\ddot{\\mathbf{u}}_n + 2\\beta \\ddot{\\mathbf{u}}_{n+1}]"
          ]}
        />

        <Divider orientation="left">5. 안정성 조건</Divider>
        <Paragraph>
          Explicit 방법의 경우, 시간 간격 <MathJax inline>{"\\( \\Delta t \\)"}</MathJax>는 요소 크기, 재료 물성에 따라 제한됨.
        </Paragraph>
        <ModelFormulaBox
          title="Courant 조건 예시"
          description="파속(c)과 요소 길이(h)를 기반으로 제한됨."
          formulas={["\\Delta t < \\frac{h}{c}"]}
        />

        <Divider orientation="left">6. 초기 조건 설정</Divider>
        <Paragraph>
          초기 위치 <MathJax inline>{"\\( \\mathbf{u}(0) \\)"}</MathJax> 및 초기 속도 <MathJax inline>{"\\( \\dot{\\mathbf{u}}(0) \\)"}</MathJax>는 반드시 주어져야 시간 해석이 가능합니다.
        </Paragraph>

        <Divider orientation="left">7. 진동 해석 및 고유치 문제</Divider>
        <ModelFormulaBox
          title="고유치 문제 정의"
          description="자유 진동 해석 시 다음 고유치 문제를 풉니다:"
          formulas={["\\det(\\mathbf{K} - \\omega^2 \\mathbf{M}) = 0"]}
        />

        <Paragraph>
          여기서 <MathJax inline>{"\\( \\omega \\)"}</MathJax>는 고유 진동수이며, 모드 형상(mode shape)은 고유 벡터로 구성됩니다.
        </Paragraph>

        <Divider orientation="left">8. 응답 스펙트럼 해석</Divider>
        <Paragraph>
          지진과 같은 외부 진동에 대한 구조 응답을 주파수 영역에서 평가합니다. 특정 주파수 대역의 증폭 또는 감쇠를 파악하는 데 유용합니다.
        </Paragraph>

        <Divider orientation="left">9. 요약</Divider>
        <Paragraph>
          본 장에서는 동적 해석의 이론과 구현 방법을 학습하였습니다. 시간 의존 문제를 다루기 위한 핵심 개념(질량, 감쇠, 시간 적분)이 FEM에 어떻게 적용되는지를 이해하고, 진동 및 충격 응답을 예측하는 방법을 습득합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter10;
