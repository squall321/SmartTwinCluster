import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import Plot from 'react-plotly.js';
const HeatmapMatrixComponent = ({ data, title = 'Measurement Heatmap', xLabelKeys }) => {
    const numEntities = data.entities.length;
    const numConditions = data.conditions.length;
    // x축 라벨: 조건 조합 문자열 생성
    const xLabels = data.conditions.map((cond, i) => {
        if (xLabelKeys && xLabelKeys.length > 0) {
            return xLabelKeys.map((key) => `${key}:${cond[key]?.toFixed(1) ?? '?'}`).join(', ');
        }
        return `Cond_${i}`;
    });
    // y축 라벨: entity 이름
    const yLabels = data.entities;
    // z값 구성 (행: entity, 열: condition)
    const zValues = [];
    for (let i = 0; i < numEntities; i++) {
        const row = [];
        for (let j = 0; j < numConditions; j++) {
            row.push(data.getValue(i, j));
        }
        zValues.push(row);
    }
    return (_jsxs("div", { children: [_jsx("h3", { style: { textAlign: 'center' }, children: title }), _jsx(Plot, { data: [
                    {
                        z: zValues,
                        x: xLabels,
                        y: yLabels,
                        type: 'heatmap',
                        colorscale: 'Jet',
                        colorbar: {
                            title: { text: 'Value' },
                        },
                        hoverongaps: false,
                    },
                ], layout: {
                    autosize: true,
                    height: 500,
                    margin: { l: 100, r: 50, b: 150, t: 30 },
                    xaxis: {
                        title: { text: xLabelKeys ? xLabelKeys.join(' + ') : 'Condition' },
                        tickangle: -45,
                        automargin: true,
                    },
                    yaxis: {
                        title: { text: 'Entity' },
                        automargin: true,
                    },
                }, config: { responsive: true }, style: { width: '100%' } })] }));
};
export default HeatmapMatrixComponent;
