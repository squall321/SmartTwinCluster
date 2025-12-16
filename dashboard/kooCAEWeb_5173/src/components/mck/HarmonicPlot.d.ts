import React from 'react';
interface HarmonicPlotProps {
    frequencies: number[];
    magnitudeDB: number[][];
    phaseDeg: number[][];
    forceLabels: string[];
}
declare const HarmonicPlot: React.FC<HarmonicPlotProps>;
export default HarmonicPlot;
