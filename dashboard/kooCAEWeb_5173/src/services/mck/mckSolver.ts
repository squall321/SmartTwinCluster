import { MCKSystem } from '../../types/mck/modelTypes';
import { ModeResult, HarmonicResult, TransientResult } from "../../types/mck/simulationTypes";
import { TransientForce } from '../../types/mck/transientTypes';
import { create, all } from 'mathjs';

const math = create(all, {});

// Helper: make reduced matrix
function reduceMatrix(M_full: any, freeDOFIndices: number[]) {
  return math.subset(
    math.subset(M_full, math.index(freeDOFIndices, math.range(0, M_full.size()[1]))),
    math.index(math.range(0, freeDOFIndices.length), freeDOFIndices)
  );
}

export function modalAnalysis(system: MCKSystem, numModes: number): ModeResult {
  // 1. All DOF → only masses
  const allNodes: string[] = [
    ...system.masses.map((m) => m.id),
    ...system.fixedPoints.map((f) => f.id),
  ];

  // Fixed node indices
  const fixedIds = new Set(system.fixedPoints.map(f => f.id));

  // Free DOF: only masses
  const freeDOFIds = system.masses.map((m) => m.id);
  const dofIndexMap: Record<string, number> = {};
  freeDOFIds.forEach((id, i) => {
    dofIndexMap[id] = i;
  });

  const n = freeDOFIds.length;
  if (n === 0) return { frequencies: [], dampingRatios: [], modeShapes: [] };

  // Floating mass check
  for (const mass of system.masses) {
    const hasConnection =
      system.springs.some((s) => s.from === mass.id || s.to === mass.id) ||
      system.dampers.some((d) => d.from === mass.id || d.to === mass.id);
    if (!hasConnection) {
      throw new Error(
        `Floating mass detected: ${mass.id}. Please connect it to springs or dampers.`
      );
    }
  }

  let M_full = math.zeros(n, n) as any;
  let K_full = math.zeros(n, n) as any;
  let C_full = math.zeros(n, n) as any;

  // Mass matrix
  system.masses.forEach((m) => {
    const i = dofIndexMap[m.id];
    M_full.set([i, i], m.m);
  });

  // Springs
  for (const spring of system.springs) {
    const i = dofIndexMap[spring.from];
    const j = dofIndexMap[spring.to];
    const k = spring.k;

    if (i !== undefined) K_full.set([i, i], K_full.get([i, i]) + k);
    if (j !== undefined) K_full.set([j, j], K_full.get([j, j]) + k);
    if (i !== undefined && j !== undefined) {
      K_full.set([i, j], K_full.get([i, j]) - k);
      K_full.set([j, i], K_full.get([j, i]) - k);
    }
  }

  // Dampers
  for (const damper of system.dampers) {
    const i = dofIndexMap[damper.from];
    const j = dofIndexMap[damper.to];
    const c = damper.c;

    if (i !== undefined) C_full.set([i, i], C_full.get([i, i]) + c);
    if (j !== undefined) C_full.set([j, j], C_full.get([j, j]) + c);
    if (i !== undefined && j !== undefined) {
      C_full.set([i, j], C_full.get([i, j]) - c);
      C_full.set([j, i], C_full.get([j, i]) - c);
    }
  }

  // Already reduced since we only built free DOFs
  const M = M_full;
  const K = K_full;
  const C = C_full;

  const zero = math.zeros(n, n) as any;
  const I = math.identity(n) as any;

  try {
    const Minv = math.inv(M);
    const A_top = math.concat(zero, I, 1);
    const A_bottom = math.concat(
      math.multiply(-1, math.multiply(Minv, K) as any),
      math.multiply(-1, math.multiply(Minv, C) as any),
      1
    );

    const A = math.concat(A_top, A_bottom, 0);
    const eig = math.eigs(A as any);
    const lambdas = eig.values as any[];

    const freqs: number[] = [];
    const dampingRatios: number[] = [];

    lambdas.forEach((val) => {
      const real = Number(math.re(val));
      const imag = Number(math.im(val));

      const omega_d = Math.sqrt(real ** 2 + imag ** 2);
      if (omega_d < 1e-6) return;

      const fn = omega_d / (2 * Math.PI);
      const zeta = -real / omega_d;
      freqs.push(fn);
      dampingRatios.push(zeta);
    });

    return {
      frequencies: freqs.slice(0, numModes),
      dampingRatios: dampingRatios.slice(0, numModes),
      modeShapes: [], // 추후 구현
    };
  } catch (e) {
    console.error("Eigenvalue decomposition failed:", e);
    throw new Error(
      "Modal analysis failed due to matrix singularity or disconnected masses."
    );
  }
}

