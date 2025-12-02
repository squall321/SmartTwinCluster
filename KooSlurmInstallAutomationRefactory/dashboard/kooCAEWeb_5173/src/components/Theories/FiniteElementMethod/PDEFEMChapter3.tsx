import React from 'react';
import { Typography, Divider, List } from 'antd';
import { MathJax, MathJaxContext } from 'better-react-mathjax';
import ModelFormulaBox from '@components/common/ModelFormulaBox';

const { Title, Paragraph, Text } = Typography;

const Chapter3: React.FC = () => (
  <MathJaxContext>
    <Typography>
      <Title level={1}>제3장. 약한 형식, 함수 공간 및 갈레르킨 방법</Title>

      <Title level={2}>3.1 약한 형식의 도입</Title>
      <Paragraph>
        고전적 해가 존재하지 않거나, 매끄럽지 않은 경우에도 PDE 문제를 해석적으로 다룰 수 있도록 하기 위해 약한 해의 개념이 필요합니다. 이를 위해 방정식을 시험 함수와 함께 적분 형태로 변형합니다.
      </Paragraph>
      <ModelFormulaBox
        title="약한 형식의 도입"
        description={<><Text>다음과 같은 이차 미분 방정식을 고려합니다:</Text></>}
        formulas={["-u''(x) = f(x), \\quad 0 < x < 1, \\quad u(0) = u(1) = 0"]}
      />
      <Paragraph>
        시험 함수 <MathJax inline>\(v(x)\)</MathJax>를 곱하고 적분한 뒤 부분적분하면:
        <ModelFormulaBox
         title="부분 적분 공식 적용하면"
         description={""}
         formulas={["\\int_0^1 u'(x)v'(x)dx = \\int_0^1 f(x)v(x)dx\\"]}
        />
        이와 같이 바뀌며, 이는 약한 해 정의로 이어집니다.
      </Paragraph>

      <Title level={3}>정의 3.1 (약한 해)</Title>
      <Paragraph>
        함수 <MathJax inline>\(u \in H_0^1(0,1)\)</MathJax>가 위의 적분식을 모든 <MathJax inline>\(v \in H_0^1(0,1)\)</MathJax>에 대해 만족하면 약한 해라고 합니다.
      </Paragraph>

      <Title level={3}>정리 3.1 (Lax–Milgram 정리)</Title>
      <Paragraph>
        힐베르트 공간 <MathJax inline>\(V\)</MathJax> 위의 쌍선형 형식 <MathJax inline>\(a(u,v)\)</MathJax>가 유계성과 강한 타원 조건을 만족하고, 선형 함수 <MathJax inline>\(f \in V'\)</MathJax>가 주어지면 다음 문제는 유일한 해를 갖습니다:
      </Paragraph>
      <Paragraph>
        <ModelFormulaBox
         title="Lax–Milgram 정리"
         description={""}
         formulas={["a(u,v) = f(v), \\quad \\forall v \\in V"]}
        />
      </Paragraph>

      <Title level={2}>3.2 함수 공간</Title>
      <Paragraph>
        약한 형식을 정의하려면 함수가 속할 공간이 필요합니다. 대표적인 공간은 소볼레프 공간 <MathJax inline>\(H^1(\Omega)\)</MathJax>이며, 그 부분공간인 <MathJax inline>\(H_0^1(\Omega)\)</MathJax>는 경계에서 0이 되는 함수들의 공간입니다.
      </Paragraph>
      <Paragraph>
        <MathJax inline>\(H_0^1\)</MathJax>는 다음 내적과 노름으로 힐베르트 공간이 됩니다:
        <ModelFormulaBox
         title="내적과 노름"
         description={""}
         formulas={["(u,v)_E := \\int_\\Omega \\nabla u \\cdot \\nabla v dx", "\\|u\\|_E := \\sqrt{(u,u)_E}"]}
        />
      </Paragraph>

      <Title level={2}>3.3 갤러킨 방법</Title>
      <Paragraph>
        무한 차원의 약한 형식을 유한 차원에서 근사하기 위한 방법이 갤러킨 방법입니다. 유한 차원 부분공간 <MathJax inline>\(V_h \subset V\)</MathJax>를 선택하여 다음 문제를 풉니다:
      </Paragraph>
      <Paragraph>
        <ModelFormulaBox
         title="갤러킨 방법"
         description={""}
         formulas={["\\text{Find } u_h \\in V_h \\text{ such that } a(u_h, v_h) = f(v_h), \\quad \\forall v_h \\in V_h"]}
        />
      </Paragraph>
      <Paragraph>
        근사 해는 기저 함수로 전개되며, 연립 선형 방정식으로 계산됩니다. 오차는 다음과 같은 Céa의 보정 이론에 의해 평가됩니다:
      </Paragraph>
      <Paragraph>
        <ModelFormulaBox
         title="Céa의 보정 이론"
         description={""}
         formulas={["\\|u - u_h\\|_E \\le \\frac{\\gamma}{\\alpha} \\inf_{w \\in V_h} \\|u - w\\|_E"]}
        />
      </Paragraph>

      <Divider />
      <Paragraph type="secondary">
        ※ 위 내용은 책 "Partial Differential Equations and the Finite Element Method" Chapter 3 기반 요약입니다.
      </Paragraph>
    </Typography>
  </MathJaxContext>
);

export default Chapter3;
