import { SupportCondition } from "../../types/threepointbending";

export function computeCurvatureDistribution(
  curvature: number,
  L: number,
  numPoints: number,
  loadType: "Point" | "UDL",
  loadPosition: number,
  supportCondition: SupportCondition
): number[] {
  const dx = L / (numPoints - 1);

  const kappaArray = [];

  for (let i = 0; i < numPoints; i++) {
    const x = i * dx;

    let localCurvature = 0;

    if (supportCondition === "SimplySupported") {
      if (loadType === "Point") {
        const a = loadPosition;
        const bSpan = L - a;

        if (x < a) {
          localCurvature = curvature * x / a;
        } else {
          localCurvature =
            curvature * (L - x) / bSpan;
        }
      } else if (loadType === "UDL") {
        localCurvature =
          curvature *
          (1 - Math.pow((2 * x - L) / L, 2));
      }
    } else if (supportCondition === "Cantilever") {
      if (loadType === "Point") {
        if (x <= loadPosition) {
          localCurvature = curvature * x / loadPosition;
        } else {
          localCurvature = 0;
        }
      } else if (loadType === "UDL") {
        localCurvature =
          curvature *
          (1 - Math.pow(x / L, 2));
      }
    }

    kappaArray.push(localCurvature);
  }

  return kappaArray;
}
