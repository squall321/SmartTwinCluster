import { strainToStressRambergOsgood } from "./rambergOsgood";
export function momentCurvature(curvature, height, width, material, deformation, integrationSteps) {
    const I = (width * Math.pow(height, 3)) / 12;
    if (deformation === "Small") {
        if (material.model !== "LinearElastic") {
            throw new Error("Plasticity not allowed in Small Deformation.");
        }
        return curvature * material.params.E * I;
    }
    const dy = height / integrationSteps;
    let M = 0;
    for (let i = 0; i < integrationSteps; i++) {
        const y = -height / 2 + i * dy;
        const strain = curvature * y;
        let stress = 0;
        if (material.model === "LinearElastic") {
            stress = material.params.E * strain;
        }
        else if (material.model === "PowerLaw") {
            const { E, sigmaY, K, n } = material.params;
            if (Math.abs(strain) <= sigmaY / E) {
                stress = E * strain;
            }
            else {
                const sign = strain >= 0 ? 1 : -1;
                const plasticStrain = Math.abs(strain) - sigmaY / E;
                stress =
                    sign *
                        (sigmaY + K * Math.pow(plasticStrain, n));
            }
        }
        else if (material.model === "RambergOsgood") {
            const { E, sigma0, K, n } = material.params;
            stress = strainToStressRambergOsgood(strain, E, sigma0, K, n);
        }
        M += stress * y * dy;
    }
    return M;
}
