import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter12: React.FC = () => {
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
          멀티피직스는 두 개 이상의 물리 현상을 동시에 고려하여 복합적인 시스템을 해석하는 기법입니다. 본 장에서는 열-기계(thermo-mechanical), 유체-구조(fsi), 전자기-기계(em-mechanical) 등 다양한 산업 응용을 FEM 프레임워크 내에서 어떻게 통합하는지를 다룹니다.
        </Paragraph>

        <Divider orientation="left">1. 열-기계 연성 문제</Divider>
        <ModelFormulaBox
          title="열 전달 방정식"
          description="우선 열 해석은 다음 지배 방정식을 따릅니다."
          formulas={["\\nabla \\cdot (k \\nabla T) + Q = \\rho c \\frac{\\partial T}{\\partial t}"]}
        />
        <ModelFormulaBox
          title="열 팽창으로 인한 기계 하중"
          description="열 응력은 다음과 같이 팽창계수 \(\alpha\)와 온도차 \(\Delta T\)로부터 계산됩니다."
          formulas={["{\\sigma}_\\text{thermal} = -E \\alpha \\Delta T {I}"]}
        />
        <Paragraph>
          이와 같이 열 전달 해석 후 온도장 \(T(x,t)\)을 기계 해석의 하중으로 넘겨주는 방식으로 연성이 구현됩니다.
        </Paragraph>

        <Divider orientation="left">2. 유체-구조 연성 (FSI)</Divider>
        <Paragraph>
          유체와 구조가 상호작용하는 경우, 유체는 구조에 힘을 가하고 구조는 유동 영역의 경계를 바꾸는 식으로 연성됩니다.
        </Paragraph>
        <ModelFormulaBox
          title="유체 영역: Navier-Stokes 방정식"
          description="불안정 비압축 유체의 운동을 설명합니다."
          formulas={["\\rho \\left( \\frac{\\partial \\mathbf{v}}{\\partial t} + \\mathbf{v} \\cdot \\nabla \\mathbf{v} \\right) = -\\nabla p + \\mu \\nabla^2 \\mathbf{v} + \\mathbf{f}"]}
        />
        <ModelFormulaBox
          title="경계 연성 조건"
          description="FSI에서는 다음과 같은 조건이 경계면에서 필요합니다."
          formulas={["\\mathbf{v}_\\text{fluid} = \\frac{\\partial \\mathbf{u}_\\text{solid}}{\\partial t}, ", "{\\sigma}_\\text{fluid} \\cdot \\mathbf{n} = {\\sigma}_\\text{solid} \\cdot \\mathbf{n}"]}
        />

        <Divider orientation="left">3. 산업 예제 및 해석 흐름</Divider>
        <Row gutter={16}>
          <Col span={12}>
            <Card title="열-기계 예제">
              <List
                dataSource={[
                  "반도체 패키지 열팽창으로 인한 변형 및 응력 해석",
                  "브레이크 디스크의 마찰열에 따른 변형 분석"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
          <Col span={12}>
            <Card title="FSI 예제">
              <List
                dataSource={[
                  "자동차 외피의 공력 해석",
                  "동맥 벽과 혈류의 연성 시뮬레이션"
                ]}
                renderItem={(item) => <List.Item>{item}</List.Item>}
              />
            </Card>
          </Col>
        </Row>

        <Divider orientation="left">4. 연성 해석 전략</Divider>
        <List
          header={<b>두 가지 주요 전략</b>}
          dataSource={[
            "강연성(Strong Coupling): 두 물리현상을 동시에 계산 (monolithic)",
            "약연성(Weak Coupling): 각 물리 계산을 분리 후 교환 (partitioned)"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Paragraph>
          연성 방식의 선택은 해의 정확도, 안정성, 계산 비용에 큰 영향을 미칩니다.
        </Paragraph>

        <Divider orientation="left">5. 요약</Divider>
        <Paragraph>
          본 장에서는 다양한 멀티피직스 해석 시나리오를 소개하고, FEM 내 연성 구현 방식과 수식 구조, 실제 산업 적용 예제를 설명했습니다. 다음 장에서는 고차 요소를 포함한 고정밀 FEM 기법을 다룹니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter12;