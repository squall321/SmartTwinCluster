import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Upload, Button, Table, InputNumber, Space, Form, message, Popconfirm, Spin } from 'antd';
import { InboxOutlined, PlusOutlined, DeleteOutlined, DownloadOutlined } from '@ant-design/icons';
import Plot from 'react-plotly.js';
import { generateDropAttitudeOptionFile } from '../components/shared/utils';
import ExportMeshModifierButton from '../components/shared/ExportMeshModifierButtonProps';

const { Title } = Typography;

const defaultOptions = {
  OffsetDistance: 0.1,
  Density: 2700,
  YoungsModulus: 70e9,
  PoissonRatio: 0.3,
  tFinal: 1.0e-3,
  dt: 1.0e-6,
};

const optionLabels: Record<string, string> = {
  OffsetDistance: '벽면까지 초기 거리 (m)',
  Density: '밀도 (kg/m³)',
  YoungsModulus: '탄성계수(GPa)',
  PoissonRatio: '푸아송비(비율)',
  tFinal: '종료 시간(Tfinal, s)',
  dt: '시간 간격(dt, s)',
};

const initialRow = {
  EulerRolling: 0,
  EulerPitching: 0,
  EulerYawing: 0,
  Height: 1220,
  InitialVelocityX: 0,
  InitialVelocityY: 0,
  InitialVelocityZ: 0,
  InitialAngularVelocityX: 0,
  InitialAngularVelocityY: 0,
  InitialAngularVelocityZ: 0,
};



