import React from "react";
import { Form, InputNumber } from "antd";
import { LoadConfig } from "../../../types/threepointbending";

interface Props {
  loadConfig: LoadConfig;
  setLoadConfig: (cfg: LoadConfig) => void;
}

const LoadPanel: React.FC<Props> = ({
  loadConfig,
  setLoadConfig
}) => {
  const handleChange = (key: keyof LoadConfig, value: number) => {
    setLoadConfig({
      ...loadConfig,
      [key]: value
    });
  };

  return (
    <>
      <Form.Item label="Max Load (N)">
        <InputNumber
          value={loadConfig.maxLoad}
          onChange={(v) => handleChange("maxLoad", v || 0)}
          style={{ width: "100%" }}
        />
      </Form.Item>
      <Form.Item label="Step (N)">
        <InputNumber
          value={loadConfig.step}
          onChange={(v) => handleChange("step", v || 0)}
          style={{ width: "100%" }}
        />
      </Form.Item>
    </>
  );
};

export default LoadPanel;
