import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import ColoredScatter2DComponent from '../components/ColoredScatter2DComponent';
import Scatter3DComponent from '../components/Scatter3DComponent';
import ColoredScatter3DComponent from '../components/ColoredScatter3DComponent';
import HeatmapMatrixComponent from '../components/HeatmapMatrixComponent';
import LineChartPerEntityComponent from '../components/LineChartPerEntityComponent';
import ParallelCoordinatesPlotComponent from '../components/ParallelCoordinatesPlotComponent';
const { Title, Paragraph } = Typography;
const ComponentTestPage = () => {
    /////////////// Scatter Data Test Set
    const data = [
        ['x', 'y', 'z', 'w', 'v'],
        ...Array.from({ length: 30 }, () => {
            const x = +(Math.random() * 100).toFixed(2);
            const y = +(Math.random() * 100).toFixed(2);
            const z = +(Math.random() * 100).toFixed(2);
            const w = +(x * y + z).toFixed(2);
            const v = +Math.sin(x + y + z).toFixed(4);
            return [x, y, z, w, v];
        }),
    ];
    ///////////// StressDB Test Set
    const NUM_PARTS = 20;
    const NUM_ANGLES = 30;
    // 1) 부품 ID
    const parts = Array.from({ length: NUM_PARTS }, (_, i) => `Part_${i + 1}`);
    // 2) 오일러 각 30개 (임의 분포 예시)
    const angleSets = Array.from({ length: NUM_ANGLES }, () => ({
        roll: (Math.random() * 360 - 180).toFixed(2), // -180° ~ 180°
        pitch: (Math.random() * 180 - 90).toFixed(2), //  -90° ~  90°
        yaw: (Math.random() * 360 - 180).toFixed(2), // -180° ~ 180°
    })).map(a => ({ roll: +a.roll, pitch: +a.pitch, yaw: +a.yaw }));
    // 3) 응력 값  (예:  0 ~ 500 MPa   난수)
    const stress = new Float32Array(NUM_PARTS * NUM_ANGLES);
    for (let p = 0; p < NUM_PARTS; p++) {
        for (let a = 0; a < NUM_ANGLES; a++) {
            const idx = p * NUM_ANGLES + a;
            stress[idx] = +(Math.random() * 500).toFixed(2);
        }
    }
    // 4) helper
    const db = {
        entities: parts,
        conditions: angleSets,
        values: stress,
        getValue: (p, a) => stress[p * NUM_ANGLES + a],
        setValue: (p, a, v) => { stress[p * NUM_ANGLES + a] = v; },
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                width: '100%',
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDCE6 Component Test" }), _jsx(Paragraph, { children: "\uC0C8\uB85C \uAC1C\uBC1C\uB41C Component\uB97C \uD14C\uC2A4\uD2B8\uD558\uAE30 \uC704\uD55C \uD398\uC774\uC9C0\uC785\uB2C8\uB2E4." }), _jsxs("div", { style: { padding: '20px' }, children: [_jsx("div", { style: { marginBottom: '30px' }, children: _jsx(ColoredScatter2DComponent, { title: "Colored Scatter 2D Component", data: data }) }), _jsx("div", { style: { marginBottom: '30px' }, children: _jsx(Scatter3DComponent, { title: "Scatter 3D Component", data: data }) }), _jsx("div", { style: { marginBottom: '30px' }, children: _jsx(ColoredScatter3DComponent, { title: "Colored Scatter 3D Component", data: data }) }), _jsx("div", { style: { marginBottom: '30px' }, children: _jsx(HeatmapMatrixComponent, { title: "Heatmap Matrix Component", data: db, xLabelKeys: ['roll', 'pitch', 'yaw'] }) }), _jsx("div", { style: { marginBottom: '30px' }, children: _jsx(LineChartPerEntityComponent, { title: "Line Chart Per Entity Component", data: db, xLabelKeys: ['roll', 'pitch', 'yaw'] }) }), _jsx("div", { style: { marginBottom: '30px' }, children: _jsx(ParallelCoordinatesPlotComponent, { data: db, angleKeys: ['roll', 'pitch', 'yaw'], valueKey: "stress", title: "Euler Angles & Stress\u2006\u2014\u2006Parallel Coordinates" }) })] })] }) }));
};
export default ComponentTestPage;
