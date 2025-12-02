import React, { useMemo, useState } from 'react';
import { Typography, Form, Input, InputNumber, Button, Table, Space, message, Tooltip, Upload, Tag } from 'antd';
import { CopyOutlined, DownloadOutlined, ThunderboltOutlined, InboxOutlined, FileDoneOutlined } from '@ant-design/icons';
import Papa from 'papaparse';

const { Title, Paragraph, Text } = Typography;
const { Dragger } = Upload;

export type SubmitBulletPanelProps = {
  csvData?: (string | number)[][];
  csvPath?: string;
  objPath?: string;
  defaultTimestep?: number;
  defaultWriteTime?: number;
  defaultThreads?: number;
  solverEntry?: string;
};

type JobRow = {
  key: number;
  idx: number;
  start: number;
  end: number;
  batchsize: number;
  command: string;
};

const SubmitBulletPanel: React.FC<SubmitBulletPanelProps> = ({
  csvData: externalCsvData,
  csvPath: externalCsvPath,
  objPath: externalObjPath,
  defaultTimestep = 1.0e-6,
  defaultWriteTime = 1.0,
  defaultThreads = 4,
  solverEntry = 'python solver.py',
}) => {
  const [csvData, setCsvData] = useState<(string | number)[][] | undefined>(externalCsvData);
  const [csvPath, setCsvPath] = useState<string>(externalCsvPath ?? 'drop.csv');
  const [objPath, setObjPath] = useState<string>(externalObjPath ?? 'smartphone.obj');
  const [csvUploaded, setCsvUploaded] = useState<boolean>(false);
  const [objUploaded, setObjUploaded] = useState<boolean>(false);

  const numCases = useMemo(() => {
    if (!csvData || csvData.length <= 1) return 0;
    return csvData.length - 1;
  }, [csvData]);

  const [timestep, setTimestep] = useState<number>(defaultTimestep);
  const [writeTime, setWriteTime] = useState<number>(defaultWriteTime);
  const [threads, setThreads] = useState<number>(defaultThreads);
  const [entry, setEntry] = useState<string>(solverEntry);
  const [jobs, setJobs] = useState<JobRow[]>([]);

  const generateJobs = () => {
    if (numCases <= 0) {
      message.error('CSV 데이터(행 수)를 확인할 수 없습니다. csvData를 props로 전달했는지 확인하세요.');
      return;
    }
    if (threads <= 0) {
      message.error('threads 는 1 이상이어야 합니다.');
      return;
    }

    const chunk = Math.ceil(numCases / threads);
    const newJobs: JobRow[] = [];

    for (let k = 0; k < threads; k++) {
      const start = k * chunk;
      const end = Math.min((k + 1) * chunk, numCases);
      if (start >= end) break;

      const cmd = `${entry} ` +
        `--start ${start} ` +
        `--end ${end} ` +
        `--batchsize ${chunk} ` +
        `--timestep ${timestep} ` +
        `--csv ${csvPath} ` +
        `--objfile ${objPath} ` +
        `--writetime ${writeTime}`;

      newJobs.push({ key: k, idx: k, start, end, batchsize: chunk, command: cmd });
    }

    setJobs(newJobs);
    message.success(`${newJobs.length}개의 job 커맨드를 생성했습니다.`);
  };

  const copyAll = async () => {
    if (jobs.length === 0) return;
    const text = jobs.map(j => j.command).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      message.success('모든 커맨드를 클립보드에 복사했습니다.');
    } catch (e) {
      message.error('클립보드 복사에 실패했습니다.');
    }
  };

  const downloadSh = () => {
    if (jobs.length === 0) return;
    const body = [
      '#!/usr/bin/env bash',
      'set -e',
      `# total cases: ${numCases}, threads: ${threads}`,
      ...jobs.map(j => j.command + ' &'),
      'wait',
      'echo "all jobs done"',
    ].join('\n');

    const blob = new Blob([body], { type: 'text/x-shellscript;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'run_bullet_jobs.sh';
    a.click();
    URL.revokeObjectURL(url);
  };

  const columns = [
    { title: '#', dataIndex: 'idx', width: 60 },
    { title: 'start', dataIndex: 'start', width: 90 },
    { title: 'end', dataIndex: 'end', width: 90 },
    { title: 'batchsize', dataIndex: 'batchsize', width: 110 },
    {
      title: 'command',
      dataIndex: 'command',
      render: (val: string) => (
        <Space>
          <Text code style={{ userSelect: 'all' }}>{val}</Text>
          <Tooltip title="Copy">
            <Button
              size="small"
              icon={<CopyOutlined />}
              onClick={async () => {
                try { await navigator.clipboard.writeText(val); message.success('복사됨'); }
                catch { message.error('복사 실패'); }
              }}
            />
          </Tooltip>
        </Space>
      ),
    },
  ];

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
        const headers = meta as string[];
        const parsed: (string | number)[][] = [headers];
        raw.forEach((row) => {
          const rowArray = headers.map((key) => {
            const val = row[key];
            const num = Number(val);
            return isNaN(num) ? val : num;
          });
          parsed.push(rowArray);
        });
        setCsvData(parsed);
        setCsvPath(file.name);
        setCsvUploaded(true);
        message.success(`CSV "${file.name}" 업로드 성공!`);
      },
    });
    return false;
  };

  const handleOBJ = (file: File) => {
    if (!file.name.endsWith('.obj')) {
      message.error('OBJ 파일만 업로드 가능합니다.');
      return Upload.LIST_IGNORE;
    }
    setObjPath(file.name);
    setObjUploaded(true);
    message.success(`OBJ "${file.name}" 업로드 성공!`);
    return false;
  };

  return (
    <div style={{ padding: 24 }}>
      <Title level={3}>SubmitBulletPanel</Title>
      <Paragraph>
        <b>CSV</b> 및 <b>OBJ</b> 파일을 직접 업로드하거나, 외부 props로 전달받을 수 있습니다.
      </Paragraph>

      <Title level={4}>📂 파일 업로드</Title>
      <Paragraph>
        • CSV 파일은 실험 케이스를 포함한 파라미터 테이블입니다. (첫 행은 헤더)<br />
        • OBJ 파일은 시뮬레이션 대상 형상입니다.
      </Paragraph>

      <Space direction="vertical" style={{ width: '100%' }}>
        <Dragger
          name="csv"
          multiple={false}
          accept=".csv"
          beforeUpload={handleCSV}
          showUploadList={false}
        >
          <p className="ant-upload-drag-icon"><InboxOutlined /></p>
          <p className="ant-upload-text">CSV 파일 드래그 혹은 클릭</p>
          {csvUploaded && <Tag icon={<FileDoneOutlined />} color="green">{csvPath} 불러옴</Tag>}
        </Dragger>

        <Dragger
          name="obj"
          multiple={false}
          accept=".obj"
          beforeUpload={handleOBJ}
          showUploadList={false}
        >
          <p className="ant-upload-drag-icon"><InboxOutlined /></p>
          <p className="ant-upload-text">OBJ 파일 드래그 혹은 클릭</p>
          {objUploaded && <Tag icon={<FileDoneOutlined />} color="blue">{objPath} 불러옴</Tag>}
        </Dragger>
      </Space>

      <Form layout="vertical" onFinish={generateJobs} style={{ marginTop: 24 }}>
        <Form.Item label="solver entry (예: python solver.py)">
          <Input value={entry} onChange={(e) => setEntry(e.target.value)} />
        </Form.Item>
        <Form.Item label="timestep (s)">
          <InputNumber style={{ width: '100%' }} value={timestep} onChange={(v) => setTimestep(v ?? 0)} />
        </Form.Item>
        <Form.Item label="writeTime (s)">
          <InputNumber style={{ width: '100%' }} value={writeTime} onChange={(v) => setWriteTime(v ?? 0)} />
        </Form.Item>
        <Form.Item label="threads (동시에 돌릴 job 수)">
          <InputNumber min={1} style={{ width: '100%' }} value={threads} onChange={(v) => setThreads(v ?? 1)} />
        </Form.Item>
        <Space>
          <Button type="primary" htmlType="submit" icon={<ThunderboltOutlined />}>Generate Commands</Button>
          <Button icon={<CopyOutlined />} disabled={jobs.length === 0} onClick={copyAll}>Copy All</Button>
          <Button icon={<DownloadOutlined />} disabled={jobs.length === 0} onClick={downloadSh}>Download .sh</Button>
        </Space>
      </Form>

      <Table<JobRow>
        style={{ marginTop: 24 }}
        bordered
        size="small"
        dataSource={jobs}
        columns={columns}
        pagination={false}
        rowKey="key"
      />
    </div>
  );
};

export default SubmitBulletPanel;