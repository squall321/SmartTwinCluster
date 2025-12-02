import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter24: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 전통적인 유한 요소법(FEM)의 한계를 보완하는 <Text strong>무요소 기법(Meshfree methods)</Text>과
          균열이나 불연속 처리를 위한 <Text strong>확장 유한 요소법(XFEM)</Text>을 다룹니다. 경계 이동, 파괴, 큰 변형 등을 다루는 문제에서 유용하게 적용됩니다.
        </Paragraph>

        <Divider orientation="left">1. 무요소 기법 개요</Divider>
        <Paragraph>
          무요소 기법은 명시적인 요소 연결 없이 <Text strong>노드 기반 보간 함수</Text>를 사용하여 변위를 근사합니다.
          대표적인 기법으로는 <Text strong>Element-Free Galerkin (EFG)</Text>과 <Text strong>스무드 파티클 유체역학(SPH)</Text>이 있습니다.
        </Paragraph>

        <List
          size="small"
          dataSource={[
            "EFG: 이동 가중 최소제곱법(Moving Least Squares, MLS)을 기반으로 형상 함수 구성",
            "SPH: 입자 간 커널 함수 기반 상호작용을 통해 연속체 방정식 근사"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">2. 확장 유한 요소법 (XFEM)</Divider>
        <Paragraph>
          XFEM은 기존 FEM 기반에 <Text strong>불연속 함수 또는 특이 함수</Text>를 추가하여 균열과 같은 특이성을 자연스럽게 표현할 수 있도록 합니다.
          <Text strong>Partition of Unity</Text> 개념을 바탕으로 기존 요소에 enrichment를 추가합니다.
        </Paragraph>

        <ModelFormulaBox
          title="XFEM 변위 근사"
          description={
            <>기존 FEM 근사에 불연속성과 특이성을 반영한 항을 추가하여 구성합니다:</>
          }
          formulas={[
            "u(x) = \\sum_{i \\in I} N_i(x) u_i + \\sum_{j \\in J} N_j(x) H(x) a_j + \\sum_{k \\in K} N_k(x) \\sum_{l} F_l(x) b_k^l"
          ]}
        />

        <Divider orientation="left">3. Level Set Method와 결합</Divider>
        <Paragraph>
          XFEM에서는 <Text strong>레벨셋(Level Set)</Text> 방법과 결합하여 균열면이나 계면의 위치를 암시적으로 추적할 수 있습니다.
          이는 균열의 진전이나 계면의 이동을 수치적으로 안정적으로 처리하는 데 유리합니다.
        </Paragraph>

        <Divider orientation="left">4. FEM과의 비교 및 적용 사례</Divider>
        <Paragraph>
          Meshfree 및 XFEM 기법은 다음과 같은 장점과 한계를 가집니다:
        </Paragraph>

        <List
          size="small"
          dataSource={[
            "장점: 큰 변형, 파괴, 경계 이동 문제에서 유연한 적용",
            "단점: 경계 조건 처리 복잡, 계산 비용 증가",
            "응용 예시: 균열 진전 해석, 유체-구조 상호작용, 성형 가공 해석"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 전통 FEM의 한계를 극복하기 위한 meshfree 기법과 XFEM의 원리 및 응용을 다루었습니다.
          균열 해석이나 복잡한 비선형 문제에 효과적으로 적용 가능하며, 향후 다양한 멀티피직스 문제로 확장되고 있습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter24;