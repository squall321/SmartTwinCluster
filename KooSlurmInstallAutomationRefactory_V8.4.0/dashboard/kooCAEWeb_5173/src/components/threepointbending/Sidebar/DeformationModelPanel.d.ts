import React from "react";
import { DeformationModel } from "../../../types/threepointbending";
interface Props {
    deformationModel: DeformationModel;
    setDeformationModel: (model: DeformationModel) => void;
}
declare const DeformationModelPanel: React.FC<Props>;
export default DeformationModelPanel;
