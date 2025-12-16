import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import Plot from 'react-plotly.js';
/**
 * 🔷  ParallelCoordinatesPlotComponent
 *   - 축 : roll, pitch, yaw, stress
 *   - 색 : entity index를 기반으로 연속형 색상 매핑
 */
const ParallelCoordinatesPlotComponent = ({ data, angleKeys = ['roll', 'pitch', 'yaw'], valueKey = 'stress', title = 'Parallel Coordinates Plot', }) => {
    const numEntities = data.entities.length;
    const numConditions = data.conditions.length;
    const records = [];
    const entityIndices = [];
    data.entities.forEach((entity, pIdx) => {
        for (let cIdx = 0; cIdx < numConditions; cIdx++) {
            const rec = {};
            angleKeys.forEach((k) => (rec[k] = data.conditions[cIdx][k]));
            rec[valueKey] = data.getValue(pIdx, cIdx);
            records.push(rec);
            entityIndices.push(pIdx); // 각 조합의 엔티티 인덱스 저장
        }
    });
    const dimensions = [
        ...angleKeys.map((k) => ({
            label: k,
            values: records.map((r) => r[k]),
        })),
        {
            label: valueKey,
            values: records.map((r) => r[valueKey]),
        },
    ];
    return (_jsxs("div", { style: { width: '100%' }, children: [_jsx("h3", { style: { textAlign: 'center' }, children: title }), _jsx(Plot, { data: [
                    {
                        type: 'parcoords',
                        line: {
                            color: entityIndices,
                            colorscale: 'Jet',
                            showscale: true,
                            colorbar: {
                                title: 'Part Index',
                            },
                        },
                        dimensions: dimensions,
                    },
                ], layout: {
                    autosize: true,
                    height: 500,
                    margin: { l: 60, r: 30, b: 40, t: 40 },
                }, config: { responsive: true }, style: { width: '100%' } })] }));
};
export default ParallelCoordinatesPlotComponent;
