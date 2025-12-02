import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter7: React.FC = () => {
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
          본 장에서는 자유 진동 해석을 위한 고유치 문제를 다룹니다. 구조물의 고유진동수와 고유형상(mode shape)을 구하여 동적 특성을 이해하는 데 중요한 기초를 제공합니다.
        </Paragraph>

        <Divider orientation="left">1. 자유 진동 방정식</Divider>
        <ModelFormulaBox
          title="질량-강성 시스템의 운동 방정식 (자유 진동)"
          description="외력이 없는 경우, 운동 방정식은 다음과 같습니다:"
          formulas={["\\mathbf{M} \\ddot{\\mathbf{u}} + \\mathbf{K} \\mathbf{u} = 0"]}
        />

        <Divider orientation="left">2. 고유치 문제 정식화</Divider>
        <ModelFormulaBox
          title="조화해 가정"
          description="해를 다음과 같은 조화진동 형태로 가정합니다:"
          formulas={["\\mathbf{u}(t) = \\mathbf{\\phi} e^{i \\omega t}"]}
        />

        <ModelFormulaBox
          title="일반화 고유치 문제"
          description="이를 운동 방정식에 대입하면 다음과 같은 고유치 문제가 유도됩니다:"
          formulas={["(\\mathbf{K} - \\omega^2 \\mathbf{M}) \\mathbf{\\phi} = 0"]}
        />

        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\omega \\)"}</MathJax>: 고유진동수 (rad/s)</li>
            <li><MathJax inline>{"\\( \\mathbf{\\phi} \\)"}</MathJax>: 고유형상 (mode shape)</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">3. 고유치 해석의 물리적 의미</Divider>
        <Paragraph>
          구조물은 각 고유진동수에 해당하는 고유형상으로 진동할 수 있으며, 외력이 해당 주파수와 일치할 경우 공진 현상이 발생합니다. 고유형상은 일반적으로 정규화(normalization)되어 표현됩니다.
        </Paragraph>

        <Divider orientation="left">4. 수치 해법</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="고유치 해석 기법">
              <List
                size="small"
                dataSource={[
                  "Inverse Iteration",
                  "Subspace Iteration",
                  "Lanczos Method",
                  "QR Algorithm"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
          <Col span={12}>
            <Card title="주요 특징">
              <List
                size="small"
                dataSource={[
                  "가장 작은 혹은 큰 고유치부터 계산 가능",
                  "모드 수 제한 가능",
                  "정규 직교성 이용한 후처리"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">5. 정규화 조건</Divider>
        <ModelFormulaBox
          title="모드 정규화"
          description="해석 및 비교를 위해 다음과 같이 정규화합니다:"
          formulas={["\\mathbf{\\phi}_i^T \\mathbf{M} \\mathbf{\\phi}_j = \\delta_{ij}", "\\mathbf{\\phi}_i^T \\mathbf{K} \\mathbf{\\phi}_j = \\omega_i^2 \\delta_{ij}"]}
        />

        <Divider orientation="left">6. 응용 및 예시</Divider>
        <Paragraph>
          고유진동수는 설계에서 구조물의 공진 주파수를 피하거나 제어장치의 조율 등에 사용됩니다. 예를 들어 스마트폰의 진동모터 설계, 고층건물의 동적 응답 분석 등에 활용됩니다.
        </Paragraph>

        <Divider orientation="left">7. 요약</Divider>
        <Paragraph>
          고유치 해석은 동적 해석의 핵심 요소로서, 질량 및 강성의 고유 특성으로부터 시스템의 진동 특성을 규명할 수 있게 해줍니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter7;
