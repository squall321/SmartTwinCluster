import React from "react";
import { Form, Select, InputNumber } from "antd";
import { LoadType, SupportCondition } from "../../../types/threepointbending";

interface Props {
  loadType: LoadType;
  setLoadType: (val: LoadType) => void;
  loadPosition: number;
  setLoadPosition: (val: number) => void;
  integrationSteps: number;
  setIntegrationSteps: (val: number) => void;
  supportCondition: SupportCondition;
  setSupportCondition: (val: SupportCondition) => void;
  span: number;
}

const AnalysisConditionPanel: React.FC<Props> = ({
  loadType,
  setLoadType,
  loadPosition,
  setLoadPosition,
  integrationSteps,
  setIntegrationSteps,
  supportCondition,
  setSupportCondition,
  span
}) => {
  return (
    <>
      <Form.Item label="Support Condition">
        <Select
          value={supportCondition}
          onChange={setSupportCondition}
          options={[
            { value: "SimplySupported", label: "Simply Supported" },
            { value: "Cantilever", label: "Cantilever" }
          ]}
          style={{ width: "100%" }}
        />
      </Form.Item>

      <Form.Item label="Load Type">
        <Select
          value={loadType}
          onChange={setLoadType}
          options={[
            { value: "Point", label: "Point Load" },
            { value: "UDL", label: "Uniform Distributed Load" }
          ]}
          style={{ width: "100%" }}
        />
      </Form.Item>

      {loadType === "Point" && (
        <Form.Item label="Load Position (mm)">
          <InputNumber
            value={loadPosition}
            onChange={(v) => setLoadPosition(v || span / 2)}
            style={{ width: "100%" }}
            min={0}
            max={span}
          />
        </Form.Item>
      )}

      <Form.Item label="Integration Steps">
        <InputNumber
          value={integrationSteps}
          onChange={(v) => setIntegrationSteps(v || 100)}
          style={{ width: "100%" }}
          min={10}
          max={1000}
        />
      </Form.Item>
    </>
  );
};

export default AnalysisConditionPanel;
