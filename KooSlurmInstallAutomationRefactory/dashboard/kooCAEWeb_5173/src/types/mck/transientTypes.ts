export interface TransientForce {
    nodeId: string;
    type: "function" | "pwm" | "table";
    expression?: string;
    pwmChannel?: string;
    timeArray?: number[];
    forceArray?: number[];
    duration: number;
    dt: number;
  }
  