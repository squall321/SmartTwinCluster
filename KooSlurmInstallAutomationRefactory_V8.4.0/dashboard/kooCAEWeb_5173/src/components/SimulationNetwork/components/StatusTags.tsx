// components/simulationnetwork/StatusTags.tsx
import React from 'react';
import { Tag } from 'antd';
import { CaseStatus } from '../types/simulationnetwork';
import { getStatusColor } from '../utils/statusUtils';

interface Props { statuses: CaseStatus[]; }

const StatusTags: React.FC<Props> = ({ statuses }) => (
  <>
    {statuses.map(s => <Tag key={s} color={getStatusColor(s)}>{s}</Tag>)}
  </>
);

export default StatusTags;
