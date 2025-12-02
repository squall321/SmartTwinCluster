import React from "react";
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
declare const AnalysisConditionPanel: React.FC<Props>;
export default AnalysisConditionPanel;
