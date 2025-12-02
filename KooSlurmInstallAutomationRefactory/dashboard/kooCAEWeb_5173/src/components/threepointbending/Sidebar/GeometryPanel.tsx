import React from "react";
import { Form, InputNumber } from "antd";
import { BeamGeometry } from "../../../types/threepointbending";

interface Props {
  geometry: BeamGeometry;
  setGeometry: (geo: BeamGeometry) => void;
}

const GeometryPanel: React.FC<Props> = ({
  geometry,
  setGeometry
}) => {
  const handleChange = (key: keyof BeamGeometry, value: number) => {
    setGeometry({
      ...geometry,
      [key]: value
    });
  };

  return (
    <>
      <Form.Item label="Span (mm)">
        <InputNumber
          value={geometry.span}
          onChange={(v) => handleChange("span", v || 0)}
          style={{ width: "100%" }}
        />
      </Form.Item>
      <Form.Item label="Height (mm)">
        <InputNumber
          value={geometry.height}
          onChange={(v) => handleChange("height", v || 0)}
          style={{ width: "100%" }}
        />
      </Form.Item>
      <Form.Item label="Width (mm)">
        <InputNumber
          value={geometry.width}
          onChange={(v) => handleChange("width", v || 0)}
          style={{ width: "100%" }}
        />
      </Form.Item>
    </>
  );
};

export default GeometryPanel;
