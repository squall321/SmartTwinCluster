import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const PDEFEMChapter2: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">
        <Title level={2}>제 2 장: 1차원 문제를 위한 연속 요소</Title>

        <Divider orientation="left">2.1 일반적인 프레임워크</Divider>
        <Paragraph>
          유한 요소법(FEM)은 연속체 문제를 수치적으로 해결하는 방법으로, 1차원 문제를 다룰 때에도 동일한 기본적인 접근 방식을 사용합니다. 특히, 1차원 문제에서는 강성 행렬을 구하기 위한 기초적인 방법론이 중요한데, 이를 위해서는 문제의 약한 형태(weak form)로 변환해야 합니다. 갤러킨 방법(Galerkin method)은 가장 널리 사용되는 기법입니다.
        </Paragraph>
        <Paragraph>
          <Text strong>갤러킨 방법 (Galerkin Method):</Text> FEM에서 사용되는 가장 일반적인 방법으로, 주어진 방정식의 해를 근사하는데 사용되는 기저함수를 선택하고, 이를 사용하여 방정식의 약한 형태를 구성한 뒤, 그 방정식에서 해를 구하는 방식입니다. 이 방법은 기저함수를 선택하는 과정에서 정확도를 조절할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">2.2 최저 차수 요소</Divider>
        <Paragraph>
          1차원 문제에서 가장 단순한 요소는 선형 요소(linear element)입니다. 선형 요소에서는 기저 함수로 선형 함수를 사용하여 해를 근사합니다. 이 방식은 수학적으로 간단하지만, 정밀도가 높지 않으며 주로 기본적인 문제를 해결할 때 사용됩니다. 선형 요소를 사용하면 강성 행렬을 간단하게 계산할 수 있으며, 해의 근사는 저차수로 이루어집니다.
        </Paragraph>
        <Paragraph>
          <Text strong>선형 요소의 근사:</Text> 1차원 선형 요소에서는 각 요소를 두 개의 노드로 정의하며, 기저 함수로는 <MathJax inline>{"\\(N_1(x)\\)"}</MathJax>와 <MathJax inline>{"\\(N_2(x)\\)"}</MathJax>를 사용합니다. 이때, 해는 두 개의 노드에서의 값에 의해 결정됩니다.
        </Paragraph>
        <ModelFormulaBox
          title="선형 요소의 근사"
          description={<><Text strong>선형 기저 함수</Text>를 사용하여 근사를 계산합니다:</>}
          formulas={["u(x) = N_1(x) u_1 + N_2(x) u_2"]}
        />

        <Divider orientation="left">2.3 고차수 수치 적분</Divider>
        <Paragraph>
          고차수 적분은 유한 요소법에서 필수적인 기술입니다. 1차원 문제에서는 일반적으로 고차수 수치 적분인 <Text strong>가우시안 적분</Text>을 사용하여 강성 행렬과 내부 힘 벡터를 계산합니다. 가우시안 적분은 특정한 "노드"에서 함수의 값을 평가하여 적분을 계산하는 방법으로, 정확한 근사값을 제공합니다.
        </Paragraph>
        <Paragraph>
          <Text strong>가우시안 적분:</Text> 가우시안 적분은 함수 <MathJax inline>{"\\(f(x)\\)"}</MathJax>를 정해진 노드와 가중치 값을 사용하여 근사합니다. 예를 들어, 2점 가우시안 적분에서는 두 개의 노드에서 함수 값을 평가하여 적분을 계산합니다.
        </Paragraph>
        <ModelFormulaBox
          title="가우시안 적분"
          description={<><Text strong>가우시안 적분</Text>은 함수 <MathJax inline>{"\\(f(x)\\)"}</MathJax>를 정해진 노드와 가중치 값을 사용하여 근사합니다. 예를 들어, 2점 가우시안 적분에서는 두 개의 노드에서 함수 값을 평가하여 적분을 계산합니다.</>}
          formulas={["\\int_a^b f(x) dx \\approx w_1 f(x_1) + w_2 f(x_2)"
          ]}
        />

        <Divider orientation="left">2.4 고차수 요소</Divider>
        <Paragraph>
          고차수 요소는 선형 요소보다 더 높은 차수의 다항식을 사용하여 문제를 근사합니다. 고차수 요소는 해의 정확도를 높이기 위해 사용되며, 특히 비선형 문제나 고차 미분 방정식에서 유용하게 적용됩니다. 고차수 요소는 보다 복잡한 기하학적 문제를 해결할 때 사용됩니다.
        </Paragraph>
        <Paragraph>
          <Text strong>고차수 요소:</Text> 고차수 요소에서는 선형 함수 외에도 2차, 3차 다항식을 사용할 수 있습니다. 이 경우 기저 함수는 $N_1(x)$, $N_2(x)$와 같이 더 많은 다항식을 포함하며, 이를 통해 보다 정밀한 해를 구할 수 있습니다.
        </Paragraph>
        <ModelFormulaBox
          title="고차수 요소의 근사"
          description={<><Text strong>고차수 기저 함수</Text>를 사용한 근사:</>}
          formulas={["u(x) = N_1(x) u_1 + N_2(x) u_2 + N_3(x) u_3"]}
        />

        <Divider orientation="left">2.5 희소 강성 행렬</Divider>
        <Paragraph>
          유한 요소법에서 계산되는 강성 행렬은 종종 희소 행렬(sparse matrix)입니다. 이는 대부분의 원소가 0인 행렬로, 메모리 사용을 최적화하고 계산 속도를 향상시킵니다. 희소 행렬을 다룰 때는 효율적인 저장 방법과 계산 방법이 필요합니다.
        </Paragraph>
        <Paragraph>
          <Text strong>희소 행렬(Sparse Matrix):</Text> 희소 행렬은 대부분의 원소가 0인 행렬로, 계산할 때 0인 원소들을 무시하여 성능을 향상시킬 수 있습니다. 이를 저장하는 방식으로는 <Text strong>압축 희소 행렬 (Compressed Sparse Row, CSR)</Text> 형식이 자주 사용됩니다.
        </Paragraph>

        <Divider orientation="left">2.6 비균일 경계 조건 처리</Divider>
        <Paragraph>
          1차원 문제에서 경계 조건은 해의 존재와 유일성을 결정하는 중요한 요소입니다. 비균일 경계 조건이 주어졌을 때, 이를 처리하기 위한 수학적 접근이 필요합니다. 디리클레 경계 조건(Dirichlet boundary conditions)과 노이만 경계 조건(Neumann boundary conditions)을 혼합하여 적용할 수 있습니다.
        </Paragraph>
        <Paragraph>
          <Text strong>비균일 경계 조건:</Text> 경계에서의 값이 일정하지 않거나 외부의 영향에 의해 달라지는 경우, 이를 비균일 경계 조건이라 합니다. 예를 들어, 시간에 따라 변하는 온도 조건이나 외부 힘에 의해 변하는 조건이 이에 해당합니다.
        </Paragraph>

        <Divider orientation="left">2.7 유한 요소에서의 보간</Divider>
        <Paragraph>
          FEM에서 보간(Interpolation)은 해를 근사하기 위한 중요한 과정입니다. 1차원 문제에서 보간은 각 요소의 노드 값들을 기반으로 합니다. 이때 사용되는 기저 함수는 각 노드에서의 값을 표현하는 함수입니다. 보간을 통해 각 요소에서의 근사해를 구하고, 이를 전체 도메인에 대해 결합하여 최종 해를 얻습니다.
        </Paragraph>
        <Paragraph>
          <Text strong>유한 요소에서의 보간:</Text> 보간을 통해 구해지는 해는 주어진 노드에서의 값에 의해 결정됩니다. 이때, 기저 함수는 노드의 값이 어떻게 변하는지에 대한 정보를 제공합니다.
        </Paragraph>

        <List
          size="small"
          dataSource={[
            "보간 함수의 종류: 선형, 2차, 3차 함수",
            "보간의 정확도와 차수의 관계"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 1차원 문제를 해결하기 위한 여러 가지 연속 요소들을 다루었습니다. 선형 요소부터 고차수 요소까지, 다양한 요소들을 활용한 문제 해결 방법을 소개하고, 희소 강성 행렬 처리와 비균일 경계 조건 처리 방법도 설명하였습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default PDEFEMChapter2;
