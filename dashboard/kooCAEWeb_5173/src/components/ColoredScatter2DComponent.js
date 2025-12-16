import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Select, Card, Row, Col, Typography, Space, Modal, Table } from 'antd';
import Plot from 'react-plotly.js';
const { Option } = Select;
const { Title } = Typography;
const ColoredScatter2DComponent = ({ data, title = '2D Scatter Plot (Color Encoded)' }) => {
    const [headers, setHeaders] = useState([]);
    const [xKey, setXKey] = useState('');
    const [yKey, setYKey] = useState('');
    const [colorKey, setColorKey] = useState('');
    const [points, setPoints] = useState({ x: [], y: [], c: [], rest: [] });
    const [selectedData, setSelectedData] = useState([]);
    const [modalVisible, setModalVisible] = useState(false);
    useEffect(() => {
        if (data.length > 1) {
            const newHeaders = data[0].map(String);
            setHeaders(newHeaders);
            if (newHeaders.length >= 3) {
                setXKey(newHeaders[0]);
                setYKey(newHeaders[1]);
                setColorKey(newHeaders[2]);
            }
        }
    }, [data]);
    useEffect(() => {
        if (xKey && yKey && colorKey) {
            const idx = (k) => headers.indexOf(k);
            const xi = idx(xKey);
            const yi = idx(yKey);
            const ci = idx(colorKey);
            const x = [];
            const y = [];
            const c = [];
            const rest = [];
            for (let i = 1; i < data.length; i++) {
                const row = data[i];
                x.push(Number(row[xi]));
                y.push(Number(row[yi]));
                c.push(Number(row[ci]));
                rest.push(row);
            }
            setPoints({ x, y, c, rest });
        }
    }, [xKey, yKey, colorKey, data, headers]);
    const handleSelected = (event) => {
        if (!event || !event.points || event.points.length === 0)
            return;
        const selectedIndices = event.points.map((pt) => pt.pointIndex);
        const selected = selectedIndices.map((idx) => data[idx + 1]); // +1 to skip header row
        setSelectedData(selected);
        setModalVisible(true);
    };
    const columns = headers.map((h, i) => ({
        title: h,
        dataIndex: i.toString(),
        key: i.toString(),
    }));
    const dataSource = selectedData.map((row, i) => {
        const record = { key: i };
        row.forEach((val, j) => {
            record[j.toString()] = val;
        });
        return record;
    });
    return (_jsx(Card, { style: { width: '100%' }, children: _jsxs(Space, { direction: "vertical", style: { width: '100%' }, size: "large", children: [_jsx(Title, { level: 4, style: { margin: 0 }, children: title }), _jsxs(Row, { gutter: [16, 16], justify: "start", align: "middle", wrap: true, children: [_jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "X \uCD95" }) }), _jsx(Select, { value: xKey, onChange: setXKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] }), _jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "Y \uCD95" }) }), _jsx(Select, { value: yKey, onChange: setYKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] }), _jsxs(Col, { flex: "1", children: [_jsx("label", { children: _jsx("strong", { children: "Color \uCD95" }) }), _jsx(Select, { value: colorKey, onChange: setColorKey, style: { width: '100%' }, children: headers.map((h) => _jsx(Option, { value: h, children: h }, h)) })] })] }), _jsx("div", { style: { width: '100%' }, children: _jsx(Plot, { data: [{
                                x: points.x,
                                y: points.y,
                                mode: 'markers',
                                type: 'scatter',
                                marker: {
                                    size: 6,
                                    color: points.c,
                                    colorscale: 'Jet',
                                    colorbar: { title: { text: colorKey } },
                                },
                            }], layout: {
                            dragmode: 'lasso',
                            autosize: true,
                            height: 600,
                            margin: { l: 60, r: 40, b: 80, t: 20 },
                            xaxis: { title: { text: xKey } },
                            yaxis: { title: { text: yKey } },
                        }, config: { responsive: true }, onSelected: handleSelected, style: { width: '100%' } }) }), _jsx(Modal, { title: "\uC120\uD0DD\uB41C \uC810\uC758 \uB370\uC774\uD130", open: modalVisible, onCancel: () => setModalVisible(false), footer: null, width: 800, children: _jsx(Table, { columns: columns, dataSource: dataSource, pagination: { pageSize: 10 }, scroll: { x: true } }) })] }) }));
};
export default ColoredScatter2DComponent;
