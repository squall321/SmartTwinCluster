import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Select, Card, Row, Col, Typography, Space } from 'antd';
import Plot from 'react-plotly.js';
const { Option } = Select;
const { Title } = Typography;
const Scatter3DComponent = ({ data, title = '3D Scatter Plot' }) => {
    const [headers, setHeaders] = useState([]);
    const [xKey, setXKey] = useState('');
    const [yKey, setYKey] = useState('');
    const [zKey, setZKey] = useState('');
    const [xData, setXData] = useState([]);
    const [yData, setYData] = useState([]);
    const [zData, setZData] = useState([]);
    useEffect(() => {
        if (data.length > 1) {
            const newHeaders = data[0].map(String);
            setHeaders(newHeaders);
            if (newHeaders.length >= 3) {
                setXKey(newHeaders[0]);
                setYKey(newHeaders[1]);
                setZKey(newHeaders[2]);
            }
        }
    }, [data]);
    useEffect(() => {
        if (xKey && yKey && zKey) {
            const headerIndex = (key) => headers.indexOf(key);
            const xIdx = headerIndex(xKey);
            const yIdx = headerIndex(yKey);
            const zIdx = headerIndex(zKey);
            const parsedX = [];
            const parsedY = [];
            const parsedZ = [];
            for (let i = 1; i < data.length; i++) {
                const row = data[i];
                parsedX.push(Number(row[xIdx]));
                parsedY.push(Number(row[yIdx]));
                parsedZ.push(Number(row[zIdx]));
            }
            setXData(parsedX);
            setYData(parsedY);
            setZData(parsedZ);
        }
    }, [xKey, yKey, zKey, data, headers]);
    return (_jsx(Card, { style: { width: '100%' }, children: _jsxs(Space, { direction: "vertical", style: { width: '100%' }, size: "large", children: [_jsx(Title, { level: 4, style: { margin: 0 }, children: title }), _jsxs(Row, { gutter: [16, 16], justify: "start", align: "middle", children: [_jsxs(Col, { children: [_jsx("label", { children: _jsx("strong", { children: "X \uCD95" }) }), _jsx(Select, { value: xKey, onChange: setXKey, style: { width: 120 }, children: headers.map((h) => (_jsx(Option, { value: h, children: h }, h))) })] }), _jsxs(Col, { children: [_jsx("label", { children: _jsx("strong", { children: "Y \uCD95" }) }), _jsx(Select, { value: yKey, onChange: setYKey, style: { width: 120 }, children: headers.map((h) => (_jsx(Option, { value: h, children: h }, h))) })] }), _jsxs(Col, { children: [_jsx("label", { children: _jsx("strong", { children: "Z \uCD95" }) }), _jsx(Select, { value: zKey, onChange: setZKey, style: { width: 120 }, children: headers.map((h) => (_jsx(Option, { value: h, children: h }, h))) })] })] }), _jsx("div", { style: { width: '100%' }, children: _jsx(Plot, { data: [
                            {
                                x: xData,
                                y: yData,
                                z: zData,
                                mode: 'markers',
                                type: 'scatter3d',
                                marker: { size: 4, color: 'blue' },
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
export default Scatter3DComponent;
