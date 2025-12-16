import React from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
interface TimeAnimatedStlViewerProps {
    stlUrl: string;
    positions: BABYLON.Vector3[][];
    frame: number;
}
declare const TimeAnimatedStlViewerComponent: React.FC<TimeAnimatedStlViewerProps>;
export default TimeAnimatedStlViewerComponent;
