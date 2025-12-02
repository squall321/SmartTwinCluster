import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter1: React.FC = () => {
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
          본 장에서는 유한 요소법(Finite Element Method, FEM)의 이론적 배경과 적용 동기를 살펴보고, 수치 해석 기법으로서의 FEM의 전반적인 구조와 절차를 설명합니다.
        </Paragraph>

        <Divider orientation="left">1. FEM의 등장 배경과 필요성</Divider>
        <Card size="small">
          <Paragraph>
            실생활에서의 대부분의 공학 문제는 연속체의 거동을 기반으로 모델링되며, 이는 편미분 방정식으로 기술됩니다. 하지만 다음과 같은 복잡성 때문에 해석적으로 풀기 어렵습니다:
          </Paragraph>
          <List
            size="small"
            bordered
            dataSource={[
              "복잡한 형상 (예: 곡면, 구멍, 경계) 및 재료 분포",
              "하중의 비선형성 및 경계 조건의 다양성",
              "시간에 따른 변화 및 다물리장 연성 (열+구조 등)"
            ]}
            renderItem={(item) => <List.Item>{item}</List.Item>}
          />
        </Card>

        <Divider orientation="left">2. FEM의 핵심 아이디어</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="기존 해석 방식" bordered={false}>
              <List
                size="small"
                dataSource={[
                  "해석해 기반",
                  "간단한 기하와 하중만 가능",
                  "복잡성 증가 시 불가능"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
          <Col span={12}>
            <Card title="FEM의 접근 방식" bordered={false}>
              <List
                size="small"
                dataSource={[
                  "도메인을 요소로 분할",
                  "각 요소에서 근사 함수 사용",
                  "전체 시스템으로 조립하여 근사 해 계산"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">3. 수학적 배경</Divider>
        <ModelFormulaBox
          title="연속체 문제의 지배 방정식"
          description="일반적인 구조 해석 문제는 다음과 같은 평형 방정식으로 표현됩니다:"
          formulas={["-\\nabla \\cdot \\mathbf{\\sigma} = \\mathbf{b} \\quad \\text{in } \\Omega"]}
        />
        <Paragraph>
          여기서:
          <ul>
            <li><MathJax inline>{"\\( \\mathbf{\\sigma} \\)"}</MathJax>: 응력 텐서</li>
            <li><MathJax inline>{"\\( \\mathbf{b} \\)"}</MathJax>: 체적 하중 벡터</li>
            <li><MathJax inline>{"\\( \\Omega \\)"}</MathJax>: 해석 영역</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">4. 약한 형식 유도</Divider>
        <Paragraph>
          FEM에서는 직접적인 해 대신 약한 형식(Weak Form)을 도입하여 문제를 수치적으로 풀 수 있도록 합니다.
        </Paragraph>
        <ModelFormulaBox
          title="가중 잔차식"
          description="시험 함수 $w(x)$를 곱하고 적분하여 미분 차수를 낮춥니다."
          formulas={["\\int_\\Omega w (-\\nabla \\cdot \\mathbf{\\sigma}) d\\Omega = \\int_\\Omega w \\cdot \\mathbf{b} d\\Omega"]}
        />
        <ModelFormulaBox
          title="부분적분 후 약한 형식"
          description="부분적분을 수행하여 미분 연산을 시험 함수로 이동시킵니다."
          formulas={["\\int_\\Omega {\\epsilon}(w) : \\mathbf{\\sigma} \\ d\\Omega = \\int_\\Omega w \\cdot \\mathbf{b} \\ d\\Omega + \\int_{\\partial\\Omega} w \\cdot \\bar{\\mathbf{t}} \\ d\\Gamma"]}
        />

        <Divider orientation="left">5. FEM 해석 절차</Divider>
        <List
          size="small"
          header={<Text strong>FEM은 다음과 같은 순서를 따릅니다:</Text>}
          bordered
          dataSource={[
            "Mesh 생성: 도메인을 요소로 분할",
            "Shape Function 정의: 각 요소 내 근사 함수 설정",
            "요소 단위의 강성 행렬 구성",
            "전역 행렬 조립",
            "경계 조건 적용 및 해 계산"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">6. 기본 행렬 시스템</Divider>
        <ModelFormulaBox
          title="선형 시스템"
          description="전역 시스템은 다음과 같은 형태를 가집니다:"
          formulas={["\\mathbf{K} \\cdot \\mathbf{u} = \\mathbf{F}"]}
        />

        <Divider orientation="left">7. 장점 및 단점</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="장점" bordered={false}>
              <ul>
                <li>복잡한 형상/조건에 적용 가능</li>
                <li>다양한 물리 분야에 확장 가능</li>
                <li>고정밀 수치 해석 가능</li>
              </ul>
            </Card>
          </Col>
          <Col span={12}>
            <Card title="단점" bordered={false}>
              <ul>
                <li>메시 품질에 따라 해 정확도 영향</li>
                <li>비선형 문제 시 계산 시간 증가</li>
                <li>수렴성 문제 발생 가능</li>
              </ul>
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">8. 적용 분야</Divider>
        <Paragraph>
          FEM은 다음과 같은 다양한 분야에 사용됩니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "구조역학: 하중, 진동, 좌굴 등",
            "열전달 해석",
            "전자기장 분석",
            "유체 흐름 및 다중 물리 연성"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">9. 요약 및 다음 장 안내</Divider>
        <Paragraph>
          본 장에서는 FEM의 이론적 동기, 수학적 모델링, 약한 형식 유도, 절차 및 응용에 대해 개괄적으로 살펴보았습니다. 다음 장에서는 가장 단순한 형태인 1차원 선형 요소를 사용하여 FEM 해석을 수치적으로 수행하는 과정을 배웁니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter1;
