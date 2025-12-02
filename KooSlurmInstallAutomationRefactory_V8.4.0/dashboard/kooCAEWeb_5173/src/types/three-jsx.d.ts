import { Object3D } from 'three';

declare global {
  namespace JSX {
    interface IntrinsicElements {
      mesh: any;
      boxGeometry: any;
      sphereGeometry: any;
      planeGeometry: any;
      meshStandardMaterial: any;
      ambientLight: any;
      pointLight: any;
      group: any;
      primitive: any;
      points: any;
      bufferGeometry: any;
      bufferAttribute: any;
      pointsMaterial: any;
      // Babylon.js elements
      arcRotateCamera: any;
      hemisphericLight: any;
      directionalLight: any;
      model: any;
    }
  }
}

export {}; 