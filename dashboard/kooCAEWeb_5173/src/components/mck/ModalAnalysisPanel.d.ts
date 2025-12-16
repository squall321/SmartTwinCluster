import React from 'react';
import { MCKSystem } from '../../types/mck/modelTypes';
import { ModeResult } from '../../types/mck/simulationTypes';
interface ModalAnalysisPanelProps {
    system: MCKSystem;
    modalResults: ModeResult | null;
    onRunModal: (numModes: number) => void;
}
declare const ModalAnalysisPanel: React.FC<ModalAnalysisPanelProps>;
export default ModalAnalysisPanel;
