import React, { useState } from "react";
import { Layout, Form, message } from "antd";
import DeformationModelPanel from "./Sidebar/DeformationModelPanel";
import MaterialModelPanel from "./Sidebar/MaterialModelPanel";
import GeometryPanel from "./Sidebar/GeometryPanel";
import LoadPanel from "./Sidebar/LoadPanel";
import AnalysisConditionPanel from "./Sidebar/AnalysisConditionPanel";
import SimulationControls from "./Sidebar/SimulationControls";
import LoadDeflectionChart from "./Charts/LoadDeflectionChart";
import MomentCurvatureChart from "./Charts/MomentCurvatureChart";
import UdlLoadDistributionChart from "./Charts/UdlLoadDistributionChart";
import DeflectedShapeAnimation from "./Animation/DeflectedShapeAnimation";
import ResultTable from "./DataTable/ResultTable";

import {
  DeformationModel,
  MaterialModel,
  MaterialParams,
  BeamGeometry,
  LoadConfig,
  SimulationResult,
  SupportCondition
} from "../../types/threepointbending";

import { runSimulation } from "../../utils/threepointbending/simulation";
import ModelFormulaBox from "../common/ModelFormulaBox";

const { Sider, Content } = Layout;

const ThreePointBendingApp: React.FC = () => {
  const [deformationModel, setDeformationModel] =
    useState<DeformationModel>("Small");

  const [materialModel, setMaterialModel] =
    useState<MaterialModel>("LinearElastic");

  const [materialParams, setMaterialParams] =
    useState<MaterialParams>({
      model: "LinearElastic",
      params: { E: 200000 }
    });

  const [geometry, setGeometry] = useState<BeamGeometry>({
    span: 200,
    height: 10,
    width: 10
  });

  const [loadConfig, setLoadConfig] = useState<LoadConfig>({
    maxLoad: 100,
    step: 5
  });

  const [supportCondition, setSupportCondition] =
    useState<SupportCondition>("SimplySupported");

  const [loadType, setLoadType] = useState<"Point" | "UDL">("Point");
  const [loadPosition, setLoadPosition] = useState<number>(geometry.span / 2);
  const [integrationSteps, setIntegrationSteps] = useState<number>(100);

  const [simulationResult, setSimulationResult] =
    useState<SimulationResult | null>(null);

  const [loading, setLoading] = useState<boolean>(false);

  const handleRunSimulation = () => {
    if (
      deformationModel === "Small" &&
      materialModel !== "LinearElastic"
    ) {
      message.error(
        "Plasticity models are not supported for Small Deformation!"
      );
      return;
    }

    try {
      setLoading(true);

      const analysis = {
        loadType,
        loadPosition,
        integrationSteps,
        supportCondition
      };

      const result = runSimulation(
        geometry,
        loadConfig,
        materialParams,
        deformationModel,
        analysis
      );

      setSimulationResult(result);
      message.success("Simulation completed!");
    } catch (error: any) {
      message.error(error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleReset = () => {
    setSimulationResult(null);
  };

  return (
    <Layout style={{ height: "100vh" }}>
      <Sider
        width={320}
        style={{
          background: "#fff",
          padding: "16px",
          overflow: "auto",
          borderRight: "1px solid #f0f0f0"
        }}
      >
        <Form layout="vertical">
        <DeformationModelPanel
            deformationModel={deformationModel}
            setDeformationModel={setDeformationModel}
        />

        {/* 수식 박스 추가 */}
        {deformationModel === "Small" && (
            <ModelFormulaBox
            title="소변형 해석 (Small Deformation)"
            description="소변형에서는 곡률과 처짐의 관계가 선형이며, 탄성 범위 내 해석이 가능합니다."
            formulas={[
                "\\kappa = \\frac{d^2 w}{dx^2}",
                "M = E \\cdot I \\cdot \\kappa",
                "\\delta = \\frac{P \\cdot a \\cdot b (L^2 - a b)}{3 L E I}"
            ]}
            />
        )}

        {deformationModel === "Large" && (
            <ModelFormulaBox
            title="대변형 해석 (Large Deformation)"
            description="대변형에서는 곡률이 비선형 관계를 따르며, 수치 적분으로 휨 모멘트를 구합니다."
            formulas={[
                "\\kappa = \\frac{\\frac{d^2 w}{dx^2}}{\\sqrt{1 + \\left( \\frac{dw}{dx} \\right)^2 }}",
                "M = \\int_{-h/2}^{h/2} \\sigma(\\varepsilon) \\cdot y \\, dy",
                "\\varepsilon(y) = \\kappa \\cdot y"
            ]}
            />
        )}

        <MaterialModelPanel
            materialModel={materialModel}
            setMaterialModel={setMaterialModel}
            materialParams={materialParams}
            setMaterialParams={setMaterialParams}
        />


          <GeometryPanel
            geometry={geometry}
            setGeometry={setGeometry}
          />

          <LoadPanel
            loadConfig={loadConfig}
            setLoadConfig={setLoadConfig}
          />

          <AnalysisConditionPanel
            loadType={loadType}
            setLoadType={setLoadType}
            loadPosition={loadPosition}
            setLoadPosition={setLoadPosition}
            integrationSteps={integrationSteps}
            setIntegrationSteps={setIntegrationSteps}
            supportCondition={supportCondition}
            setSupportCondition={setSupportCondition}
            span={geometry.span}
          />

          <SimulationControls
            onRun={handleRunSimulation}
            onReset={handleReset}
            loading={loading}
          />
        </Form>
      </Sider>

      <Layout>
        <Content
          style={{
            padding: "24px",
            background: "#f9f9f9",
            height: "100vh",
            overflow: "auto"
          }}
        >
          {loading ? (
            <div
              style={{
                textAlign: "center",
                marginTop: "30vh"
              }}
            >
              Loading...
            </div>
          ) : simulationResult ? (
            <>
              {loadType === "UDL" && (
                <UdlLoadDistributionChart
                  span={geometry.span}
                  load={loadConfig.maxLoad}
                />
              )}

              <LoadDeflectionChart
                loads={simulationResult.loads}
                deflections={simulationResult.deflections}
              />

              <MomentCurvatureChart
                curvatures={simulationResult.curvatures}
                moments={simulationResult.moments}
              />

              <DeflectedShapeAnimation
                shapes={simulationResult.shapes}
                loads={simulationResult.loads}
              />

              <ResultTable result={simulationResult} />
            </>
          ) : (
            <div
              style={{
                textAlign: "center",
                marginTop: "30vh"
              }}
            >
              <h2>Run the simulation to see results</h2>
            </div>
          )}
        </Content>
      </Layout>
    </Layout>
  );
};

export default ThreePointBendingApp;
