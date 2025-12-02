import React from 'react';
import { Table, Select, Space, Tooltip } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { DeleteOutlined } from '@ant-design/icons';

const { Option } = Select;

export interface LsdynaJobConfig {
  key: string;
  filename: string;
  file: File;
  cores: number;
  precision: 'single' | 'double';
  version: 'R15' | 'R14';
  mode: 'SMP' | 'MPP';
}

interface Props {
  data: LsdynaJobConfig[];
  onUpdateAll: <K extends keyof LsdynaJobConfig>(field: K, value: LsdynaJobConfig[K]) => void;
  onUpdateRow: <K extends keyof LsdynaJobConfig>(
    key: string,
    field: K,
    value: LsdynaJobConfig[K]
  ) => void;
  onDeleteRow: (key: string) => void;
}

const coreOptions = [16, 32, 64, 128];
const precisionOptions = ['single', 'double'] as const;
const versionOptions = ['R15', 'R14'] as const;
const modeOptions = ['SMP', 'MPP'] as const;

const LsdynaOptionTable: React.FC<Props> = ({ data, onUpdateAll, onUpdateRow, onDeleteRow }) => {
  const columns: ColumnsType<LsdynaJobConfig> = [
    {
      title: '파일명',
      dataIndex: 'filename',
      key: 'filename',
      width: 200,
      ellipsis: true,
      render: (text: string): React.ReactNode => (
        <Tooltip title={text}>
          <div
            style={{
              display: 'inline-block',
              maxWidth: 180,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
            }}
          >
            {text}
          </div>
        </Tooltip>
      ),
    },
    {
      title: 'Core 수',
      dataIndex: 'cores',
      key: 'cores',
      width: 120,
      render: (value, row) => (
        <Select
          value={value}
          size="small"
          style={{ width: 100 }}
          onChange={(val) => onUpdateRow(row.key, 'cores', val)}
        >
          {coreOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>
      ),
    },
    {
      title: 'Precision',
      dataIndex: 'precision',
      key: 'precision',
      width: 120,
      render: (value, row) => (
        <Select
          value={value}
          size="small"
          style={{ width: 100 }}
          onChange={(val) => onUpdateRow(row.key, 'precision', val)}
        >
          {precisionOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>
      ),
    },
    {
      title: 'Version',
      dataIndex: 'version',
      key: 'version',
      width: 120,
      render: (value, row) => (
        <Select
          value={value}
          size="small"
          style={{ width: 100 }}
          onChange={(val) => onUpdateRow(row.key, 'version', val)}
        >
          {versionOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>
      ),
    },
    {
      title: 'Mode',
      dataIndex: 'mode',
      key: 'mode',
      width: 120,
      render: (value, row) => (
        <Select
          value={value}
          size="small"
          style={{ width: 100 }}
          onChange={(val) => onUpdateRow(row.key, 'mode', val)}
        >
          {modeOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>
      ),
    },
    {
      title: '삭제',
      key: 'delete',
      width: 60,
      render: (_, row) => (
        <DeleteOutlined
          onClick={() => onDeleteRow(row.key)}
          style={{ color: 'red', cursor: 'pointer' }}
        />
      ),
    },
  ];

  return (
    <>
      <Table
        bordered
        columns={columns}
        dataSource={data}
        pagination={false}
        scroll={{ x: 'max-content' }}
        size="small"
        rowKey="key"
      />

      {/* 전체 변경 UI */}
      <Space
        style={{
          marginTop: '1rem',
          padding: '8px',
          borderTop: '1px dashed #ddd',
          display: 'flex',
          flexWrap: 'wrap',
          alignItems: 'center',
          gap: '0.5rem',
        }}
      >
        <span style={{ fontWeight: 500 }}>전체 변경:</span>

        <Select size="small" style={{ width: 100 }} onChange={(val) => onUpdateAll('cores', val)} defaultValue={16}>
          {coreOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>

        <Select
          size="small"
          style={{ width: 100 }}
          onChange={(val: 'single' | 'double') => onUpdateAll('precision', val)}
          defaultValue="single"
        >
          {precisionOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>

        <Select
          size="small"
          style={{ width: 100 }}
          onChange={(val: 'R15' | 'R14') => onUpdateAll('version', val)}
          defaultValue="R15"
        >
          {versionOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>

        <Select
          size="small"
          style={{ width: 100 }}
          onChange={(val: 'SMP' | 'MPP') => onUpdateAll('mode', val)}
          defaultValue="SMP"
        >
          {modeOptions.map((opt) => (
            <Option key={opt} value={opt}>{opt}</Option>
          ))}
        </Select>
      </Space>
    </>
  );
};

export default LsdynaOptionTable;
