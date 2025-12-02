import React, { useEffect, useState } from 'react';
import { Select, Card, Row, Col, Typography, Space, Modal, Table } from 'antd';
import Plot from 'react-plotly.js';

const { Option } = Select;
const { Title } = Typography;

interface ColoredScatter2DProps {
  data: (string | number)[][];
  title?: string;
}

const ColoredScatter2DComponent: React.FC<ColoredScatter2DProps> = ({ data, title = '2D Scatter Plot (Color Encoded)' }) => {
  const [headers, setHeaders] = useState<string[]>([]);
  const [xKey, setXKey] = useState<string>('');
  const [yKey, setYKey] = useState<string>('');
  const [colorKey, setColorKey] = useState<string>('');
  const [points, setPoints] = useState<{ x: number[], y: number[], c: number[], rest: (string | number)[][] }>({ x: [], y: [], c: [], rest: [] });
  const [selectedData, setSelectedData] = useState<(string | number)[][]>([]);
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
      const idx = (k: string) => headers.indexOf(k);
      const xi = idx(xKey);
      const yi = idx(yKey);
      const ci = idx(colorKey);

      const x: number[] = [];
      const y: number[] = [];
      const c: number[] = [];
      const rest: (string | number)[][] = [];

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

  const handleSelected = (event: Readonly<Plotly.PlotSelectionEvent>) => {
    if (!event || !event.points || event.points.length === 0) return;
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
    const record: any = { key: i };
    row.forEach((val, j) => {
      record[j.toString()] = val;
    });
    return record;
  });

  return (
    <Card style={{ width: '100%' }}>
      <Space direction="vertical" style={{ width: '100%' }} size="large">
        <Title level={4} style={{ margin: 0 }}>{title}</Title>

        <Row gutter={[16, 16]} justify="start" align="middle" wrap>
          <Col flex="1">
            <label><strong>X 축</strong></label>
            <Select value={xKey} onChange={setXKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}</Select>
          </Col>
          <Col flex="1">
            <label><strong>Y 축</strong></label>
            <Select value={yKey} onChange={setYKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}</Select>
          </Col>
          <Col flex="1">
            <label><strong>Color 축</strong></label>
            <Select value={colorKey} onChange={setColorKey} style={{ width: '100%' }}>
              {headers.map((h) => <Option key={h} value={h}>{h}</Option>)}</Select>
          </Col>
        </Row>

        <div style={{ width: '100%' }}>
          <Plot
            data={[{
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
            }]}
            layout={{
              dragmode: 'lasso',
              autosize: true,
              height: 600,
              margin: { l: 60, r: 40, b: 80, t: 20 },
              xaxis: { title: { text: xKey } },
              yaxis: { title: { text: yKey } },
            }}
            config={{ responsive: true }}
            onSelected={handleSelected}
            style={{ width: '100%' }}
          />
        </div>

        <Modal
          title="선택된 점의 데이터"
          open={modalVisible}
          onCancel={() => setModalVisible(false)}
          footer={null}
          width={800}
        >
          <Table
            columns={columns}
            dataSource={dataSource}
            pagination={{ pageSize: 10 }}
            scroll={{ x: true }}
          />
        </Modal>
      </Space>
    </Card>
  );
};

export default ColoredScatter2DComponent;