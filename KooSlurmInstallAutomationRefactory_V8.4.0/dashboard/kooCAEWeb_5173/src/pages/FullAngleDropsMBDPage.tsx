import React, { useMemo, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Upload, message, Table, Select, InputNumber, Button, Space, Radio } from 'antd';
import { InboxOutlined, DownloadOutlined } from '@ant-design/icons';
import ColoredScatter3DComponent from '../components/ColoredScatter3DComponent';
import Papa from 'papaparse';
import ObjViewerComponent from '../components/ObjViewerComponent';

const { Title, Paragraph } = Typography;
const { Dragger } = Upload;
const { Option } = Select;

type ParamMode = 'fixed' | 'range' | 'normal';
type ParamName =
  | 'Height' | 'EulerX' | 'EulerY' | 'EulerZ'
  | 'Restitution' | 'Stiffness' | 'Damping'
  | 'VelX' | 'VelY' | 'VelZ'
  | 'PosX' | 'PosY';

interface ParamConfig {
  name: ParamName;
  mode: ParamMode;
  fixed?: number;
  min?: number;
  max?: number;
  mean?: number;
  std?: number;
}

interface TableRow extends ParamConfig {
  key: ParamName;
}

const DEFAULT_HEADERS: ParamName[] = [
  'Height', 'EulerX', 'EulerY', 'EulerZ',
  'Restitution', 'Stiffness', 'Damping',
  'VelX', 'VelY', 'VelZ',
  'PosX', 'PosY'
];

// 샘플 개수
const DEFAULT_NUM_SAMPLES = 32;

// 간단 LHS (0~1 사이)
function lhsSample(dim: number, n: number): number[][] {
  const result: number[][] = Array.from({ length: n }, () => Array(dim).fill(0));
  for (let d = 0; d < dim; d++) {
    const cut = Array.from({ length: n }, (_, i) => (i + Math.random()) / n); // stratified
    // shuffle
    for (let i = cut.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [cut[i], cut[j]] = [cut[j], cut[i]];
    }
    for (let i = 0; i < n; i++) {
      result[i][d] = cut[i];
    }
  }
  return result;
}

// Box-Muller 표준정규
function randn(): number {
  let u = 0, v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}

// 0.4 간격 그리드 배치
function placeOnGrid(n: number, step = 0.4) {
  const cols = Math.ceil(Math.sqrt(n));
  const coords: Array<[number, number]> = [];
  for (let i = 0; i < n; i++) {
    const x = (i % cols) * step;
    const y = Math.floor(i / cols) * step;
    coords.push([x, y]);
  }
  return coords;
}

const makeDefaultParamRows = (): TableRow[] => ([
  { key: 'Height',       name: 'Height',       mode: 'fixed', fixed: 1.5 },
  { key: 'EulerX',       name: 'EulerX',       mode: 'range', min: -180, max: 180 },
  { key: 'EulerY',       name: 'EulerY',       mode: 'range', min:  -90, max:  90 },
  { key: 'EulerZ',       name: 'EulerZ',       mode: 'range', min: -180, max: 180 },
  { key: 'Restitution',  name: 'Restitution',  mode: 'fixed', fixed: 1e-5 },
  { key: 'Stiffness',    name: 'Stiffness',    mode: 'fixed', fixed: 1e9 },
  { key: 'Damping',      name: 'Damping',      mode: 'fixed', fixed: 10 },
  { key: 'VelX',         name: 'VelX',         mode: 'fixed', fixed: 0 },
  { key: 'VelY',         name: 'VelY',         mode: 'fixed', fixed: 0 },
  { key: 'VelZ',         name: 'VelZ',         mode: 'fixed', fixed: 0 },
  { key: 'PosX',         name: 'PosX',         mode: 'fixed', fixed: 0 }, // 실제 생성 시 grid로 덮어씀
  { key: 'PosY',         name: 'PosY',         mode: 'fixed', fixed: 0 }, // 실제 생성 시 grid로 덮어씀
]);

