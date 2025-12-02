import React from "react";
import { Form, Select, InputNumber } from "antd";
import {
  MaterialModel,
  MaterialParams
} from "../../../types/threepointbending";
import ModelFormulaBox from "../../common/ModelFormulaBox";

interface Props {
  materialModel: MaterialModel;
  setMaterialModel: (model: MaterialModel) => void;
  materialParams: MaterialParams;
  setMaterialParams: (params: MaterialParams) => void;
}

const MaterialModelPanel: React.FC<Props> = ({
  materialModel,
  setMaterialModel,
  materialParams,
  setMaterialParams
}) => {
  const handleParamChange = (key: string, value: number) => {
    setMaterialParams({
      model: materialModel as MaterialModel,
      params: {
        ...materialParams.params,
        [key]: value
      }
    } as any);
  };

  return (
    <>
      <Form.Item label="Material Model">
        <Select
          value={materialModel}
          style={{ width: "100%" }}
          onChange={(v) => {
            setMaterialModel(v);
            switch (v) {
              case "LinearElastic":
                setMaterialParams({
                  model: v,
                  params: { E: 200000 }
                });
                break;
              case "PowerLaw":
                setMaterialParams({
                  model: v,
                  params: {
                    E: 200000,
                    sigmaY: 250,
                    K: 500,
                    n: 0.2
                  }
                });
                break;
              case "RambergOsgood":
                setMaterialParams({
                  model: v,
                  params: {
                    E: 200000,
                    sigma0: 250,
                    K: 0.002,
                    n: 5
                  }
                });
                break;
            }
          }}
          options={[
            { value: "LinearElastic", label: "Linear Elastic" },
            { value: "PowerLaw", label: "Power Law Plasticity" },
            { value: "RambergOsgood", label: "Ramberg-Osgood Plasticity" }
          ]}
        />
      </Form.Item>

      {Object.entries(materialParams.params).map(([key, val]) => (
        <Form.Item label={key} key={key}>
          <InputNumber
            value={val as number}
            onChange={(v) => handleParamChange(key, v || 0)}
            style={{ width: "100%" }}
          />
        </Form.Item>
      ))}

      {/* 수식 추가 */}
      {materialModel === "LinearElastic" && (
        <ModelFormulaBox
          title="Linear Elastic"
          description="선형 탄성 재료 모델입니다."
          formulas={[
            "\\sigma = E \\cdot \\varepsilon"
          ]}
        />
      )}

      {materialModel === "PowerLaw" && (
        <ModelFormulaBox
          title="Power Law Plasticity"
          description="탄성 이후 소성 영역에서 Power Law를 적용합니다."
          formulas={[
            "\\sigma = \\begin{cases} E \\cdot \\varepsilon & \\text{(Elastic)} \\\\ \\sigma_Y + K \\cdot \\varepsilon_p^n & \\text{(Plastic)} \\end{cases}"
          ]}
        />
      )}

      {materialModel === "RambergOsgood" && (
        <ModelFormulaBox
          title="Ramberg-Osgood Plasticity"
          description="Ramberg-Osgood 모델은 탄소성 변형을 부드럽게 표현합니다."
          formulas={[
            "\\varepsilon = \\frac{\\sigma}{E} + K \\left( \\frac{\\sigma}{\\sigma_0} \\right)^n"
          ]}
        />
      )}
    </>
  );
};

export default MaterialModelPanel;
