import React from "react";
import "@babylonjs/loaders/glTF";
interface Props {
    glbUrl?: string;
    glbFile?: File;
    voxelCount?: number;
    onBounds?: (bounds: {
        xmin: number;
        xmax: number;
        ymin: number;
        ymax: number;
    }) => void;
}
declare const GLBLayer: React.FC<Props>;
export default GLBLayer;
