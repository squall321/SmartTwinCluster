export interface ModeResult {
    frequencies: number[];
    dampingRatios: number[];
    modeShapes: number[][];
}
export interface HarmonicResult {
    frequency: number[];
    magnitudeDB: number[][];
    phaseDeg: number[][];
}
export interface TransientResult {
    time: number[];
    displacement: number[][];
}
