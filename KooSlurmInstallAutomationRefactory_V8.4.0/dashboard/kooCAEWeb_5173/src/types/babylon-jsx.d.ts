declare global {
  namespace JSX {
    interface IntrinsicElements {
      // Babylon.js elements
      arcRotateCamera: any;
      hemisphericLight: any;
      ambientLight: any;
      directionalLight: any;
      model: any;
    }
  }
}

export {}; 