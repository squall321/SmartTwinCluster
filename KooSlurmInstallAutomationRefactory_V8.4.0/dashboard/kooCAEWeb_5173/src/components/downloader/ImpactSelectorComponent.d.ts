import React from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
interface ImpactPoint {
    dx: number;
    dy: number;
    dz: number;
}
interface ImpactorSelectorComponentProps {
    onChange?: (stlUrl: string, impactPoints: ImpactPoint[]) => void;
    targetBoundingBox?: {
        min: BABYLON.Vector3;
        max: BABYLON.Vector3;
    } | null;
}
declare const ImpactorSelectorComponent: React.FC<ImpactorSelectorComponentProps>;
export default ImpactorSelectorComponent;
