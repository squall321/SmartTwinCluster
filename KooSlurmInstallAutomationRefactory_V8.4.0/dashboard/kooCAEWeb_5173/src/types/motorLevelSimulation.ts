export interface MotorLevelSimulationConfig {
    r_P_global_0: [number, number, number];
    r_Q_global: [number, number, number];
    xvector: [number, number, number];
    yvector: [number, number, number];
    zvector: [number, number, number];
    I_principal: [number, number, number];
    m: number;
    mu: number;
    g: number;
    width: number;
    height: number;
    thickness: number;
    dt: number;
    duration: number;
    freq: number;
    F0: number;
    forceDirection: [number, number, number];
    gridX: number;
    gridY: number;
  }
  
  export interface MotorLevelSimulationResults {
    time: number[];
    a_B_average: number[];
    rmsValue: number;
    r_O_global: number[][];
    gridXVals: number[];
    gridYVals: number[];
    magnitudeGrid: number[][][]; // [time][ny][nx]
  }
  