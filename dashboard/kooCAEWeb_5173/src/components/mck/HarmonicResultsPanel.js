import { jsx as _jsx } from "react/jsx-runtime";
import { Card } from 'antd';
import { Line } from '@ant-design/plots';
const HarmonicResultsPanel = ({ result }) => {
    const data = [];
    result.frequency.forEach((freq, idx) => {
        result.magnitudeDB.forEach((magArr, massIdx) => {
            data.push({
                freq,
                value: magArr[idx],
                series: `Node ${massIdx + 1}`,
            });
        });
    });
    const config = {
        data,
        xField: 'freq',
        yField: 'value',
        seriesField: 'series',
        smooth: true,
        height: 300,
        yAxis: {
            title: { text: 'Magnitude (dB)' },
        },
        xAxis: {
            title: { text: 'Frequency (Hz)' },
        },
    };
    return (_jsx(Card, { title: "Harmonic Response Result", size: "small", style: { marginTop: 16 }, children: _jsx(Line, { ...config }) }));
};
export default HarmonicResultsPanel;
