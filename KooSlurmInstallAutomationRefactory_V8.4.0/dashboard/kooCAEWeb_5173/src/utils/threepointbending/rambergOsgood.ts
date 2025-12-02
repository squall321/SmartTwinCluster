export function strainToStressRambergOsgood(
    strain: number,
    E: number,
    sigma0: number,
    K: number,
    n: number,
    maxIter = 50,
    tol = 1e-8
  ): number {
    let sigma = strain * E;
  
    for (let i = 0; i < maxIter; i++) {
      const f =
        sigma / E + K * Math.pow(sigma / sigma0, n) - strain;
  
      const df =
        1 / E +
        (K * n * Math.pow(sigma / sigma0, n - 1)) / sigma0;
  
      const delta = -f / df;
      sigma += delta;
  
      if (Math.abs(delta) < tol) {
        return sigma;
      }
    }
  
    throw new Error(
      "Ramberg-Osgood solver did not converge."
    );
  }
  