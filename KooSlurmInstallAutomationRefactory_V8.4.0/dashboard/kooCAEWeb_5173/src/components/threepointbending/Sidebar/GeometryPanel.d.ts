import React from "react";
import { BeamGeometry } from "../../../types/threepointbending";
interface Props {
    geometry: BeamGeometry;
    setGeometry: (geo: BeamGeometry) => void;
}
declare const GeometryPanel: React.FC<Props>;
export default GeometryPanel;