export function harmonicResponse(
    system: MCKSystem,
    freqRange: [number, number],
    numPoints: number
  ): HarmonicResult {
    const freeDOFIds = system.masses.map((m) => m.id);
    const dofIndexMap: Record<string, number> = {};
    freeDOFIds.forEach((id, i) => {
      dofIndexMap[id] = i;
    });
  
    const n = freeDOFIds.length;
    const freqs = math
      .range(freqRange[0], freqRange[1], (freqRange[1] - freqRange[0]) / numPoints, true)
      .toArray();
  
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
  
    const magnitudeDB: number[][] = [];
    const phaseDeg: number[][] = [];
  
    if (system.forces.length === 0) {
      // 최소 하나의 dummy row라도 반환
      magnitudeDB.push(Array(freqs.length).fill(0));
      phaseDeg.push(Array(freqs.length).fill(0));
    } else {
      system.forces.forEach((force) => {
        const F = math.zeros(n, 1) as any;
        const index = dofIndexMap[force.targetMassId];
        if (index === undefined) {
          console.warn(
            `Force target ${force.targetMassId} is not a mass DOF, ignoring.`
          );
          return;
        }
  
        F.set([index, 0], force.magnitude);
  
        const magRow: number[] = [];
        const phaseRow: number[] = [];
  
        freqs.forEach((f: any) => {
          const omega = 2 * Math.PI * f;
          const Z = math.add(
            math.multiply(-omega * omega, M),
            math.add(math.multiply(math.complex(0, omega), C), K)
          ) as any;
  
          const X = math.multiply(math.inv(Z), F) as any;
          const Xval = X.get ? X.get([index, 0]) : X;
  
          let mag = math.abs(Xval);
          if (mag < 1e-20) mag = 1e-20;
  
          const phase =
            Number(math.atan2(Number(math.im(Xval)), Number(math.re(Xval)))) *
            (180 / Math.PI);
  
          magRow.push(20 * Math.log10(mag));
          phaseRow.push(phase);
        });
  
        magnitudeDB.push(magRow);
        phaseDeg.push(phaseRow);
      });
    }
  
    return {
      frequency: freqs.map((f: any) => Number(f)),
      magnitudeDB,
      phaseDeg,
    };
  }
  
  export function runTransientAnalysis(
    system: MCKSystem,
    forces: TransientForce[]
  ): TransientResult {
    if (system.masses.length === 0) {
      return { time: [], displacement: [] };
    }
  
    const freeDOFIds = system.masses.map((m) => m.id);
    const dofIndexMap: Record<string, number> = {};
    freeDOFIds.forEach((id, i) => {
      dofIndexMap[id] = i;
    });
  
    const n = freeDOFIds.length;
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
  
    const maxDuration = Math.max(...forces.map((f) => f.duration));
    const dt = Math.min(...forces.map((f) => f.dt));
    const time = math.range(0, maxDuration + dt, dt, true).toArray() as number[];
  
    const Fhist = math.zeros(n, time.length) as any;
  
    for (const force of forces) {
      const i = dofIndexMap[force.nodeId];
      if (i === undefined) continue;
  
      let fvec: number[] = [];
  
      if (force.type === "function" && force.expression) {
        const expr = math.compile(force.expression);
        fvec = time.map((t) => Number(expr.evaluate({ t })));
      } else if (force.type === "table" && force.timeArray && force.forceArray) {
        fvec = interpolateTable(force.timeArray, force.forceArray, time);
      } else if (force.type === "pwm" && force.pwmChannel && force.timeArray && force.forceArray) {
        fvec = interpolateTable(force.timeArray, force.forceArray, time);
      } else {
        fvec = new Array(time.length).fill(0);
      }
  
      for (let j = 0; j < time.length; j++) {
        Fhist.set([i, j], Fhist.get([i, j]) + fvec[j]);
      }
    }
  
    // Newmark-beta parameters
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
  
    let x = math.zeros(n, 1) as any;
    let v = math.zeros(n, 1) as any;
    let a = math.multiply(
      Minv,
      math.subtract(math.column(Fhist, 0), math.add(math.multiply(C, v), math.multiply(K, x)))
    ) as any;
  
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
        math.multiply(dt, math.add(math.multiply(1 - gamma, a), math.multiply(gamma, a_new)))
      );
  
      displacements.push(x_new.toArray().map((val: number[]) => val[0]));
  
      x = x_new;
      v = v_new;
      a = a_new;
    }
  
    return {
      time,
      displacement: displacements,
    };
  }
  
  function interpolateTable(tArr: number[], fArr: number[], time: number[]): number[] {
    const fvec: number[] = [];
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
  
  export function transientResponse(
    system: MCKSystem,
    time: number[],
    forcesPerNode: Record<string, number[]>
  ): TransientResult {
    const freeDOFIds = system.masses.map((m) => m.id);
    const dofIndexMap: Record<string, number> = {};
    freeDOFIds.forEach((id, i) => {
      dofIndexMap[id] = i;
    });
  
    const n = freeDOFIds.length;
  
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
  
    // initial conditions
    let X = math.zeros(n, 1) as any;
    let V = math.zeros(n, 1) as any;
  
    const dt = time[1] - time[0];
    const displacementHistory: number[][] = [];
  
    for (let tIdx = 0; tIdx < time.length; tIdx++) {
      const t = time[tIdx];
  
      // force vector at current time
      const F = math.zeros(n, 1) as any;
      for (const nodeId of Object.keys(forcesPerNode)) {
        const nodeIndex = dofIndexMap[nodeId];
        if (nodeIndex !== undefined) {
          F.set([nodeIndex, 0], forcesPerNode[nodeId][tIdx] || 0);
        }
      }
  
      // Newmark-beta integration parameters
      const beta = 0.25;
      const gamma = 0.5;
  
      const A = math.add(
        math.add(
          K,
          math.multiply(gamma / (beta * dt), C)
        ),
        math.multiply(1 / (beta * dt * dt), M)
      ) as any;
  
      const rhs = math.add(
        F,
        math.multiply(
          M,
          math.add(
            math.multiply(1 / (beta * dt * dt), X),
            math.multiply(1 / (beta * dt), V)
          )
        ),
        math.multiply(
          C,
          math.add(
            math.multiply(gamma / (beta * dt), X),
            math.multiply((gamma / beta - 1), V)
          )
        )
      ) as any;
  
      const Xnew = math.multiply(math.inv(A), rhs) as any;
      const Vnew = math.add(
        math.multiply(gamma / (beta * dt), math.subtract(Xnew, X)),
        math.multiply(1 - gamma / beta, V)
      ) as any;
  
      X = Xnew;
      V = Vnew;
  
      const disp = Array.from({ length: n }, (_, i) => X.get([i, 0]));
      displacementHistory.push(disp);
    }
  
    return {
      time,
      displacement: math.transpose(math.matrix(displacementHistory)).toArray() as number[][],
    };
  }