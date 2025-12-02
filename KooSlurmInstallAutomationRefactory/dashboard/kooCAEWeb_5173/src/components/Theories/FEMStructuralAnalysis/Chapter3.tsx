import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter3: React.FC = () => {
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
          본 장에서는 2차원 구조 문제에 대한 유한 요소 해석을 다룹니다. 삼각형 및 사각형 요소를 기반으로 하여 정적 구조 문제를 FEM으로 푸는 과정을 단계별로 설명합니다.
        </Paragraph>

        <Divider orientation="left">1. 2D 연속체 지배 방정식</Divider>
        <ModelFormulaBox
          title="2차원 지배 방정식 (선형 정적 해석)"
          description="2차원 탄성체는 다음의 평형 방정식을 만족해야 합니다:"
          formulas={["-\\nabla \\cdot \\mathbf{\\sigma} = \\mathbf{b} \\quad \\text{in } \\Omega"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{u} = [u, v]^T \\)"}</MathJax>: x, y 방향 변위</li>
            <li><MathJax inline>{"\\( \\mathbf{b} = [b_x, b_y]^T \\)"}</MathJax>: 체적 하중</li>
            <li><MathJax inline>{"\\( \\mathbf{\\sigma} \\)"}</MathJax>: 응력 텐서</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">2. 약한 형식 도출</Divider>
        <ModelFormulaBox
          title="약한 형식"
          description="시험 함수 \( \mathbf{w} \)를 곱하고 적분 후 부분적분을 통해 다음 형태의 약한 형식을 유도합니다:"
          formulas={["\\int_\\Omega ({\\epsilon}(\\mathbf{w}) : \\mathbf{\\sigma}) \\ d\\Omega = \\int_\\Omega \\mathbf{w} \\cdot \\mathbf{b} \\ d\\Omega + \\int_{\\partial\\Omega} \\mathbf{w} \\cdot \\bar{\\mathbf{t}} \\ d\\Gamma"]}
        />

        <Divider orientation="left">3. 요소 형태 및 Shape Function</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="삼각형 요소 (Linear Triangle)">
              <List
                size="small"
                dataSource={[
                  "3개의 노드를 가짐",
                  "선형 shape function 사용",
                  "면적 좌표계 (barycentric coordinates) 사용"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
          <Col span={12}>
            <Card title="사각형 요소 (Bilinear Quadrilateral)">
              <List
                size="small"
                dataSource={[
                  "4개의 노드를 가짐",
                  "이차원 isoparametric mapping 사용",
                  "자연 좌표계 (ξ, η) 사용"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">4. 요소 강성 행렬</Divider>
        <ModelFormulaBox
          title="요소 강성 행렬의 일반적 형태"
          description="각 요소의 강성 행렬은 다음과 같이 계산됩니다:"
          formulas={["\\mathbf{k}^{(e)} = \\int_{\\Omega^e} \\mathbf{B}^T \\mathbf{D} \\mathbf{B} \\ d\\Omega"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{B} \\)"}</MathJax>: 변형률-변위 행렬</li>
            <li><MathJax inline>{"\\( \\mathbf{D} \\)"}</MathJax>: 재료 강성 행렬 (선형 탄성체일 경우 상수)</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">5. 전역 시스템 조립</Divider>
        <ModelFormulaBox
          title="전체 시스템"
          description="요소별 강성 행렬을 전체 자유도 기반으로 조립하여 다음의 시스템을 구성합니다:"
          formulas={["\\mathbf{K} \\cdot \\mathbf{u} = \\mathbf{F}"]}
        />

        <Divider orientation="left">6. 경계 조건 적용</Divider>
        <Paragraph>
          <Text strong>Dirichlet 경계 조건</Text>은 강제 변위를 통해 행렬 시스템을 수정하며, <Text strong>Neumann 경계 조건</Text>은 하중 벡터 <MathJax inline>{"\\( \\mathbf{F} \\)"}</MathJax>에 경계 하중을 포함시킵니다.
        </Paragraph>

        <Divider orientation="left">7. 간단한 예제</Divider>
        <Paragraph>
          정사각형 영역을 4개의 삼각형 요소로 나눈 뒤, 각 요소에 대한 shape function, B 행렬, 요소 강성 행렬을 계산하고 전체 시스템을 구성합니다. 경계 조건을 주고, 변위 <MathJax inline>{"\\( \\mathbf{u} \\)"}</MathJax>를 해석적으로 혹은 수치적으로 계산합니다.
        </Paragraph>

        <Divider orientation="left">8. 요약</Divider>
        <Paragraph>
          본 장에서는 2차원 문제에 대한 FEM 접근 방법을 소개하고, 요소 형상에 따른 수치 적용 방법을 살펴보았습니다. 다음 장에서는 다양한 형상의 요소를 공통적으로 다룰 수 있도록 하는 이소파라메트릭 기법을 학습합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter3;
