import React, { useState } from "react";
import MotorLevelSimulationConfigForm from "../components/MotorLevelSimulationConfigForm";
import MotorLevelResultCharts from "../components/MotorLevelResultCharts";
import { MotorLevelSimulationConfig, MotorLevelSimulationResults } from "../types/motorLevelSimulation";
import { runMotorLevelSimulation } from "../utils/motorLevelSimulation";
import { Typography, Row, Col } from "antd";
import BaseLayout from "../layouts/BaseLayout";

const { Title } = Typography;

const MotorLevelSimulationPage: React.FC = () => {
  const [results, setResults] = useState<MotorLevelSimulationResults | null>(null);

  const runSimulation = (config: MotorLevelSimulationConfig) => {
    const result = runMotorLevelSimulation(config);
    setResults(result);
  };

  return (
    <BaseLayout isLoggedIn={false}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={2}>Motor Level Vibration Simulation</Title>
        <Row gutter={16}>
          <Col span={8}>
            <MotorLevelSimulationConfigForm onRun={runSimulation} />
          </Col>
          <Col span={16}>
            {results && <MotorLevelResultCharts results={results} />}
          </Col>
        </Row>
      </div>
    </BaseLayout>
  );
};

export default MotorLevelSimulationPage;
