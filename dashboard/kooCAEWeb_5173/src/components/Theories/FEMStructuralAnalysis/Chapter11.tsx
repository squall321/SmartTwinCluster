import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter11: React.FC = () => {
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
          본 장에서는 유한 요소 해석에서 접촉(Contact)과 마찰(Friction)을 모델링하는 방법을 다룹니다. 이는 구조물 간 상호작용, 충돌, 성형 해석 등 다양한 산업 분야에서 중요한 역할을 합니다.
        </Paragraph>

        <Divider orientation="left">1. 접촉의 수학적 모델링</Divider>
        <Paragraph>
          두 물체가 접촉하는 경우, 서로 침투하지 않아야 한다는 비침투 조건을 만족해야 합니다. 이를 수학적으로 표현하면 다음과 같습니다:
        </Paragraph>
        <ModelFormulaBox
          title="비침투 조건"
          description="접촉면에서 주 표면과 종속 표면 사이의 간격 $g_n$는 항상 0 이상이어야 합니다."
          formulas={["g_n \\geq 0, \\quad \\lambda_n \\geq 0, \\quad g_n \\cdot \\lambda_n = 0"]}
        />
        <Paragraph>
          여기서 <MathJax inline>{"\\( \\lambda_n \\)"}</MathJax>은 접촉면에 작용하는 법선 방향 접촉력입니다. 이 조건을 Karush-Kuhn-Tucker(KKT) 조건이라 합니다.
        </Paragraph>

        <Divider orientation="left">2. 접촉 구현 방법</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="1. Penalty Method">
              <List
                size="small"
                dataSource={[
                  "침투 시 강한 반발력을 통해 접촉력을 근사",
                  "단순 구현이 가능하나 penalty 계수 설정이 중요",
                  "침투 오차 존재 가능"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
          <Col span={12}>
            <Card title="2. Lagrange Multiplier Method">
              <List
                size="small"
                dataSource={[
                  "비침투 조건을 엄격히 만족",
                  "추가 자유도 (multipliers)가 필요",
                  "희소 행렬 크기 증가, saddle point 문제 발생"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">3. 마찰 모델링</Divider>
        <ModelFormulaBox
          title="Coulomb 마찰 법칙"
          description="마찰력은 접촉력과 마찰계수에 비례하며, 임계값 이내에서는 stick, 그 이상이면 slip이 발생합니다."
          formulas={["|\\lambda_t| \\leq \\mu \\cdot \\lambda_n"]}
        />
        <Paragraph>
          - <MathJax inline>{"\\( \\mu \\)"}</MathJax>는 마찰계수, <MathJax inline>{"\\( \\lambda_t \\)"}</MathJax>는 접선방향 마찰력입니다.
          <br />- Stick/slip 상태를 고려한 비선형 접촉 문제로 이어집니다.
        </Paragraph>

        <Divider orientation="left">4. 비선형성과 반복해법</Divider>
        <Paragraph>
          접촉 및 마찰 문제는 본질적으로 **비선형 문제**이며, 반복적인 해석 기법 (예: Newton-Raphson + Active Set 전략)을 필요로 합니다. 접촉 상태가 변화하며 계가 변동되므로, 반복적으로 상태를 업데이트하며 수렴해야 합니다.
        </Paragraph>

        <Divider orientation="left">5. FEM 내에서의 구현 흐름</Divider>
        <List
          bordered
          dataSource={[
            "접촉 후보 탐색 (contact detection)",
            "접촉면 간 간격 및 상대 속도 계산",
            "접촉 조건 및 마찰 조건 평가",
            "접촉 강성 행렬 또는 힘 계산",
            "전체 시스템에 반영 후 반복 수렴"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">6. 간단한 예제</Divider>
        <Paragraph>
          두 블록이 충돌하여 접촉하는 문제를 고려합니다. Penalty 방식으로 접촉력을 모델링하고, 마찰계수를 조절하며 해석 결과를 비교합니다. 접촉력의 발생, 침투량 변화, 마찰력 방향의 변화 등을 시각화할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">7. 요약</Divider>
        <Paragraph>
          접촉과 마찰은 FEM에서 필수적인 확장 기능으로, 다양한 해석에 널리 사용됩니다. 비선형성과 조건부 제약을 다루는 수치기법을 잘 이해하고 적용하는 것이 중요합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter11;