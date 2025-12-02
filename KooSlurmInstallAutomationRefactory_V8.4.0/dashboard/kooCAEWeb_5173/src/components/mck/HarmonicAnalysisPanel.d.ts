import React from 'react';
import { MCKSystem } from '../../types/mck/modelTypes';
import { ModeResult } from '../../types/mck/simulationTypes';
interface HarmonicAnalysisPanelProps {
    system: MCKSystem;
    modalResults: ModeResult | null;
    onRunHarmonic: (result: any) => void;
    setSystem: React.Dispatch<React.SetStateAction<MCKSystem>>;
}
declare const HarmonicAnalysisPanel: React.FC<HarmonicAnalysisPanelProps>;
export default HarmonicAnalysisPanel;
