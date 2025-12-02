import React, { useEffect, useState } from 'react';
import { Select, Card, Row, Col, Typography, Space } from 'antd';
import Plot from 'react-plotly.js';

const { Option } = Select;
const { Title } = Typography;

interface Scatter3DProps {
  data: (string | number)[][]; // 첫 행은 헤더, 나머지는 숫자 데이터
  title?: string; // 외부로부터 받는 타이틀
}

const Scatter3DComponent: React.FC<Scatter3DProps> = ({ data, title = '3D Scatter Plot' }) => {
  const [headers, setHeaders] = useState<string[]>([]);
  const [xKey, setXKey] = useState<string>('');
  const [yKey, setYKey] = useState<string>('');
  const [zKey, setZKey] = useState<string>('');
  const [xData, setXData] = useState<number[]>([]);
  const [yData, setYData] = useState<number[]>([]);
  const [zData, setZData] = useState<number[]>([]);

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
      const headerIndex = (key: string) => headers.indexOf(key);
      const xIdx = headerIndex(xKey);
      const yIdx = headerIndex(yKey);
      const zIdx = headerIndex(zKey);

      const parsedX: number[] = [];
      const parsedY: number[] = [];
      const parsedZ: number[] = [];

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

  return (
    <Card style={{ width: '100%' }}>
      <Space direction="vertical" style={{ width: '100%' }} size="large">
        <Title level={4} style={{ margin: 0 }}>{title}</Title>

        <Row gutter={[16, 16]} justify="start" align="middle">
          <Col>
            <label><strong>X 축</strong></label>
            <Select value={xKey} onChange={setXKey} style={{ width: 120 }}>
              {headers.map((h) => (
                <Option key={h} value={h}>{h}</Option>
              ))}
            </Select>
          </Col>
          <Col>
            <label><strong>Y 축</strong></label>
            <Select value={yKey} onChange={setYKey} style={{ width: 120 }}>
              {headers.map((h) => (
                <Option key={h} value={h}>{h}</Option>
              ))}
            </Select>
          </Col>
          <Col>
            <label><strong>Z 축</strong></label>
            <Select value={zKey} onChange={setZKey} style={{ width: 120 }}>
              {headers.map((h) => (
                <Option key={h} value={h}>{h}</Option>
              ))}
            </Select>
          </Col>
        </Row>

        <div style={{ width: '100%' }}>
          <Plot
            data={[
              {
                x: xData,
                y: yData,
                z: zData,
                mode: 'markers',
                type: 'scatter3d',
                marker: { size: 4, color: 'blue' },
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

export default Scatter3DComponent;
