import { Table, Button, Typography } from 'antd';
import { ParsedPart } from '../../types/parsedPart';

interface PartTableProps {
  parts: ParsedPart[];
  editable?: boolean;
  onRemove?: (id: string) => void;
  title?: string;
}

const PartTable: React.FC<PartTableProps> = ({ parts, editable = false, onRemove, title }) => {
  const columns = [
    { title: 'ID', dataIndex: 'id', key: 'id' },
    { title: '이름', dataIndex: 'name', key: 'name' },
    ...(editable
      ? [{
          title: '작업',
          key: 'action',
          render: (_: any, record: ParsedPart) => (
            <Button danger onClick={() => onRemove?.(record.id)}>제거</Button>
          ),
        }]
      : []),
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

export default PartTable;
