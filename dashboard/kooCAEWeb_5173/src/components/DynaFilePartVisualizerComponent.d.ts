import React from 'react';
interface DynaFilePartVisualizerProps {
    onReady?: (info: {
        kfile: File;
        partId: string;
        stlUrl: string;
    }) => void;
}
declare const DynaFilePartVisualizerComponent: React.FC<DynaFilePartVisualizerProps>;
export default DynaFilePartVisualizerComponent;
