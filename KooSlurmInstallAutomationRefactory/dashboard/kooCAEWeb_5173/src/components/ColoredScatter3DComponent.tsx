import React, { useEffect, useState } from 'react';
import { Select, Card, Row, Col, Typography, Space } from 'antd';
import Plot from 'react-plotly.js';

const { Option } = Select;
const { Title } = Typography;

interface ColoredScatter3DProps {
  data: (string | number)[][];
  title?: string;
}

const ColoredScatter3DComponent: React.FC<ColoredScatter3DProps> = ({ data, title = '4D Scatter Plot (Color Encoded)' }) => {
  const [headers, setHeaders] = useState<string[]>([]);
  const [xKey, setXKey] = useState<string>('');
  const [yKey, setYKey] = useState<string>('');
  const [zKey, setZKey] = useState<string>('');
  const [colorKey, setColorKey] = useState<string>('');
  const [points, setPoints] = useState<{ x: number[], y: number[], z: number[], c: number[] }>({ x: [], y: [], z: [], c: [] });

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
      const idx = (k: string) => headers.indexOf(k);
      const xi = idx(xKey);
      const yi = idx(yKey);
      const zi = idx(zKey);
      const ci = idx(colorKey);

      const x: number[] = [];
      const y: number[] = [];
      const z: number[] = [];
      const c: number[] = [];

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

  return (
    <Card style={{ width: '100%' }}>
      <Space direction="vertical" style={{ width: '100%' }} size="large">
        <Title level={4} style={{ margin: 0 }}>{title}</Title>

        <Row gutter={[16, 16]} justify="start" align="middle" wrap>
          <Col flex="1">
            <label><strong>X 축</strong></label>
            <Select value={xKey} onChange={setXKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}
            </Select>
          </Col>
          <Col flex="1">
            <label><strong>Y 축</strong></label>
            <Select value={yKey} onChange={setYKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}
            </Select>
          </Col>
          <Col flex="1">
            <label><strong>Z 축</strong></label>
            <Select value={zKey} onChange={setZKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}
            </Select>
          </Col>
          <Col flex="1">
            <label><strong>Color 축</strong></label>
            <Select value={colorKey} onChange={setColorKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}
            </Select>
          </Col>
        </Row>

        <div style={{ width: '100%' }}>
          <Plot
            data={[
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
            ]}
            layout={{
              autosize: true,
              height: 600,
              margin: { l: 0, r: 0, b: 0, t: 0 },
              scene: {
                xaxis: { title: { text: xKey } },
                yaxis: { title: { text: yKey } },
                zaxis: { title: { text: zKey } },
              },
            }}
            style={{ width: '100%' }}
            config={{ responsive: true }}
          />
        </div>
      </Space>
    </Card>
  );
};

export default ColoredScatter3DComponent;
