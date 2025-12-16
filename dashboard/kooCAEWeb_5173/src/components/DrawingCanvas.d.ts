import React from 'react';
interface DrawingCanvasProps {
    glbUrl?: string;
    glbFile?: File;
    onModelBounds?: (bounds: {
        xmin: number;
        xmax: number;
        ymin: number;
        ymax: number;
    }) => void;
}
declare const DrawingCanvas: React.ForwardRefExoticComponent<DrawingCanvasProps & React.RefAttributes<any>>;
export default DrawingCanvas;
