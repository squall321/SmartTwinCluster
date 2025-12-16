import React from "react";
import "@babylonjs/loaders/glTF";
interface Props {
    glbUrl?: string;
    glbFile?: File;
    onBounds?: (bounds: {
        xmin: number;
        xmax: number;
        ymin: number;
        ymax: number;
    }) => void;
}
declare const GLBLayerTest: React.FC<Props>;
export default GLBLayerTest;
