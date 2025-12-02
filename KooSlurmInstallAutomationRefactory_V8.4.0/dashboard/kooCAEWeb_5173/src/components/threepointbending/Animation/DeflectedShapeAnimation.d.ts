import React from "react";
import { DeformedShape } from "../../../types/threepointbending";
interface Props {
    shapes: DeformedShape[];
    loads: number[];
}
declare const DeflectedShapeAnimation: React.FC<Props>;
export default DeflectedShapeAnimation;
