import React from "react";
import { MassNode } from "../../types/mck/modelTypes";
import { TransientForce } from "../../types/mck/transientTypes";
interface TransientAnalysisPanelProps {
    nodes: MassNode[];
    onAddForce: (force: TransientForce) => void;
    onRunTransient: () => void;
    onDeleteForce: (forceKey: string) => void;
    forces: TransientForce[];
}
declare const TransientAnalysisPanel: React.FC<TransientAnalysisPanelProps>;
export default TransientAnalysisPanel;
