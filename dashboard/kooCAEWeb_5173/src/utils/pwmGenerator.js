export function generatePWM(config) {
    const { targetFrequency, sinAmplitude, dt, duration, channels } = config;
    const t = [];
    const size = Math.floor(duration / dt);
    for (let i = 0; i < size; i++) {
        t.push(i * dt);
    }
    const SinX = t.map(time => sinAmplitude * Math.sin(2 * Math.PI * targetFrequency * time));
    const SawX = [];
    channels.forEach((ch) => {
        const imax = Math.round((1 / ch.frequency) / dt);
        let ith = 1;
        const saw = new Array(t.length).fill(0);
        while (ith < t.length) {
            for (let i = 1; i <= Math.round(imax / 2); i++) {
                if (ith >= t.length)
                    break;
                saw[ith] =
                    -ch.amplitude +
                        (ch.coefficient * ch.amplitude) /
                            (2.0 / ch.frequency) *
                            (i - 1) *
                            dt;
                ith++;
            }
            for (let i = Math.round(imax / 2) + 1; i <= imax; i++) {
                if (ith >= t.length)
                    break;
                saw[ith] =
                    ch.amplitude -
                        (ch.coefficient * ch.amplitude) /
                            (2.0 / ch.frequency) *
                            (i - imax / 2.0 - 1) *
                            dt;
                ith++;
            }
        }
        SawX.push(saw);
    });
    let PWM = new Array(t.length).fill(0);
    channels.forEach((ch, j) => {
        if (!ch.enabled)
            return;
        for (let i = 0; i < t.length; i++) {
            if (j === 0) {
                if (SinX[i] >= 0) {
                    PWM[i] = SinX[i] - SawX[j][i] >= 0 ? ch.amplitude : 0;
                }
                else {
                    PWM[i] = SinX[i] - SawX[j][i] < 0 ? -ch.amplitude : 0;
                }
            }
            else {
                if (PWM[i] >= 0) {
                    PWM[i] = SinX[i] - SawX[j][i] >= 0 ? PWM[i] : 0;
                }
                else {
                    PWM[i] = SinX[i] - SawX[j][i] < 0 ? PWM[i] : 0;
                }
            }
        }
    });
    return {
        t,
        SinX,
        SawX,
        PWM
    };
}
