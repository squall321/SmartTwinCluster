// src/types/mck/simulationTypes.ts

export interface ModeResult {
    frequencies: number[];
    dampingRatios: number[];
    modeShapes: number[][]; // shape: [mode][mass index]
  }
  
  export interface HarmonicResult {
    frequency: number[];
    magnitudeDB: number[][]; // rows = force별
    phaseDeg: number[][];    // rows = force별
  }
  
  export interface TransientResult {
    time: number[];                   // 해석 시간 벡터
    displacement: number[][];         // 각 DOF별 변위 결과 (shape: [nDOF][timeSteps])
  }