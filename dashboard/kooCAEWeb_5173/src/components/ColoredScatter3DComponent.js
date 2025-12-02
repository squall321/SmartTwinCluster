import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Select, Card, Row, Col, Typography, Space } from 'antd';
import Plot from 'react-plotly.js';
const { Option } = Select;
const { Title } = Typography;
const ColoredScatter3DComponent = ({ data, title = '4D Scatter Plot (Color Encoded)' }) => {
    const [headers, setHeaders] = useState([]);
    const [xKey, setXKey] = useState('');
    const [yKey, setYKey] = useState('');
    const [zKey, setZKey] = useState('');
    const [colorKey, setColorKey] = useState('');
    const [points, setPoints] = useState({ x: [], y: [], z: [], c: [] });
    useEffect(() => {
        if (data.length > 1) {
            const newHeaders = data[0].map(String);
            setHeaders(newHeaders);
            if (newHeaders.length >= 4) {
                setXKey(newHeaders[0]);
                setYKey(newHeaders[1]);
                setZKey(newHeaders[2]);
                setColorKey(newHeaders[3]);
            }
        }
    }, [data]);
    useEffect(() => {
        if (xKey && yKey && zKey && colorKey) {
            const idx = (k) => headers.indexOf(k);
            const xi = idx(xKey);
            const yi = idx(yKey);
            const zi = idx(zKey);
            const ci = idx(colorKey);
            const x = [];
            const y = [];
            const z = [];
            const c = [];
            for (let i = 1; i < data.length; i++) {
                const row = data[i];
                x.push(Number(row[xi]));
                y.push(Number(row[yi]));
                z.push(Number(row[zi]));
                c.push(Number(row[ci]));
            }
            setPoints({ x, y, z, c });
        }
    }, [xKey, yKey, zKey, colorKey, data, headers]);
    return (_jsx(Card, { style: { width: '100%' }, children: _jsxs(Space, { direction: "vertical", style: { width: '100%' }, size: "large", children: [_jsx(Title, { level: 4, style: { margin: 0 }, children: title }), _jsxs(Row, { gutter: [16, 16], justify: "start", align: "middle", wrap: true, children: [_jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "X \uCD95" }) }), _jsx(Select, { value: xKey, onChange: setXKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] }), _jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "Y \uCD95" }) }), _jsx(Select, { value: yKey, onChange: setYKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] }), _jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "Z \uCD95" }) }), _jsx(Select, { value: zKey, onChange: setZKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] }), _jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "Color \uCD95" }) }), _jsx(Select, { value: colorKey, onChange: setColorKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] })] }), _jsx("div", { style: { width: '100%' }, children: _jsx(Plot, { data: [
                            {
                                x: points.x,
                                y: points.y,
                                z: points.z,
                                mode: 'markers',
                                type: 'scatter3d',
                                marker: {
                                    size: 4,
                                    color: points.c,
                                    colorscale: 'Jet',
                                    colorbar: { title: { text: colorKey } },
                                },
                            },
                        ], layout: {
                            autosize: true,
                            height: 600,
                            margin: { l: 0, r: 0, b: 0, t: 0 },
                            scene: {
                                xaxis: { title: { text: xKey } },
                                yaxis: { title: { text: yKey } },
                                zaxis: { title: { text: zKey } },
                            },
                        }, style: { width: '100%' }, config: { responsive: true } }) })] }) }));
};
export default ColoredScatter3DComponent;
