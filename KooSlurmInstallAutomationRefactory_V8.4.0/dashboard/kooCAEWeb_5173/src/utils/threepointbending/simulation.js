import { momentCurvature } from "./momentCurvature";
import { computeCurvatureDistribution } from "./curvatureDistribution";
import { integrateDeformation } from "./deformationIntegrator";
export function runSimulation(geometry, loadCfg, material, deformation, analysis) {
    const loads = [];
    const deflections = [];
    const curvatures = [];
    const moments = [];
    const shapes = [];
    const { width: b, height: h, span: L } = geometry;
    const I = (b * Math.pow(h, 3)) / 12;
    for (let P = 0; P <= loadCfg.maxLoad; P += loadCfg.step) {
        let delta = 0;
        let M = 0;
        let curvature = 0;
        if (deformation === "Small") {
            if (analysis.loadType === "Point") {
                const a = analysis.loadPosition;
                const bSpan = L - a;
                M = (P * a * bSpan) / L;
                curvature = M / (material.params.E * I);
                delta =
                    (P * a * bSpan * (Math.pow(L, 2) - a * bSpan)) /
                        (3 * L * material.params.E * I);
            }
            else if (analysis.loadType === "UDL") {
                M = (P * L) / 8;
                curvature = M / (material.params.E * I);
                delta = (5 * P * Math.pow(L, 4)) / (384 * material.params.E * I);
            }
        }
        else {
            let targetMoment = 0;
            if (analysis.loadType === "Point") {
                const a = analysis.loadPosition;
                const bSpan = L - a;
                targetMoment = (P * a * bSpan) / L;
            }
            else if (analysis.loadType === "UDL") {
                targetMoment = (P * L) / 8;
            }
            let kappaGuess = 0.00001;
            const maxIter = 50;
            const tol = 1e-6;
            for (let i = 0; i < maxIter; i++) {
                const Mcalc = momentCurvature(kappaGuess, h, b, material, deformation, analysis.integrationSteps);
                const residual = Mcalc - targetMoment;
                if (Math.abs(residual) < tol)
                    break;
                const dk = kappaGuess * 0.01;
                const Mplus = momentCurvature(kappaGuess + dk, h, b, material, deformation, analysis.integrationSteps);
                const dMdK = (Mplus - Mcalc) / dk;
                kappaGuess -= residual / dMdK;
            }
            curvature = kappaGuess;
            M = targetMoment;
            delta = (curvature * L * L) / 8;
        }
        const kappaArray = computeCurvatureDistribution(curvature, L, 100, analysis.loadType, analysis.loadPosition, analysis.supportCondition);
        const { wArray } = integrateDeformation(kappaArray, L / 99);
        const shape = {
            xPositions: Array.from({ length: wArray.length }, (_, i) => (L / 99) * i),
            yPositions: wArray
        };
        loads.push(P);
        deflections.push(delta);
        curvatures.push(curvature);
        moments.push(M);
        shapes.push(shape);
    }
    return {
        loads,
        deflections,
        curvatures,
        moments,
        shapes
    };
}
