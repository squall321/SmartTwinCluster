import React from "react";
import { Form, Radio } from "antd";
import { DeformationModel } from "../../../types/threepointbending";

interface Props {
  deformationModel: DeformationModel;
  setDeformationModel: (model: DeformationModel) => void;
}

const DeformationModelPanel: React.FC<Props> = ({
  deformationModel,
  setDeformationModel
}) => (
  <Form.Item label="Deformation Model">
    <Radio.Group
      value={deformationModel}
      onChange={(e) =>
        setDeformationModel(e.target.value)
      }
    >
      <Radio value="Small">Small Deformation</Radio>
      <Radio value="Large">Large Deformation</Radio>
    </Radio.Group>
  </Form.Item>
);

export default DeformationModelPanel;
