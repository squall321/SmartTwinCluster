// components/simulationnetwork/StatusLegend.tsx
import React from 'react';
import StatusTags from './StatusTags';
import { ALL_STATUSES } from '../utils/statusUtils';

const StatusLegend: React.FC = () => (
  <div>
    <strong>Status Legend:</strong> <StatusTags statuses={ALL_STATUSES} />
  </div>
);

export default StatusLegend;
