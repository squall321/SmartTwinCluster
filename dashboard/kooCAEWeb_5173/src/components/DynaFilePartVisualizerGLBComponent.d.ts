import React from 'react';
interface DynaFilePartVisualizerProps {
    onReady?: (info: {
        kfile: File;
        partId: string;
        glbFile: File;
    }) => void;
}
declare const DynaFilePartVisualizerGLBComponent: React.FC<DynaFilePartVisualizerProps>;
export default DynaFilePartVisualizerGLBComponent;
