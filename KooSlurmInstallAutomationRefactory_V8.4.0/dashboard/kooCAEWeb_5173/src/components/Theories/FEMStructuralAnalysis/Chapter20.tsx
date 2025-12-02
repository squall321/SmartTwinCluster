import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter20: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 판(plates)과 쉘(shells) 구조의 유한 요소 해석을 위한 이론과 수치 기법을 소개합니다.
          얇은 판의 Kirchhoff-Love 이론과 두꺼운 판/쉘에 적합한 Mindlin-Reissner 이론을 비교하며,
          전단 잠김(shear locking) 현상과 그 해결책, 쉘 요소에서의 수직 방향 보간 함수 사용 및 고차 요소의 필요성 등을 다룹니다.
        </Paragraph>

        <Divider orientation="left">1. Kirchhoff-Love vs. Mindlin-Reissner</Divider>
        <Paragraph>
          <Text strong>Kirchhoff-Love 판 이론</Text>은 매우 얇은 판 구조에 적합하며, 수직 단면이 항상 평면으로 유지된다는 가정을 따릅니다.
          반면, <Text strong>Mindlin-Reissner 이론</Text>은 단면 회전을 허용하여 전단 효과를 반영하므로 두꺼운 판/쉘에 적합합니다.
        </Paragraph>

        <ModelFormulaBox
          title="Mindlin 전단 변형"
          description={
            <>
              Mindlin-Reissner 이론에서는 전단 변형률이 다음과 같이 정의되며,
              수직 변위 <MathJax inline>{"\( w \)"}</MathJax>와 회전 <MathJax inline>{"\( \theta_x, \theta_y \)"}</MathJax>를 포함합니다.
            </>
          }
          formulas={["\\gamma_{xz} = \\theta_x - \\frac{\\partial w}{\\partial x}", "\\gamma_{yz} = \\theta_y - \\frac{\\partial w}{\\partial y}"]}
        />

        <Divider orientation="left">2. 전단 잠김 (Shear Locking)</Divider>
        <Paragraph>
          얇은 판에서 Mindlin 요소를 사용하면 전단 변형률이 과도하게 구속되어 <Text strong>전단 잠김</Text>이 발생할 수 있습니다.
          이를 완화하기 위해 <Text strong>감쇠 보간(reduced integration)</Text>, <Text strong>Selective Reduced Integration</Text>, <Text strong>MITC</Text> 요소 등이 사용됩니다.
        </Paragraph>

        <Divider orientation="left">3. 쉘 요소 모델링</Divider>
        <Paragraph>
          쉘 요소는 곡면 구조를 모델링하기 위한 얇은 2차원 요소로, 곡률, 회전, 전단 등을 반영합니다.
          얇은 쉘에서는 Kirchhoff 조건이, 두꺼운 쉘에서는 Mindlin 조건이 사용됩니다.
        </Paragraph>

        <List
          size="small"
          header={<Text strong>쉘 요소 설계 고려사항</Text>}
          dataSource={[
            "곡면 상의 변형률 정의",
            "회전 자유도 처리",
            "전단 잠김 방지 기법 적용",
            "고차 보간 함수 사용을 통한 정밀도 향상"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">4. 고차 쉘 요소</Divider>
        <Paragraph>
          수직 방향 보간 함수와 고차 쉘 요소는 곡률이 크거나 전단 변형이 큰 구조에 유리합니다.
          이때, 적절한 수직 보간 함수 선택이 정확도와 수렴성에 영향을 줍니다.
        </Paragraph>

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          본 장에서는 Kirchhoff-Love와 Mindlin-Reissner 판/쉘 이론의 차이,
          전단 잠김 현상 및 그 완화 방법, 쉘 요소에서의 설계 요소와 고차 보간 함수의 중요성을 다루었습니다.
          다양한 실전 구조물에 따라 적절한 판/쉘 이론의 선택이 필수적입니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter20;
