import React from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/core/Meshes/mesh';
import '@babylonjs/loaders';
interface ObjViewerProps {
    url: string;
    mtlUrl?: string;
    backgroundColor?: BABYLON.Color4;
    orthographic?: boolean;
}
declare const ObjViewerComponent: React.FC<ObjViewerProps>;
export default ObjViewerComponent;
