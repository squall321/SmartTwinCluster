export function integrateDeformation(
    curvatureArray: number[],
    dx: number
  ): { thetaArray: number[]; wArray: number[] } {
    const thetaArray: number[] = [];
    const wArray: number[] = [];
  
    let theta = 0;
    let w = 0;
  
    for (let i = 0; i < curvatureArray.length; i++) {
      theta += curvatureArray[i] * dx;
      thetaArray.push(theta);
  
      w += theta * dx;
      wArray.push(w);
    }
  
    const w0 = wArray[0];
    const wArrayShifted = wArray.map((val) => val - w0);
  
    return {
      thetaArray,
      wArray: wArrayShifted
    };
  }
  