const FullAngleDropsMBDPage: React.FC = () => {
  const [data, setData] = useState<(string | number)[][] | null>(null);
  const [rows, setRows] = useState<TableRow[]>(makeDefaultParamRows);
  const [numSamples, setNumSamples] = useState<number>(DEFAULT_NUM_SAMPLES);
  const [globalSampler, setGlobalSampler] = useState<'lhs' | 'random'>('lhs');
  const [objUrl, setObjUrl] = useState<string | null>(null);

 
  

  // CSV 업로드 파서
  const handleCSV = (file: File) => {
    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const raw = results.data as Record<string, string>[];
        const meta = results.meta.fields || [];

        if (raw.length === 0 || meta.length === 0) {
          message.error('CSV에 유효한 데이터가 없습니다.');
          return;
        }

        try {
          const headers = meta as string[];
          const parsed: (string | number)[][] = [headers];

          raw.forEach((row) => {
            const rowArray: (string | number)[] = headers.map((key) => {
              const val = row[key];
              const num = Number(val);
              return isNaN(num) ? val : num;
            });
            parsed.push(rowArray);
          });

          setData(parsed);
          message.success('CSV 로드 성공!');
        } catch (e) {
          console.error(e);
          message.error('CSV 파싱 중 오류가 발생했습니다.');
        }
      },
    });

    return false;
  };

  // 파라미터 테이블 변경 핸들러
  const changeRow = (name: ParamName, patch: Partial<TableRow>) => {
    setRows(prev => prev.map(r => r.name === name ? { ...r, ...patch } : r));
  };

  const columns = [
    {
      title: 'Name',
      dataIndex: 'name',
      width: 130,
      render: (v: ParamName) => <b>{v}</b>,
    },
    {
      title: 'Mode',
      dataIndex: 'mode',
      width: 120,
      render: (_: any, record: TableRow) => (
        <Select
          value={record.mode}
          style={{ width: '100%' }}
          onChange={(val: ParamMode) => changeRow(record.name, { mode: val })}
        >
          <Option value="fixed">fixed</Option>
          <Option value="range">range (LHS/Random)</Option>
          <Option value="normal">normal(μ, σ)</Option>
        </Select>
      ),
    },
    {
      title: 'Fixed',
      dataIndex: 'fixed',
      width: 120,
      render: (_: any, record: TableRow) => (
        <InputNumber
          value={record.fixed}
          onChange={(val) => changeRow(record.name, { fixed: val ?? undefined })}
          disabled={record.mode !== 'fixed'}
          style={{ width: '100%' }}
        />
      ),
    },
    {
      title: 'Min',
      dataIndex: 'min',
      width: 120,
      render: (_: any, record: TableRow) => (
        <InputNumber
          value={record.min}
          onChange={(val) => changeRow(record.name, { min: val ?? undefined })}
          disabled={record.mode !== 'range'}
          style={{ width: '100%' }}
        />
      ),
    },
    {
      title: 'Max',
      dataIndex: 'max',
      width: 120,
      render: (_: any, record: TableRow) => (
        <InputNumber
          value={record.max}
          onChange={(val) => changeRow(record.name, { max: val ?? undefined })}
          disabled={record.mode !== 'range'}
          style={{ width: '100%' }}
        />
      ),
    },
    {
      title: 'Mean',
      dataIndex: 'mean',
      width: 120,
      render: (_: any, record: TableRow) => (
        <InputNumber
          value={record.mean}
          onChange={(val) => changeRow(record.name, { mean: val ?? undefined })}
          disabled={record.mode !== 'normal'}
          style={{ width: '100%' }}
        />
      ),
    },
    {
      title: 'Std',
      dataIndex: 'std',
      width: 120,
      render: (_: any, record: TableRow) => (
        <InputNumber
          value={record.std}
          onChange={(val) => changeRow(record.name, { std: val ?? undefined })}
          disabled={record.mode !== 'normal'}
          style={{ width: '100%' }}
        />
      ),
    },
  ];

  const generate = () => {
    // 1) LHS용으로 'range' 모드인 파라미터들만 차원에 포함
    const rangeParams = rows.filter(r => r.mode === 'range');
    const dim = rangeParams.length;

    let lhs: number[][] = [];
    if (globalSampler === 'lhs' && dim > 0) {
      lhs = lhsSample(dim, numSamples); // 0~1
    }

    // Pos grid
    const grid = placeOnGrid(numSamples, 0.4);

    // 2) 한 샘플당 값 생성
    const records: Record<ParamName, number>[] = [];
    for (let i = 0; i < numSamples; i++) {
      const rec = {} as Record<ParamName, number>;

      // 먼저 기본/고정값/정규/범위값 채움
      let rangeIdx = 0;
      for (const r of rows) {
        if (r.name === 'PosX' || r.name === 'PosY') continue; // 나중에 grid로 덮어씀

        if (r.mode === 'fixed') {
          rec[r.name] = r.fixed ?? 0;
        } else if (r.mode === 'range') {
          const lo = r.min ?? 0;
          const hi = r.max ?? 1;
          const u = (globalSampler === 'lhs' && dim > 0)
            ? lhs[i][rangeIdx++] // stratified
            : Math.random();     // random
          rec[r.name] = lo + (hi - lo) * u;
        } else { // normal
          const mean = r.mean ?? 0;
          const std = r.std ?? 1;
          rec[r.name] = mean + std * randn();
        }
      }

      // PosX/PosY는 0.4 간격 그리드
      const [px, py] = grid[i];
      rec.PosX = px;
      rec.PosY = py;

      records.push(rec);
    }

    // 3) CSV/ColoredScatter3DComponent용 2D 배열 구성
    const headers = DEFAULT_HEADERS;
    const parsed: (string | number)[][] = [headers];

    for (const r of records) {
      parsed.push(headers.map(h => r[h as ParamName]));
    }

    setData(parsed);
    message.success(`샘플 ${numSamples}개 생성 완료!`);
  };

  

  const downloadCSV = () => {
    if (!data) return;
    const csv = Papa.unparse({
      fields: data[0] as string[],
      data: data.slice(1),
    });
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `FullAngleDrops_${new Date().toISOString().replace(/[:.]/g, '-')}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>전각도 다물체 동역학 낙하 시뮬레이션</Title>
        <Paragraph>
          • CSV를 드래그-드롭하여 바로 시각화하거나<br/>
          • 아래 파라미터 테이블에서 <b>고정값 / 범위(LHS/Random) / 정규분포(μ,σ)</b>를 지정해 샘플을 생성할 수 있습니다.<br/>
          • <b>PosX, PosY</b>는 항상 <code>0.4</code> 간격으로 겹치지 않도록 자동 배치됩니다.
        </Paragraph>

        {/* CSV 업로더 */}
        <Dragger
          name="file"
          multiple={false}
          accept=".csv"
          beforeUpload={handleCSV}
          showUploadList={false}
          style={{ marginBottom: 30 }}
        >
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">CSV 파일을 이곳에 드래그하거나 클릭하여 업로드하세요</p>
        </Dragger>

        {/* 파라미터 설정 & 샘플링 */}
        <Space direction="vertical" style={{ width: '100%', marginTop: 24 }}>
          <Title level={4}>파라미터 기반 샘플 생성</Title>

          <Space align="center" wrap>
          <span>샘플 개수:</span>
          <InputNumber
            min={1}
            value={numSamples}
            onChange={(v) => setNumSamples(v ?? 1)}
          />
          <span>range 모드 전역 샘플러:</span>
          <Radio.Group
            value={globalSampler}
            onChange={(e) => setGlobalSampler(e.target.value)}
            optionType="button"
            options={[
              { label: 'LHS', value: 'lhs' },
              { label: 'Random', value: 'random' },
            ]}
          />
          <Button type="primary" onClick={generate}>
            샘플 생성
          </Button>
          <Button
            icon={<DownloadOutlined />}
            onClick={downloadCSV}
            disabled={!data}
          >
            CSV 다운로드
          </Button>
          </Space>

          <Table<TableRow>
            bordered
            size="small"
            dataSource={rows}
            columns={columns}
            pagination={false}
            style={{ marginTop: 12 }}
          />
        </Space>

        {/* 3D 시각화 */}
        <div style={{ marginTop: 32 }}>
          {data && (
            <ColoredScatter3DComponent
              title="Colored Scatter 3D"
              data={data}
             
            />
          )}
        </div>
        {/* OBJ 업로더 */}
        <Title level={4} style={{ marginTop: 48 }}>📦 OBJ 파일 업로드</Title>
        <Paragraph>
          시뮬레이션 결과와 함께 사용할 3D 모델(.obj)을 업로드하세요.
        </Paragraph>

        <Dragger
          name="objFile"
          multiple={false}
          accept=".obj"
          beforeUpload={(file) => {
            const isObj = file.name.endsWith('.obj');
            if (!isObj) {
              message.error('OBJ 파일만 업로드할 수 있습니다.');
              return Upload.LIST_IGNORE;
            }
            setObjUrl(URL.createObjectURL(file));
            const reader = new FileReader();
            reader.onload = (e) => {
              const content = e.target?.result as string;
              // TODO: content 처리
              console.log('[OBJ 업로드됨]', file.name, content.slice(0, 100));
              message.success(`OBJ 파일 "${file.name}" 로드 완료`);
            };
            reader.readAsText(file);

            return false; // 자동 업로드 방지
          }}
          showUploadList={false}
        >
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">OBJ 파일을 이곳에 드래그하거나 클릭하여 업로드하세요</p>
        </Dragger>
        {objUrl && (
          <ObjViewerComponent url={objUrl} />
        )}

      </div>
    </BaseLayout>
  );
};

export default FullAngleDropsMBDPage;
