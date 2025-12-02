import React from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
interface StlWithPositions {
    url: string;
    positions: BABYLON.Vector3[];
}
interface MultipleStlViewerProps {
    models: StlWithPositions[];
    viewDirection?: 'top' | 'bottom' | 'left' | 'right' | 'front' | 'back';
}
declare const MultipleStlViewerComponent: React.FC<MultipleStlViewerProps>;
export default MultipleStlViewerComponent;
