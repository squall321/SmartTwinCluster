function cross(a, b) {
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ];
}
function dot(a, b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
function multiplyMatrixVector(M, v) {
    return M.map(row => dot(row, v));
}
export function runMotorLevelSimulation(config) {
    const { r_P_global_0, r_Q_global, xvector, yvector, zvector, I_principal, m, mu, g, width, height, thickness, dt, duration, freq, F0, gridX, gridY } = config;
    const timeSteps = Math.floor(duration / dt);
    const time = Array.from({ length: timeSteps }, (_, i) => i * dt);
    // Force
    const forceDirNorm = Math.sqrt(config.forceDirection[0] ** 2 +
        config.forceDirection[1] ** 2 +
        config.forceDirection[2] ** 2) || 1;
    const forceUnit = config.forceDirection.map(v => v / forceDirNorm);
    const F_global = time.map(t => {
        const scalar = config.F0 * Math.sin(2 * Math.PI * config.freq * t);
        return forceUnit.map(d => d * scalar);
    });
    const N = m * g;
    const F_friction_max = mu * N * 1000; // N → N·mm
    const F_net_global = F_global.map((Fvec) => {
        const Fmag = Math.sqrt(Fvec[0] ** 2 + Fvec[1] ** 2 + Fvec[2] ** 2);
        if (Fmag <= F_friction_max) {
            // 마찰력으로 정지 (static friction)
            return [0, 0, 0];
        }
        else {
            // kinetic friction → F_friction를 빼준다
            const F_unit = Fvec.map(v => v / Fmag);
            const F_friction_vec = F_unit.map(v => v * F_friction_max);
            return Fvec.map((v, i) => v - F_friction_vec[i]);
        }
    });
    // 가속도
    const acc_global = F_net_global.map(f => f.map(v => v / m));
    const v_P_global = Array.from({ length: timeSteps }, () => [0, 0, 0]);
    const x_P_global = Array.from({ length: timeSteps }, () => [0, 0, 0]);
    for (let i = 1; i < timeSteps; i++) {
        v_P_global[i] = v_P_global[i - 1].map((v, j) => v + acc_global[i - 1][j] * dt);
        x_P_global[i] = x_P_global[i - 1].map((x, j) => x + v_P_global[i - 1][j] * dt);
    }
    const Q_matrix = [xvector, yvector, zvector];
    const Q_T = Q_matrix[0].map((_, colIndex) => Q_matrix.map(row => row[colIndex]));
    const r_PQ_global = r_Q_global.map((v, i) => v - r_P_global_0[i]);
    const r_PQ_principal = Q_T.map(row => dot(row, r_PQ_global));
    const F_principal = F_global.map(f => Q_T.map(row => dot(row, f)));
    const M_principal = F_principal.map(f => cross(r_PQ_principal, f));
    const h_P = r_P_global_0[1];
    const alpha_principal = M_principal.map(m => m.map((val, i) => val / I_principal[i]));
    const omega_principal = Array.from({ length: timeSteps }, () => [0, 0, 0]);
    for (let i = 1; i < timeSteps; i++) {
        omega_principal[i] = omega_principal[i - 1].map((v, j) => v + alpha_principal[i - 1][j] * dt);
    }
    const omega_global = omega_principal.map(w => Q_matrix.map(row => dot(row, w)));
    const alpha_global = alpha_principal.map(a => Q_matrix.map(row => dot(row, a)));
    const r_O_global = Array.from({ length: timeSteps }, () => [0, 0, 0]);
    r_O_global[0] = x_P_global[0];
    const eps = 1e-3;
    const maxDistance = 500;
    for (let i = 1; i < timeSteps; i++) {
        const omega = omega_global[i];
        const v_P = v_P_global[i];
        const omega_norm_sq = Math.max(dot(omega, omega), eps ** 2);
        const crossTerm = cross(omega, v_P.map(v => -v));
        const r_OP = crossTerm.map(v => v / omega_norm_sq);
        const r_OP_norm = Math.sqrt(dot(r_OP, r_OP));
        const r_OP_scaled = r_OP_norm > maxDistance
            ? r_OP.map(v => (v * maxDistance) / r_OP_norm)
            : r_OP;
        r_O_global[i] = x_P_global[i].map((v, j) => v + r_OP_scaled[j]);
    }
    // Generate grid points
    const xVals = [];
    const yVals = [];
    for (let i = 0; i < gridX; i++) {
        xVals.push(-width / 2 + (i / (gridX - 1)) * width);
    }
    for (let j = 0; j < gridY; j++) {
        yVals.push((j / (gridY - 1)) * height);
    }
    const gridPoints = [];
    for (let y of yVals) {
        for (let x of xVals) {
            gridPoints.push([x, y, 0]); // Top surface
        }
    }
    const magnitudeGrid = [];
    for (let t = 0; t < timeSteps; t++) {
        const R_t = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]; // Identity for now (no rotation integration here)
        const omega_t = omega_global[t];
        const alpha_t = alpha_global[t];
        const a_P_t = acc_global[t];
        const magnitudeRow = [];
        for (let p = 0; p < gridPoints.length; p++) {
            const r_BP0 = gridPoints[p].map((v, idx) => v - r_P_global_0[idx]);
            const r_BP_t = multiplyMatrixVector(R_t, r_BP0);
            const term2 = cross(alpha_t, r_BP_t);
            const term3 = cross(omega_t, cross(omega_t, r_BP_t));
            const a_B = a_P_t.map((val, idx) => val + term2[idx] + term3[idx]);
            const magnitude = Math.sqrt(a_B[0] ** 2 + a_B[1] ** 2 + a_B[2] ** 2) / 9.81 / 1000.0;
            magnitudeRow.push(magnitude);
        }
        // reshape into [ny, nx]
        const mag2D = [];
        for (let j = 0; j < gridY; j++) {
            mag2D.push(magnitudeRow.slice(j * gridX, (j + 1) * gridX));
        }
        magnitudeGrid.push(mag2D);
    }
    const a_B_average = magnitudeGrid.map(frame => frame.reduce((sum, row) => sum + row.reduce((s, v) => s + v, 0), 0) / (gridX * gridY));
    const rmsValue = Math.sqrt(a_B_average.reduce((sum, val) => sum + val * val, 0) / a_B_average.length);
    return {
        time,
        a_B_average,
        rmsValue,
        r_O_global,
        gridXVals: xVals,
        gridYVals: yVals,
        magnitudeGrid
    };
}
