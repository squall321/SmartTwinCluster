import React from "react";
import { MotorLevelSimulationConfig } from "../types/motorLevelSimulation";
interface Props {
    onRun: (config: MotorLevelSimulationConfig) => void;
}
declare const MotorLevelSimulationConfigForm: React.FC<Props>;
export default MotorLevelSimulationConfigForm;
