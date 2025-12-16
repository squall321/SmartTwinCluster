import React from "react";
interface PWMGeneratorProps {
    onPWMGenerated?: (result: {
        channelName: string;
        duration: number;
        dt: number;
        t: number[];
        PWM: number[];
    }) => void;
}
declare const PWMGenerator: React.FC<PWMGeneratorProps>;
export default PWMGenerator;
