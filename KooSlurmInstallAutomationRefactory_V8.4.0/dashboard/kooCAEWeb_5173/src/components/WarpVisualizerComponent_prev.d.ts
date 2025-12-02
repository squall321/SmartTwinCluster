import '@babylonjs/loaders';
import React from 'react';
import 'antd/dist/reset.css';
interface WarpVisualizerProps {
    warpageInfo: {
        rawData: number[][];
        xLength: number;
        yLength: number;
        scaleFactor: number;
    } | null;
}
declare const WarpVisualizerComponent: React.FC<WarpVisualizerProps>;
export default WarpVisualizerComponent;
