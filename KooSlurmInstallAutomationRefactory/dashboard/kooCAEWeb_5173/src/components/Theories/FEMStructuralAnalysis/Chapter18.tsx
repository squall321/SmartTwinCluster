import React from "react";
import { Typography, Divider, List } from "antd";
import { MathJax, MathJaxContext } from "better-react-mathjax";
import ModelFormulaBox from "@components/common/ModelFormulaBox";

const { Title, Paragraph, Text } = Typography;

const Chapter18: React.FC = () => {
  return (
    <MathJaxContext>
      <div className="space-y-6">


        <Paragraph>
          본 장에서는 유한 요소 해석의 정확도와 효율성에 직접적인 영향을 미치는 메시 생성 기법과 품질 평가 방법을 다룹니다. 구조적 메시와 비구조적 메시의 차이, 자동 메시 생성 알고리즘, 요소 품질 척도, 메시 스무딩 및 개선 전략을 소개합니다.
        </Paragraph>

        <Divider orientation="left">1. 구조적 vs 비구조적 메시</Divider>
        <Paragraph>
          <Text strong>구조적 메시</Text>는 격자 형태의 정렬된 메시로, 정형적인 형상을 가지며 노드와 요소의 인덱싱이 단순합니다. 반면 <Text strong>비구조적 메시</Text>는 복잡한 형상에 유연하게 적용 가능하며 삼각형, 사면체 등 다양한 형태의 요소를 포함합니다.
        </Paragraph>

        <List
          header={<Text strong>비교 항목</Text>}
          bordered
          dataSource={[
            "구조적 메시: 메모리 효율, 빠른 어셈블리, 제한된 형상 적용",
            "비구조적 메시: 복잡한 형상 적합, 정밀한 국부 해석 가능, 어셈블리 복잡도 증가"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">2. 자동 메시 생성 기법</Divider>
        <Paragraph>
          자동 메시 생성 알고리즘은 다음과 같은 기법으로 분류됩니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "Delaunay 삼각분할: 노드 사이 거리 기반 삼각형 생성, 각도 최적화",
            "Advancing Front: 경계에서부터 요소를 확장하며 채워나감",
            "Octree 기반: 공간을 분할하여 복잡한 영역을 자동으로 메시화"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">3. 요소 품질 평가</Divider>
        <Paragraph>
          생성된 요소의 품질은 해석 정확도에 영향을 주며, 대표적인 평가 지표는 다음과 같습니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "Aspect ratio: 요소의 길이 대비 높이 비율",
            "Skewness: 이상적인 형상에서의 왜곡 정도",
            "Jacobian determinant: 변환의 국소 안정성 판단 기준"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <ModelFormulaBox
          title="Aspect Ratio 계산"
          description={
            "2D 삼각형의 경우, 가장 긴 변을 기준으로 비율 계산:"
          }
          formulas={["AR = \\\dfrac{l_{\\max}}{h_{\\min}}"]}
        />

        <Divider orientation="left">4. 메시 스무딩 및 개선</Divider>
        <Paragraph>
          메시의 품질을 향상시키기 위해 다음과 같은 후처리 기법이 사용됩니다:
        </Paragraph>
        <List
          size="small"
          dataSource={[
            "Laplacian 스무딩: 각 노드를 인접 노드의 평균 위치로 이동시킴",
            "Optimization-based smoothing: 품질 메트릭을 최소화하는 방향으로 노드 위치 조정",
            "Topological 개선: 엣지 플립(edge flipping)이나 노드 병합 등을 통한 품질 개선"
          ]}
          renderItem={(item) => <List.Item>{item}</List.Item>}
        />

        <Divider orientation="left">요약</Divider>
        <Paragraph>
          적절한 메시 생성과 품질 관리는 유한 요소 해석에서 필수적인 전처리 과정입니다. 이 장에서는 구조적/비구조적 메시의 특징, 주요 자동 생성 알고리즘, 요소 품질 척도, 메시 개선 기법 등을 학습하였습니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter18;