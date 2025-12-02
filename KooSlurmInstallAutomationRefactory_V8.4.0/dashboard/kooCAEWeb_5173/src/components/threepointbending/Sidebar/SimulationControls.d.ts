import React from "react";
interface Props {
    onRun: () => void;
    onReset: () => void;
    loading: boolean;
}
declare const SimulationControls: React.FC<Props>;
export default SimulationControls;
