import React from 'react';
import '@babylonjs/loaders';
interface ImpactorPointViewerProps {
    url: string;
    impactPoints: {
        dx: number;
        dy: number;
    }[];
}
declare const ImpactorPointViewerComponent: React.FC<ImpactorPointViewerProps>;
export default ImpactorPointViewerComponent;
