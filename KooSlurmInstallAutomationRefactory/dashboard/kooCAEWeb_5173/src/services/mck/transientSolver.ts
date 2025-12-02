import { MCKSystem } from "../../types/mck/modelTypes";
import { TransientForce } from "../../types/mck/transientTypes";
import { create, all } from "mathjs";

const math = create(all, {});

export interface TransientResult {
  time: number[];
  displacements: number[][];
}

export function runTransientAnalysis(
  system: MCKSystem,
  forces: TransientForce[]
): TransientResult {
  if (system.masses.length === 0) {
    return { time: [], displacements: [] };
  }

  // DoF mapping
  const freeDOFIds = system.masses.map((m) => m.id);
  const dofIndexMap: Record<string, number> = {};
  freeDOFIds.forEach((id, i) => {
    dofIndexMap[id] = i;
  });

  const n = freeDOFIds.length;

  // Assemble M, K, C
  let M = math.zeros(n, n) as any;
  let K = math.zeros(n, n) as any;
  let C = math.zeros(n, n) as any;

  system.masses.forEach((m) => {
    const i = dofIndexMap[m.id];
    M.set([i, i], m.m);
  });

  system.springs.forEach((spring) => {
    const i = dofIndexMap[spring.from];
    const j = dofIndexMap[spring.to];
    const k = spring.k;
    if (i !== undefined) K.set([i, i], K.get([i, i]) + k);
    if (j !== undefined) K.set([j, j], K.get([j, j]) + k);
    if (i !== undefined && j !== undefined) {
      K.set([i, j], K.get([i, j]) - k);
      K.set([j, i], K.get([j, i]) - k);
    }
  });

  system.dampers.forEach((damper) => {
    const i = dofIndexMap[damper.from];
    const j = dofIndexMap[damper.to];
    const c = damper.c;
    if (i !== undefined) C.set([i, i], C.get([i, i]) + c);
    if (j !== undefined) C.set([j, j], C.get([j, j]) + c);
    if (i !== undefined && j !== undefined) {
      C.set([i, j], C.get([i, j]) - c);
      C.set([j, i], C.get([j, i]) - c);
    }
  });

  // Global time array
  const maxDuration = Math.max(...forces.map((f) => f.duration));
  const dt = Math.min(...forces.map((f) => f.dt));
  const time = math.range(0, maxDuration + dt, dt, true).toArray() as number[];

  // Generate global force vector over time
  const Fhist = math.zeros(n, time.length) as any;

  for (const force of forces) {
    const i = dofIndexMap[force.nodeId];
    if (i === undefined) continue;
  
    let fvec: number[] = [];
  
    if (force.type === "function" && force.expression) {
      const expr = math.compile(force.expression);
      fvec = time.map((t) => Number(expr.evaluate({ t })));
    } 
    else if (force.type === "table" && force.timeArray && force.forceArray) {
      fvec = interpolateTable(force.timeArray, force.forceArray, time);
    } 
    else {
      fvec = new Array(time.length).fill(0);
    }
  
    for (let j = 0; j < time.length; j++) {
      Fhist.set([i, j], Fhist.get([i, j]) + fvec[j]);
    }
  }

  // Newmark parameters
  const beta = 0.25;
  const gamma = 0.5;

  const Minv = math.inv(M);
  const a0 = 1 / (beta * dt * dt);
  const a1 = gamma / (beta * dt);
  const a2 = 1 / (beta * dt);
  const a3 = 1 / (2 * beta) - 1;
  const a4 = gamma / beta - 1;
  const a5 = dt * (gamma / (2 * beta) - 1);

  const Keff = math.add(
    K,
    math.add(math.multiply(a1, C), math.multiply(a0, M))
  ) as any;
  const KeffInv = math.inv(Keff);

  // Initial conditions
  let x = math.zeros(n, 1) as any;
  let v = math.zeros(n, 1) as any;
  let a = math.multiply(Minv, math.subtract(math.column(Fhist, 0), math.add(math.multiply(C, v), math.multiply(K, x)))) as any;

  const displacements: number[][] = [];

  for (let k = 0; k < time.length; k++) {
    const Fk = math.column(Fhist, k);
    const rhs = math.add(
      Fk,
      math.add(
        math.multiply(M, math.add(math.multiply(a0, x), math.add(math.multiply(a2, v), math.multiply(a3, a)))),
        math.multiply(C, math.add(math.multiply(a1, x), math.add(math.multiply(a4, v), math.multiply(a5, a))))
      )
    );

    const x_new = math.multiply(KeffInv, rhs) as any;
    const a_new = math.add(
      math.multiply(a0, math.subtract(x_new, x)),
      math.add(math.multiply(a2, v), math.multiply(a3, a))
    );

    const v_new = math.add(
      v,
      math.multiply(dt, math.add(math.multiply((1 - gamma), a), math.multiply(gamma, a_new)))
    );

    displacements.push(x_new.toArray().map((val: number[]) => val[0]));

    x = x_new;
    v = v_new;
    a = a_new;
  }

  return {
    time,
    displacements,
  };
}

function interpolateTable(tArr: number[], fArr: number[], time: number[]): number[] {
  const fvec = [];
  for (const t of time) {
    if (t <= tArr[0]) {
      fvec.push(fArr[0]);
    } else if (t >= tArr[tArr.length - 1]) {
      fvec.push(fArr[fArr.length - 1]);
    } else {
      for (let i = 0; i < tArr.length - 1; i++) {
        if (tArr[i] <= t && t <= tArr[i + 1]) {
          const slope =
            (fArr[i + 1] - fArr[i]) / (tArr[i + 1] - tArr[i]);
          fvec.push(fArr[i] + slope * (t - tArr[i]));
          break;
        }
      }
    }
  }
  return fvec;
}
