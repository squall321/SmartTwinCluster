import React from 'react';
import { Table, Card } from 'antd';
import { ModeResult } from '../../types/mck/simulationTypes';

interface Props {
  modalResults: ModeResult | null;
}

const ModalResultsPanel: React.FC<Props> = ({ modalResults }) => {
  const columns = [
    { title: 'Mode', dataIndex: 'mode', width: 80 },
    { title: 'Frequency (Hz)', dataIndex: 'frequency', width: 150 },
    { title: 'Damping Ratio (%)', dataIndex: 'damping', width: 150 }
  ];

  const data =
    modalResults?.frequencies.map((f, i) => ({
      key: i,
      mode: i + 1,
      frequency: f.toFixed(3),
      damping: (modalResults.dampingRatios[i] * 100).toFixed(3),
    })) || [];

  return (
    <Card title="Modal Analysis Results" size="small" style={{ marginTop: 16 }}>
      <Table
        columns={columns}
        dataSource={data}
        pagination={false}
        locale={{ emptyText: "No modal results." }}
        size="small"
      />
    </Card>
  );
};

export default ModalResultsPanel;
