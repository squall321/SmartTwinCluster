import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter4: React.FC = () => {
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
          본 장에서는 다양한 요소 형상에 대해 일관된 수치 해석을 가능하게 하는 이소파라메트릭 매핑(Isoparametric Mapping) 기법을 다룹니다. 이는 실제 좌표계에서 자연 좌표계로 변환하여 적분 및 해석을 용이하게 합니다.
        </Paragraph>

        <Divider orientation="left">1. 개념 소개</Divider>
        <Paragraph>
          이소파라메트릭 매핑은 요소의 형상 함수(Shape Function)를 사용하여 실제 좌표계를 자연 좌표계로 매핑합니다. 이를 통해 변위, 하중, 기하 구조를 동일한 함수로 표현할 수 있습니다.
        </Paragraph>

        <ModelFormulaBox
          title="Isoparametric Mapping"
          description="자연 좌표계 $(\xi, \eta)$에서 실제 좌표 $(x, y)$는 다음과 같이 표현됩니다."
          formulas={["x = \\sum_{i=1}^n N_i(\\xi, \\eta) x_i", "y = \\sum_{i=1}^n N_i(\\xi, \\eta) y_i"]}
        />

        <Divider orientation="left">2. 자코비안 행렬</Divider>
        <ModelFormulaBox
          title="Jacobian Matrix"
          description="자연 좌표계에서 실제 좌표계로의 변화율을 나타내는 자코비안 행렬은 다음과 같습니다."
          formulas={[
            "J = \\begin{bmatrix} \\frac{\\partial x}{\\partial \\xi} & \\frac{\\partial x}{\\partial \\eta} \\\\ \\frac{\\partial y}{\\partial \\xi} & \\frac{\\partial y}{\\partial \\eta} \\end{bmatrix}"
          ]}
        />

        <Paragraph>
          자코비안 행렬을 사용하면 면적 적분, 기하학적 변환, 변형률 계산 등에 핵심적으로 활용됩니다.
        </Paragraph>

        <Divider orientation="left">3. 면적 적분 변환</Divider>
        <ModelFormulaBox
          title="적분 변수의 변환"
          description="요소 영역의 적분은 자코비안 행렬의 행렬식을 활용하여 다음과 같이 변환됩니다."
          formulas={["\\int_{\\Omega^e} f(x, y) \\, dxdy = \\int_{-1}^{1} \\int_{-1}^{1} f(\\xi, \\eta) |J(\\xi, \\eta)| \\, d\\xi d\\eta"]}
        />

        <Divider orientation="left">4. 이소파라메트릭 요소 예시</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="4노드 사각형 요소">
              <List
                size="small"
                dataSource={[
                  "각 노드는 자연 좌표계 (-1, -1) ~ (1, 1)에 배치됨",
                  "형상 함수는 이차원 곱 형태로 정의됨",
                  "자코비안은 위치에 따라 일정하지 않음"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
          <Col span={12}>
            <Card title="3노드 삼각형 요소">
              <List
                size="small"
                dataSource={[
                  "Barycentric 좌표계 사용",
                  "선형 또는 곡선 요소 형상 표현 가능",
                  "곡면 경계 요소에 유리함"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">5. 정리</Divider>
        <Paragraph>
          이소파라메트릭 매핑은 다양한 요소 형상에 대해 공통된 해석 프레임워크를 제공하며, 복잡한 기하학에 대한 정확한 표현과 수치 적분을 가능하게 합니다. 이는 2차원 및 3차원 FEM에서 핵심적인 역할을 하며, 고차 요소나 곡면 경계 처리에 매우 유용합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter4;