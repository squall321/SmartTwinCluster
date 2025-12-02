import React from "react";
import { Typography, Divider, Row, Col, Card, List } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter14: React.FC = () => {
  return (
    <MathJaxContext
      version={3}
      config={{
        tex: {
          inlineMath: [["$", "$"], ["\\(", "\\)"]],
          displayMath: [["$$", "$$"], ["\\[", "\\]"]],
        },
      }}
    >
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 계산 비용을 절감하고 실시간 해석을 가능하게 하기 위한 {
            "Reduced-Order Modeling (ROM)"
          } 기법을 소개합니다. 특히 복잡한 유한 요소 모델의 동작을 저차원 모델로 근사하여 빠른 계산을 가능하게 합니다.
        </Paragraph>

        <Divider orientation="left">1. ROM의 필요성</Divider>
        <Paragraph>
          대규모 FEM 모델은 해석 시간이 매우 오래 걸릴 수 있습니다. 설계 최적화, 파라미터 탐색, 디지털 트윈 등의 응용에서는 실시간 성능이 필요하며, 이를 위해 모델 차수를 줄이는 기법이 필수적입니다.
        </Paragraph>

        <List
          size="small"
          header={<Text strong>대표적 응용 분야</Text>}
          bordered
          dataSource={[
            "디지털 트윈 (Digital Twin)",
            "설계 최적화 (Design Optimization)",
            "모델 기반 제어 (Model-Based Control)",
            "민감도 분석 및 불확실성 정량화",
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">2. 모드 기반 모델 감소 (Modal Reduction)</Divider>
        <Paragraph>
          구조 진동 문제에서는 고유진동 형상을 활용하여 동적 응답을 저차원 공간으로 사영할 수 있습니다.
        </Paragraph>

        <ModelFormulaBox
          title="고전적 Modal Superposition"
          description="구조 해석 결과를 모드 형상의 선형 조합으로 표현"
          formulas={["u(x,t) \\approx \\sum_{i=1}^{r} q_i(t) \\phi_i(x)"]}
        />

        <Paragraph>
          여기서 <MathJax inline>{"\\( \\phi_i(x) \\)"}</MathJax>는 <MathJax inline>{"\\( i \\)"}</MathJax>번째 고유모드이며, <MathJax inline>{"\\( q_i(t) \\)"}</MathJax>는 시간에 따른 계수입니다. 일반적으로 몇 개의 우세한 모드만으로도 전체 응답을 잘 근사할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">3. POD (Proper Orthogonal Decomposition)</Divider>
        <Paragraph>
          POD는 해의 스냅샷 데이터를 기반으로 직교 기저를 추출하여 모델을 저차원화하는 대표적인 데이터 기반 기법입니다.
        </Paragraph>

        <ModelFormulaBox
          title="스냅샷 행렬의 특이값 분해"
          description="스냅샷 행렬을 SVD로 분해하여 주요 모드를 추출"
          formulas={["\\mathbf{X} = \\mathbf{U} \\mathbf{\\Sigma} \\mathbf{V}^T"]}
        />

        <Paragraph>
          상위 <MathJax inline>{"\\( r \\)"}</MathJax>개의 특이값에 해당하는 <MathJax inline>{"\\( \\mathbf{U}_r \\)"}</MathJax>를 이용하여 해를 근사합니다:
        </Paragraph>

        <ModelFormulaBox
        title="POD 기반 근사"
        description={
            <>
            상위 <MathJax inline>{"\\( r \\)"}</MathJax>개의 특이값에 해당하는{" "}
            <MathJax inline>{"\\( \\mathbf{U}_r \\)"}</MathJax>를 이용하여 해를 근사합니다:
            </>
        }
        formulas={["\\mathbf{u}(t) \\approx \\mathbf{U}_r \\mathbf{q}(t)"]}
        />



        <Divider orientation="left">4. Galerkin Projection</Divider>
        <Paragraph>
          유한 요소 방정식을 POD 기저에 사영하여 저차원 시스템으로 변환합니다.
        </Paragraph>

        <ModelFormulaBox
          title="Galerkin 사영"
          description="유한 요소 방정식을 POD 기저에 사영하여 저차원 시스템으로 변환"
          formulas={["\\mathbf{U}_r^T \\mathbf{K} \\mathbf{U}_r \\mathbf{q} = \\mathbf{U}_r^T \\mathbf{F}"]}
        />

        <Paragraph>
          이 방정식은 저차원 <MathJax inline>{"\\( r \\times r \\)"}</MathJax> 시스템으로 해결 가능하며, 계산량을 크게 줄입니다.
        </Paragraph>

        <Divider orientation="left">5. 비선형 시스템에서의 ROM</Divider>
        <Paragraph>
          비선형 항은 단순히 선형 사영으로는 처리하기 어려우며, DEIM(Discrete Empirical Interpolation Method) 등의 보조 기법이 필요합니다.
        </Paragraph>

        <ModelFormulaBox
          title="DEIM 근사"
          description="비선형 항을 일부 샘플링 점에서 근사"
          formulas={["\\mathbf{f}(\\mathbf{u}) \\approx \\mathbf{V}_m (\\mathbf{P}^T \\mathbf{V}_m)^{-1} \\mathbf{P}^T \\mathbf{f}(\\mathbf{u})"]}
        />

        <Paragraph>
          여기서 <MathJax inline>{"\\( \\mathbf{V}_m \\)"}</MathJax>은 비선형 항에 대한 POD 기저, <MathJax inline>{"\\( \\mathbf{P} \\)"}</MathJax>는 샘플링 선택 행렬입니다.
        </Paragraph>

        <Divider orientation="left">6. 요약</Divider>
        <Paragraph>
          Reduced-Order Modeling은 고해상도 FEM 모델의 계산 부담을 줄이고 실시간 해석이 필요한 다양한 산업 응용에서 핵심적인 역할을 합니다. 본 장에서는 Modal Reduction, POD, Galerkin 사영, DEIM 등을 포함한 대표적 기법들을 소개하였습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter14;
