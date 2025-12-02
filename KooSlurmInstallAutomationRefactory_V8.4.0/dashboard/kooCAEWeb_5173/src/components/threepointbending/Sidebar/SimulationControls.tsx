import React from "react";
import { Button, Space, Spin } from "antd";

interface Props {
  onRun: () => void;
  onReset: () => void;
  loading: boolean;
}

const SimulationControls: React.FC<Props> = ({
  onRun,
  onReset,
  loading
}) => (
  <>
    <Space style={{ marginTop: 16 }}>
      <Button
        type="primary"
        onClick={onRun}
        disabled={loading}
      >
        Run Simulation
      </Button>
      <Button
        danger
        onClick={onReset}
        disabled={loading}
      >
        Reset
      </Button>
    </Space>
    {loading && (
      <div style={{ marginTop: 16 }}>
        <Spin tip="Running simulation..." />
      </div>
    )}
  </>
);

export default SimulationControls;
