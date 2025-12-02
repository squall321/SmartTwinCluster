import { PWMConfig } from "../types/pwm";
export declare function generatePWM(config: PWMConfig): {
    t: number[];
    SinX: number[];
    SawX: number[][];
    PWM: any[];
};
