import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const PDEFEMChapter1: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">
        <Title level={2}>제 1 장: 편미분 방정식 개관</Title>

        <Divider orientation="left">1.1 선택된 일반적 속성</Divider>
        <Paragraph>
          편미분 방정식(PDE)은 자연에서 많은 물리적 과정을 설명하는 중요한 도구입니다. 이 방정식은 물리적 양들이 시간과 공간에 따라 어떻게 변하는지를 묘사하며, 대부분의 경우 정확한 해를 구하는 것이 어렵습니다. 따라서, PDE의 해를 구하는 수치적 접근이 필요합니다. 이 장에서는 편미분 방정식의 기본적인 성질과 분류 방법을 다룹니다.
        </Paragraph>
        <Paragraph>
          <Text strong>정의 1.1 (타원형·포물형·쌍곡형 방정식):</Text> 편미분 방정식은 일반적으로 타원형, 포물형, 쌍곡형으로 분류됩니다. 이러한 분류는 방정식의 계수행렬 $A(x)$의 성질에 따라 결정됩니다. 각 분류는 물리적 문제에서의 해석적 의미를 갖습니다.
        </Paragraph>
        <List>
          <List.Item>
            <Text strong>타원형 (Elliptic):</Text> 모든 고유값이 양수인 경우, 해당 방정식은 시스템이 <Text strong>정적</Text> 상태에 있을 때 나타나는 문제를 설명합니다. 예를 들어, 전기장 분포나 열전달 문제와 같은 평형 상태 문제입니다.
          </List.Item>
          <List.Item>
            <Text strong>포물형 (Parabolic):</Text> 시간에 따른 진화를 설명하는 방정식으로, 시간이 지남에 따라 최종적인 평형 상태에 도달하는 문제를 모델링합니다. 예를 들어, 열전도 문제는 포물형 PDE로 모델링됩니다.
          </List.Item>
          <List.Item>
            <Text strong>쌍곡형 (Hyperbolic):</Text> 파동이나 정보의 전파를 설명하는 방정식입니다. 쌍곡형 PDE는 일반적으로 파동 방정식과 같은 동적 문제를 설명합니다.
          </List.Item>
        </List>

        <Divider orientation="left">1.2 하다마르의 잘 제기된 문제</Divider>
        <Paragraph>
          <Text strong>정의 1.2 (하다마르의 잘 제기된 문제):</Text> PDE 경계값 문제(또는 초기-경계값 문제)가 <Text strong>잘 제기되었다 (well-posed)</Text>고 할 수 있는 조건은 다음과 같습니다.
        </Paragraph>
        <List>
          <List.Item>
            <Text strong>해가 존재하고 유일하다.</Text>
          </List.Item>
          <List.Item>
            <Text strong>해가 주어진 조건에 대해 연속적으로 의존한다.</Text>
            (입력 데이터에 작은 변화가 있으면, 해 역시 연속적으로 변한다는 조건)
          </List.Item>
        </List>
        <Paragraph>
          잘 제기된 문제는 물리적으로 안정적이고, 수치적으로도 근사 해를 구할 수 있습니다. 반면, 부적절하게 제기된 문제는 미세한 변화에도 해가 크게 변할 수 있습니다. 이로 인해 실용적인 문제 해결에 어려움을 겪을 수 있습니다.
        </Paragraph>
        <Paragraph>
          <Text strong>주석 1.1 (역문제의 부정칙성):</Text> 역문제는 잘 제기된 문제와 달리, 일반적으로 ill-posed합니다. 예를 들어, 열전달 문제를 역으로 계산하면 작은 오차가 크게 증폭될 수 있습니다.
        </Paragraph>

        <Divider orientation="left">1.3 타원형 방정식의 예</Divider>
        <Paragraph>
          <Text strong>예제 1.1 (타원형 PDE – 전기 퍼텐셜 방정식):</Text> 전하 밀도 분포 <MathJax inline>{"\\(\\rho(x)\\)"}</MathJax>가 주어졌을 때, 전기 퍼텐셜 <MathJax inline>{"\\(\\phi(x)\\)"}</MathJax>는 다음과 같은 포아송 방정식을 만족합니다:
        </Paragraph>
        <Paragraph>
          이 방정식은 타원형 PDE로, 전기 퍼텐셜은 정적 문제에 해당합니다. 해의 유일성을 보장하려면 경계 조건이 필요합니다. 예를 들어, 전위가 무한원점에서 0이 되도록 설정할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">1.4 포물형 방정식의 예</Divider>
        <Paragraph>
          <Text strong>예제 1.2 (포물형 PDE – 열전달 방정식):</Text> 열전달 문제는 포물형 PDE로, 온도의 시간에 따른 변화를 설명합니다. 열전도도, 밀도, 비열 등의 물질 특성이 일정할 때, 온도 분포 <MathJax inline>{"\\(\\Theta(x,t)\\)"}</MathJax>는 다음과 같은 열전달 방정식을 따릅니다:
        </Paragraph>
        <MathJax>{"\\[ \\rho c \\frac{\\partial \\Theta(x,t)}{\\partial t} - k \\Delta \\Theta(x,t) = q(x) \\,. \\]"}</MathJax>
        <Paragraph>
          이 방정식은 시간에 따른 온도의 변화를 설명하는 포물형 PDE입니다. 여기서 해의 존재와 유일성을 보장하기 위해 초기 온도 분포와 경계에서의 온도 조건이 필요합니다.
        </Paragraph>

        <Divider orientation="left">1.5 쌍곡형 방정식의 예</Divider>
        <Paragraph>
          <Text strong>예제 1.3 (쌍곡형 PDE – 파동 방정식):</Text> 쌍곡형 PDE는 파동이나 정보의 전파를 다룹니다. 예를 들어, 음파의 전파를 모델링하는 파동 방정식은 다음과 같습니다:
        </Paragraph>
        <MathJax>{"\\[ \\frac{\\partial^2 p(x,t)}{\\partial t^2} - a^2 \\Delta p(x,t) = 0 \\,. \\]"}</MathJax>
        <Paragraph>
          이 방정식은 매질 내에서 파동이 전파되는 현상을 설명합니다. 파동 방정식은 경계와 초기 조건에 의해 결정되며, 적절한 경계 조건을 제공해야 해가 존재하고 유일함을 보장할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">1.6 해의 존재와 유일성 이론</Divider>
        <Paragraph>
          <Text strong>정리 1.1 (Lax-Milgram 레마):</Text> 타원형 PDE에서 해의 존재와 유일성을 보장하는 중요한 이론 중 하나가 Lax-Milgram 레마입니다. 이 레마에 따르면, 적절한 조건 하에 <Text strong>에너지 내적</Text>을 사용하여 유일한 해를 찾을 수 있습니다.
        </Paragraph>
        <ModelFormulaBox
          title="Lax-Milgram Lemma"
          description={<><Text strong>적절한 조건을 만족하는 문제는 유일한 해를 갖는다:</Text></>}
          formulas={[
            "A(u,v) = f(v), \\quad \\text{for all } v, u \\in V"
          ]}
        />

        <Paragraph>
          이러한 이론적 배경을 바탕으로, 유한 요소법(FEM)을 사용한 수치적 접근에서는 이론적으로 존재하고 유일한 해를 근사하는 방법을 제시할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 편미분 방정식의 기본적인 성질, 분류, 해의 존재 및 유일성에 대한 이론을 다뤘습니다. PDE의 종류에 따른 해석적 접근을 통해 각 문제의 특성에 맞는 해결 방법을 제시할 수 있음을 보였습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default PDEFEMChapter1;
