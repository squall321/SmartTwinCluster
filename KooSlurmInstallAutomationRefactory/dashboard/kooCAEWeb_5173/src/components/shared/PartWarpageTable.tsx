import { Table, Button, Typography, Upload, InputNumber, Space, Tag } from 'antd';
import { UploadOutlined, EyeOutlined, DeleteOutlined } from '@ant-design/icons';
import { ParsedPart } from '../../types/parsedPart';

interface WarpageInfo {
  rawData: number[][]; // .dat로부터 파싱된 행렬
  xLength: number;
  yLength: number;
  scaleFactor: number;
}

interface PartWarpageTableProps {
  parts: ParsedPart[];
  editable?: boolean;
  onRemove?: (id: string) => void;
  title?: string;
  onUploadDat?: (partId: string, file: File) => void;
  onViewPart?: (partId: string) => void;
  datStatusMap?: Record<string, boolean>;
  warpageMap: Record<string, WarpageInfo>;
  onParamChange: (partId: string, newParams: Partial<Pick<WarpageInfo, 'xLength' | 'yLength' | 'scaleFactor'>>) => void;
}

const PartWarpageTable: React.FC<PartWarpageTableProps> = ({
  parts,
  editable = false,
  onRemove,
  title,
  onUploadDat,
  onViewPart,
  datStatusMap = {},
  warpageMap,
  onParamChange,
}) => {
  const columns = [
    { title: 'ID', dataIndex: 'id', key: 'id' },
    { title: '이름', dataIndex: 'name', key: 'name' },
    {
      title: 'DAT 상태',
      key: 'dat',
      render: (_: any, record: ParsedPart) =>
        datStatusMap[record.id] ? <Tag color="green">업로드됨</Tag> : <Tag color="red">없음</Tag>
    },
    {
      title: 'X', key: 'xLength',
      render: (_: any, record: ParsedPart) => (
        <InputNumber
          min={0}
          step={0.1}
          value={warpageMap[record.id]?.xLength ?? 1}
          onChange={(val) => onParamChange(record.id, { xLength: val ?? 0 })}
        />
      )
    },
    {
      title: 'Y', key: 'yLength',
      render: (_: any, record: ParsedPart) => (
        <InputNumber
          min={0}
          step={0.1}
          value={warpageMap[record.id]?.yLength ?? 1}
          onChange={(val) => onParamChange(record.id, { yLength: val ?? 0 })}
        />
      )
    },
    {
      title: 'Scale', key: 'scaleFactor',
      render: (_: any, record: ParsedPart) => (
        <InputNumber
          min={0}
          step={0.1}
          value={warpageMap[record.id]?.scaleFactor ?? 1}
          onChange={(val) => onParamChange(record.id, { scaleFactor: val ?? 1 })}
        />
      )
    },
    {
      title: '작업',
      key: 'actions',
      render: (_: any, record: ParsedPart) => (
        <Space>
          <Upload
            accept=".dat,.txt"
            beforeUpload={(file) => {
              onUploadDat?.(record.id, file);
              return false;
            }}
            showUploadList={false}
          >
            <Button size="small" icon={<UploadOutlined />}>업로드</Button>
          </Upload>
          <Button
            size="small"
            icon={<EyeOutlined />}
            onClick={() => onViewPart?.(record.id)}
            disabled={!datStatusMap[record.id]}
          >
            보기
          </Button>
          {editable && (
            <Button
              danger
              size="small"
              icon={<DeleteOutlined />}
              onClick={() => onRemove?.(record.id)}
            >
              제거
            </Button>
          )}
        </Space>
      )
    }
  ];

  return (
    <div style={{ marginTop: 24 }}>
      {title && <Typography.Text strong>{title}</Typography.Text>}
      <Table
        dataSource={parts.map((p, i) => ({ ...p, key: i }))}
        columns={columns}
        pagination={false}
        size="small"
        bordered
        style={{ marginTop: 12 }}
      />
    </div>
  );
};

export default PartWarpageTable;
