import React from 'react';
import { Select, Input, Button, Space } from 'antd';

interface Props {
  selectedDate?: string;
  selectedMode?: string;
  prefix?: string;
  onDateChange: (date?: string) => void;
  onModeChange: (mode?: string) => void;
  onPrefixChange: (prefix?: string) => void;
  onLoad: () => void;
  allDates: string[];
  allModes: string[];
}

const FileFilterPanel: React.FC<Props> = ({
  selectedDate,
  selectedMode,
  prefix,
  onDateChange,
  onModeChange,
  onPrefixChange,
  onLoad,
  allDates,
  allModes,
}) => {
  return (
    <Space direction="horizontal" style={{ marginBottom: 16, flexWrap: 'wrap' }}>
      <Select
        placeholder="날짜"
        value={selectedDate}
        onChange={onDateChange}
        options={allDates.map(date => ({ value: date, label: date }))}
        allowClear
        style={{ minWidth: 150 }}
      />
      <Select
        placeholder="모드"
        value={selectedMode}
        onChange={onModeChange}
        options={allModes.map(mode => ({ value: mode, label: mode }))}
        allowClear
        style={{ minWidth: 140 }}
      />
      <Input
        placeholder="Prefix (예: taylor_A)"
        value={prefix}
        onChange={e => onPrefixChange(e.target.value)}
        style={{ minWidth: 200 }}
      />
      <Button type="primary" onClick={onLoad}>
        📂 Load
      </Button>
    </Space>
  );
};

export default FileFilterPanel;