const DropAttitudeGenerator = () => {
  const [kFile, setKFile] = useState<File | null>(null);
  const [tableData, setTableData] = useState<any[]>([initialRow]);
  const [options, setOptions] = useState(defaultOptions);
  const [randomCount, setRandomCount] = useState(5);
  const [loading, setLoading] = useState(false);
  const fullPlotBoxStyle: React.CSSProperties = { width: '100%', height: 500, minWidth: 0 };
  const fullPlotStyle: React.CSSProperties = { width: '100%', height: '100%' };
  

  const handleAddRow = () => {
    setTableData([...tableData, { ...initialRow }]);
  };

  const handleDeleteRow = (indexToRemove: number) => {
    const newData = tableData.filter((_, idx) => idx !== indexToRemove);
    setTableData(newData);
  };

  const handleClearAllRows = () => {
    setTableData([]);
  };

  const handleAddPredefinedRows = (angles: number[][]) => {
    const newRows = angles.map(([roll, pitch, yaw]) => ({
      ...initialRow,
      Height: 1500,
      EulerRolling: roll,
      EulerPitching: pitch,
      EulerYawing: yaw,
    }));
    setTableData([...tableData, ...newRows]);
  };

  const handleOptionChange = (key: string, value: number) => {
    setOptions({ ...options, [key]: value });
  };
  /*
  const handleExport = () => {
    const fields = Object.keys(initialRow);
    let content = '*Inputfile\n';
    content += `${kFile?.name || 'UNKNOWN.k'}\n`;
    content += '*Mode\n';
    content += 'DROP_ATTITUDE,1\n';
    content += '**DropAttitude,1\n';

    fields.forEach(field => {
      content += field + ',' + tableData.map(row => row[field]).join(',') + '\n';
    });

    Object.entries(options).forEach(([key, value]) => {
      content += `${key},${value}\n`;
    });

    content += '**EndDropAttitude\n*End';

    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'drop_attitude.txt';
    link.click();
  };*/

  const columnNameMap: Record<string, React.ReactNode> = {
    EulerRolling: <div style={{ textAlign: 'center' }}>Roll<br />(롤)</div>,
    EulerPitching: <div style={{ textAlign: 'center' }}>Pitch<br />(피치)</div>,
    EulerYawing: <div style={{ textAlign: 'center' }}>Yaw<br />(요)</div>,
    Height: <div style={{ textAlign: 'center' }}>높이<br />(mm)</div>,
    InitialVelocityX: <div style={{ textAlign: 'center' }}>Vx<br />(mm/s)</div>,
    InitialVelocityY: <div style={{ textAlign: 'center' }}>Vy<br />(mm/s)</div>,
    InitialVelocityZ: <div style={{ textAlign: 'center' }}>Vz<br />(mm/s)</div>,
    InitialAngularVelocityX: <div style={{ textAlign: 'center' }}>ωx<br />(rad/s)</div>,
    InitialAngularVelocityY: <div style={{ textAlign: 'center' }}>ωy<br />(rad/s)</div>,
    InitialAngularVelocityZ: <div style={{ textAlign: 'center' }}>ωz<br />(rad/s)</div>,
  };

  const columns = [
    ...Object.keys(initialRow).map((key) => ({
      title: columnNameMap[key] || key,
      dataIndex: key,
      align: 'center' as const,
      width: 50,
      render: (_: any, record: any, index: number) => (
        <InputNumber
          size="small"
          style={{ width: '80px', textAlign: 'center' }}
          value={record[key]}
          onChange={(value) => {
            const newData = [...tableData];
            newData[index][key] = value;
            setTableData(newData);
          }}
        />
      ),
    })),
    {
      title: '삭제',
      dataIndex: 'delete',
      align: 'center' as const,
      width: 60,
      render: (_: any, __: any, index: number) => (
        <Popconfirm title="이 행을 삭제하시겠습니까?" onConfirm={() => handleDeleteRow(index)}>
          <Button icon={<DeleteOutlined />} size="small" danger />
        </Popconfirm>
      ),
    },
  ];

  const plotData = [{
    x: tableData.map(d => d.EulerRolling),
    y: tableData.map(d => d.EulerPitching),
    z: tableData.map(d => d.EulerYawing),
    mode: 'markers',
    type: 'scatter3d',
    marker: { size: 4, color: tableData.map(d => d.Height), colorscale: 'Viridis' },
  }];

  const plotLayout = {
    margin: { l: 0, r: 0, b: 0, t: 0 },
    autosize: true,
    scene: {
      xaxis: { title: 'Roll (°)' },
      yaxis: { title: 'Pitch (°)' },
      zaxis: { title: 'Yaw (°)' },
    },
  };
  
  // boxLayout도 동일 처리
  const boxLayout = {
    margin: { l: 0, r: 0, b: 0, t: 0 },
    autosize: true,
    scene: {
      xaxis: { title: 'X', scaleanchor: 'y' },
      yaxis: { title: 'Y', scaleanchor: 'z' },
      zaxis: { title: 'Z' },
      aspectmode: 'data',
    },
  };

  const boxData = tableData.flatMap((row, index) => {
    const angleToRad = (angle: number) => angle * Math.PI / 180;
    const rx = angleToRad(row.EulerRolling);
    const ry = angleToRad(row.EulerPitching);
    const rz = angleToRad(row.EulerYawing);
    const size = { x: 70, y: 150, z: 8 };
  
    // ✅ 정방형 그리드 좌표 계산
    const total = tableData.length;
    const cols = Math.ceil(Math.sqrt(total));
    const spacingX = 250.0;
    const spacingY = 250.0;
    const rowIdx = Math.floor(index / cols);
    const colIdx = index % cols;
    const offsetX = colIdx * spacingX;
    const offsetY = -rowIdx * spacingY;
    const offsetZ = row.Height;
  
    const corners = [
      [-size.x / 2, -size.y / 2, -size.z / 2],
      [size.x / 2, -size.y / 2, -size.z / 2],
      [size.x / 2, size.y / 2, -size.z / 2],
      [-size.x / 2, size.y / 2, -size.z / 2],
      [-size.x / 2, -size.y / 2, size.z / 2],
      [size.x / 2, -size.y / 2, size.z / 2],
      [size.x / 2, size.y / 2, size.z / 2],
      [-size.x / 2, size.y / 2, size.z / 2],
    ];
  
    const rotate = (v: number[]) => {
      let [x, y, z] = v;
      [y, z] = [y * Math.cos(rx) - z * Math.sin(rx), y * Math.sin(rx) + z * Math.cos(rx)];
      [x, z] = [x * Math.cos(ry) + z * Math.sin(ry), -x * Math.sin(ry) + z * Math.cos(ry)];
      [x, y] = [x * Math.cos(rz) - y * Math.sin(rz), x * Math.sin(rz) + y * Math.cos(rz)];
      return [x + offsetX, y + offsetY, z + offsetZ];
    };
  
    const vertices = corners.map(rotate);
  
    const frontFace = [[0, 1, 2], [0, 2, 3]];
    const topFace = [[2, 3, 7], [2, 7, 6]];
    const otherFaces = [
      [4, 5, 6], [4, 6, 7],
      [0, 1, 5], [0, 5, 4],
      [1, 2, 6], [1, 6, 5],
      [3, 0, 4], [3, 4, 7],
    ];
  
    const meshFront = {
      type: 'mesh3d',
      x: vertices.map(v => v[0]),
      y: vertices.map(v => v[1]),
      z: vertices.map(v => v[2]),
      i: frontFace.map(f => f[0]),
      j: frontFace.map(f => f[1]),
      k: frontFace.map(f => f[2]),
      color: 'red',
      opacity: 1.0,
      name: `Front ${index}`,
      showscale: false,
    };
  
    const meshTop = {
      type: 'mesh3d',
      x: vertices.map(v => v[0]),
      y: vertices.map(v => v[1]),
      z: vertices.map(v => v[2]),
      i: topFace.map(f => f[0]),
      j: topFace.map(f => f[1]),
      k: topFace.map(f => f[2]),
      color: 'blue',
      opacity: 1.0,
      name: `Top ${index}`,
      showscale: false,
    };
  
    const meshOthers = {
      type: 'mesh3d',
      x: vertices.map(v => v[0]),
      y: vertices.map(v => v[1]),
      z: vertices.map(v => v[2]),
      i: otherFaces.map(f => f[0]),
      j: otherFaces.map(f => f[1]),
      k: otherFaces.map(f => f[2]),
      color: 'gray',
      opacity: 1.0,
      name: `Body ${index}`,
      showscale: false,
    };
  
    return [meshOthers, meshFront, meshTop];
  });
  

  const parseDropAttitudeFile = (text: string) => {
    try {
      const lines = text
        .split(/\r?\n/)
        .map(line => line.trim())
        .filter(line => line.length > 0);
  
      const tableFields: Record<string, number[]> = {};
      const optionsData: Record<string, number> = {};
      
      let inDropAttitude = false;
  
      for (const line of lines) {
        if (line.startsWith("**DropAttitude")) {
          inDropAttitude = true;
          continue;
        }
        if (line.startsWith("**EndDropAttitude")) {
          inDropAttitude = false;
          continue;
        }
        if (inDropAttitude) {
          const [key, ...values] = line.split(",").map(s => s.trim());
          tableFields[key] = values.map(v => parseFloat(v));
        } else {
          if (line.includes(",")) {
            const [key, value] = line.split(",").map(s => s.trim());
            if (key in defaultOptions) {
              optionsData[key] = parseFloat(value);
            }
          }
        }
      }
  
      const numRows = Object.values(tableFields)[0]?.length || 0;
      const rows = Array.from({ length: numRows }, (_, i) => {
        const row: any = {};
        for (const key of Object.keys(initialRow)) {
          row[key] = tableFields[key] ? tableFields[key][i] : 0;
        }
        return row;
      });
  
      setTableData(rows);
      setOptions({ ...defaultOptions, ...optionsData });
      message.success("옵션 파일을 불러왔습니다!");
    } catch (error) {
      console.error(error);
      message.error("옵션 파일 파싱 중 오류가 발생했습니다.");
    } finally {
      setLoading(false);
    }
  };
  
       
  

  return (
    <BaseLayout isLoggedIn={true}>
      <Spin spinning={loading} tip="옵션 파일 불러오는 중...">

      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>🧭 낙하 자세 생성기</Title>

        <Upload.Dragger
          multiple={false}
          accept=".k"
          beforeUpload={(file) => {
            setLoading(true);
            setTimeout(() => {
              setKFile(file);
              message.success(`${file.name} 선택됨`);
              setLoading(false);
            }, 0);
            return false;
          }}
          style={{ marginBottom: '2rem' }}
        >
          <p className="ant-upload-drag-icon"><InboxOutlined /></p>
          <p className="ant-upload-text">기본 해석용 .k 파일을 업로드하세요</p>
        </Upload.Dragger>

        <Upload.Dragger
          multiple={false}
          accept=".txt"
          beforeUpload={(file) => {
            setLoading(true);
            setTimeout(() => {
              const reader = new FileReader();
              reader.onload = (e) => {
                const content = e.target?.result as string;
                parseDropAttitudeFile(content);
                setLoading(false);
              };
              reader.onerror = () => {
                message.error("파일 읽기에 실패했습니다.");
                setLoading(false);
              }
              reader.readAsText(file);
            }, 0);
            return false;
          }}
          style={{ marginBottom: '2rem' }}
        >
          <p className="ant-upload-drag-icon"><InboxOutlined /></p>
          <p className="ant-upload-text">옵션 파일(.txt)을 업로드하여 자세와 옵션을 불러오세요</p>
        </Upload.Dragger>

        <Title level={5}>DOE 파라미터</Title>
        <Space wrap style={{ marginBottom: '1rem' }}>
          <Button icon={<PlusOutlined />} onClick={handleAddRow}>직접 추가</Button>
          <Button onClick={() => handleAddPredefinedRows([
            [0, 0, 0],        // 전면
            [180, 0, 0],      // 배면
            [90, 0, 0],       // 좌측면 (왼쪽이 바닥으로)
            [-90, 0, 0],      // 우측면 (오른쪽이 바닥으로)
            [0, -90, 0],      // 상단 (윗면이 바닥으로)
            [0, 90, 0],       // 하단 (아랫면이 바닥으로)
          ])}>
            📦 1.5m 6면 낙하
          </Button>

          <Button onClick={() => handleAddPredefinedRows([
            [-45, 0, 0], [45, 0, 0], [0, -45, 0], [0, 45, 0],
            [0, 0, -45], [0, 0, 45], [45, 45, 0], [-45, -45, 0],
            [0, 45, 45], [0, -45, -45], [45, 0, 45], [-45, 0, -45]
          ])}>📦 1.5m 12엣지 낙하</Button>
          <Button onClick={() => handleAddPredefinedRows([
            [-35.264, 45, 0], [35.264, 45, 0],
            [-35.264, -45, 0], [35.264, -45, 0],
            [-35.264, 45, 180], [35.264, 45, 180],
            [-35.264, -45, 180], [35.264, -45, 180]
          ])}>📦 1.5m 8코너 낙하</Button>
          
          <InputNumber
            min={1}
            max={100}
            value={randomCount}
            onChange={(v) => setRandomCount(v || 1)}
            style={{ width: '80px' }}
            />
            <Button onClick={() => {
            const rows = Array.from({ length: randomCount }, () => ({
                ...initialRow,
                Height: 1500,
                EulerRolling: Math.random() * 360 - 180,
                EulerPitching: Math.random() * 360 - 180,
                EulerYawing: Math.random() * 360 - 180,
            }));
            setTableData([...tableData, ...rows]);
            }}>
            📦 1.5m 랜덤 낙하
            </Button>
            <Button onClick={() => {
            const rows = Array.from({ length: randomCount }, () => ({
                ...initialRow,
                Height: Math.floor(Math.random() * 1800) + 300,
                EulerRolling: Math.random() * 360 - 180,
                EulerPitching: Math.random() * 360 - 180,
                EulerYawing: Math.random() * 360 - 180,
            }));
            setTableData([...tableData, ...rows]);
            }}>
            📦 랜덤 높이 낙하
            </Button>
            
            <Button danger onClick={handleClearAllRows}>전체 삭제</Button>

        </Space>


        <Table
          columns={columns}
          dataSource={tableData}
          rowKey={(record, index) => index?.toString() ?? ''}
          pagination={false}
          scroll={{ x: true }}
        />

        <Title level={5} style={{ marginTop: '2rem' }}>시뮬레이션 전역 옵션</Title>
        <Form layout="vertical">
          <Space wrap>
            {Object.entries(defaultOptions).map(([key, defaultValue]) => (
              <Form.Item label={optionLabels[key] || key} key={key}>
                <InputNumber
                  value={options[key as keyof typeof options]}
                  onChange={(value) => handleOptionChange(key, value || 0)}
                />
              </Form.Item>
            ))}
          </Space>
        </Form>

        <Title level={5} style={{ marginTop: '2rem' }}> Roll–Pitch–Yaw 분포 (3D)</Title>
        <div style={fullPlotBoxStyle}>
          <Plot
            data={plotData as any}
            layout={plotLayout as any}
            useResizeHandler
            style={fullPlotStyle}
            config={{ responsive: true }}
          />
        </div>


        <Title level={5} style={{ marginTop: '2rem' }}> 자세별 스마트폰 박스 시각화 (3D)</Title>
        <div style={fullPlotBoxStyle}>
          <Plot
            data={boxData as any}
            layout={boxLayout as any}
            useResizeHandler
            style={fullPlotStyle}
            config={{ responsive: true }}
          />
        </div>
        <div style={{ marginTop: '2rem', textAlign: 'center' }}>
          <ExportMeshModifierButton
            kFile={kFile}
            kFileName={kFile?.name || 'UNKNOWN.k'}
            optionFileGenerator={() => generateDropAttitudeOptionFile(kFile?.name || 'UNKNOWN.k', tableData, options)}
            optionFileName="drop_attitude.txt"
            solver="MeshModifier"
            mode="DropAttitude"
            buttonLabel="🔁 해석 실행 (Mesh Modifier)"
          />
        </div>
      </div>
      </Spin>
    </BaseLayout>
  );
};

export default DropAttitudeGenerator;
