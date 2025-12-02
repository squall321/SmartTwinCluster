import React from "react";
type DotPattern = "1x1" | "3x3" | "1x3" | "3x1" | "2x2" | "2x1" | "1x2";
interface DotIconProps {
    pattern: DotPattern;
    size?: number;
    color?: string;
}
declare const DotIcon: React.FC<DotIconProps>;
export default DotIcon;
