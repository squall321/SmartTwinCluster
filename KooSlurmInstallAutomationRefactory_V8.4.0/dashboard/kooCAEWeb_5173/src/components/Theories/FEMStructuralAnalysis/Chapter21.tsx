import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter21: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 곡면이나 곡률을 갖는 도메인 위에서 정의된 편미분 방정식(PDE)의 유한 요소 해석에 대해 다룹니다. 생체 구조, 얇은 쉘, 지오메트릭 웨이브 등 다양한 응용 분야에서 곡면상의 해석이 필요하며, 이를 위해 매니폴드 기반의 요소 정의가 사용됩니다.
        </Paragraph>

        <Divider orientation="left">1. 곡면 위의 PDE</Divider>
        <Paragraph>
          도메인이 평면이 아닌 곡면(2D 매니폴드)일 경우, 라플라시안 등의 미분 연산은 Riemannian geometry 기반의 정의로 확장되어야 합니다. 예: 지오메트릭 열 확산, 파동 방정식, 커튼 곡면 진동 등.
        </Paragraph>

        <Divider orientation="left">2. 매니폴드에서의 FEM 정의</Divider>
        <Paragraph>
          요소 형상 함수와 적분은 곡면에 정의된 좌표계(예: local tangent frame)를 기준으로 구성됩니다. 매니폴드 위의 FEM은 일반적으로 다음 조건을 만족해야 합니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "기저벡터는 국소 접평면에 위치해야 함",
            "면적 요소 및 적분은 곡률 반영 필요",
            "방향성(법선)의 일관성 확보",
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">3. 곡률 적응 메시 및 Embedded Domain</Divider>
        <Paragraph>
          곡면 영역은 보통 3D 볼륨 메시에 포함되어 있으며, level set 또는 파라메트릭 표현으로 정의됩니다. 다음과 같은 기법들이 사용됩니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "곡률 기반 메시 리파인먼트: 곡률 큰 영역에 요소 밀도 증가",
            "Implicit surface FEM: Level set 기반 정의",
            "Embedded domain method: 곡면을 볼륨 메시 내에 내장하여 계산",
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">4. 주요 수식</Divider>
        <ModelFormulaBox
          title="곡면 라플라시안"
          description={
            "곡면상의 스칼라장에 대해 정의되는 Laplace-Beltrami 연산자 (Riemannian 라플라시안):"
          }
          formulas={["\\Delta_g u = \\text{div}_g( \\nabla_g u )"]}
        />

        <ModelFormulaBox
          title="곡면 위의 적분"
          description={
            "곡면 영역에서의 적분은 곡률에 따라 변화하는 면적 요소를 포함합니다:"
          }
          formulas={["\\int_{\Gamma} f(x) \, dS = \\int_{\Omega} f(x(\\xi)) \, |J(\\xi)| \, d\\xi"]}
        />

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          곡면 도메인 위의 FEM은 기하학적으로 복잡한 대상의 정밀 해석을 가능하게 합니다. Riemannian geometry 기반 연산자 정의, 곡률 적응 메시, 암묵적 표현 기법 등을 통해 곡면 PDE를 정확히 해석할 수 있습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter21;