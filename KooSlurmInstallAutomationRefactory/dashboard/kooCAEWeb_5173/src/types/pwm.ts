export interface PWMChannel {
    name: string;
    frequency: number;
    amplitude: number;
    coefficient: number;
    enabled: boolean;
  }
  
  export interface PWMConfig {
    targetFrequency: number;
    sinAmplitude: number;
    dt: number;
    duration: number;
    channels: PWMChannel[];
  }
  