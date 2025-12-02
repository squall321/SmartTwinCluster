import React from "react";
import { MaterialModel, MaterialParams } from "../../../types/threepointbending";
interface Props {
    materialModel: MaterialModel;
    setMaterialModel: (model: MaterialModel) => void;
    materialParams: MaterialParams;
    setMaterialParams: (params: MaterialParams) => void;
}
declare const MaterialModelPanel: React.FC<Props>;
export default MaterialModelPanel;
