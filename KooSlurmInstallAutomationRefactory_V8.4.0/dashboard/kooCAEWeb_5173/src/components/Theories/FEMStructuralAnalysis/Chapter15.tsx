import React from "react";
import { Typography, Divider, Row, Col, Card } from "antd";
import ModelFormulaBox from "@components/common/ModelFormulaBox";
import { MathJax, MathJaxContext } from "better-react-mathjax";

const { Title, Paragraph, Text } = Typography;

const Chapter15: React.FC = () => {
  return (
    <MathJaxContext
      version={3}
      config={{
        tex: {
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
          고성능 컴퓨팅(High-Performance Computing, HPC)은 대규모 유한 요소 해석을 빠르고 효율적으로 수행하기 위한 핵심 기술입니다. 이 장에서는 병렬 계산 전략, 분산 메모리 아키텍처, 도메인 분할 기법 및 관련 툴(MPI, OpenMP, GPU 가속 등)에 대해 설명합니다.
        </Paragraph>

        <Divider orientation="left">1. FEM과 HPC의 필요성</Divider>
        <Paragraph>
          수백만 개 이상의 자유도를 가지는 문제에서 FEM 해석은 막대한 메모리와 연산 자원을 요구합니다. 따라서 효율적인 분산/병렬 처리가 필수입니다.
        </Paragraph>

        <Divider orientation="left">2. 병렬화 전략</Divider>
        <Paragraph>
          FEM에서의 병렬화는 크게 두 가지 방식으로 구분됩니다:
        </Paragraph>
        <ul>
          <li><Text strong>분산 메모리 병렬화:</Text> MPI를 이용하여 여러 노드 간 데이터를 분산</li>
          <li><Text strong>공유 메모리 병렬화:</Text> OpenMP를 이용하여 단일 노드 내 CPU 코어를 활용</li>
        </ul>

        <Divider orientation="left">3. 도메인 분할</Divider>
        <Paragraph>
          전체 해석 영역을 여러 개의 하위 도메인으로 분할하여 각각 병렬 처리합니다. 이때 각 도메인은 독립적으로 요소 조립 및 해를 수행하고, 경계에서 데이터를 교환합니다.
        </Paragraph>

        <ModelFormulaBox
        title="행렬 분할"
        description="전체 행렬 \\( \\mathbf{K} \\)를 블록 구조로 다음과 같이 분할합니다:"
        formulas={[
            "\\mathbf{K} = \\begin{bmatrix} \\mathbf{K}_{11} & \\mathbf{K}_{12} \\\\ \\mathbf{K}_{21} & \\mathbf{K}_{22} \\end{bmatrix}"
        ]}
        />


        <Divider orientation="left">4. MPI 기반 병렬 FEM</Divider>
        <Paragraph>
          MPI는 분산 메모리 환경에서 각 프로세스 간 통신을 관리하는 표준입니다. 각 도메인별 요소 조립 및 경계 노드의 데이터 교환은 다음과 같은 순서로 수행됩니다:
        </Paragraph>
        <ol>
          <li>도메인 분할 및 요소 분배</li>
          <li>로컬 요소 행렬 조립</li>
          <li>경계 정보 MPI 통신으로 교환</li>
          <li>전역 시스템 솔버 수행</li>
        </ol>

        <Divider orientation="left">5. GPU 가속 FEM</Divider>
        <Paragraph>
          GPU는 대규모 반복 계산에 적합하며, 행렬 조립 및 솔버 단계에서 병렬 처리 성능을 극대화할 수 있습니다. CUDA, OpenCL 또는 Kokkos 기반의 라이브러리 사용이 일반적입니다.
        </Paragraph>

        <Divider orientation="left">6. 라이브러리 및 프레임워크</Divider>
        <ul>
          <li><Text strong>Trilinos:</Text> 병렬 선형/비선형 솔버 및 FEM 지원</li>
          <li><Text strong>PETSc:</Text> 대규모 선형 시스템 솔버 및 병렬 벡터/행렬 지원</li>
          <li><Text strong>MFEM:</Text> MPI 및 GPU 가속 FEM 프레임워크</li>
          <li><Text strong>deal.II:</Text> OpenMP 및 MPI 기반 고차 FEM 라이브러리</li>
        </ul>

        <Divider orientation="left">7. 성능 최적화</Divider>
        <Paragraph>
          <ul>
            <li>효율적인 도메인 분할 (METIS, ParMETIS 등)</li>
            <li>통신량 최소화 및 계산/통신 중첩</li>
            <li>캐시 최적화 및 반복자 기반 데이터 접근</li>
          </ul>
        </Paragraph>

        <Divider orientation="left">8. 요약</Divider>
        <Paragraph>
          FEM의 확장성과 효율성 확보를 위해서는 HPC 기술의 통합이 필수입니다. 병렬화 전략의 적절한 선택, 도메인 분할 및 MPI/GPU 등의 기술 활용은 산업 및 연구 전반에서 실질적인 성능 향상을 가능하게 합니다.
        </Paragraph>
      </div>
    </MathJaxContext>
  );
};

export default Chapter15;