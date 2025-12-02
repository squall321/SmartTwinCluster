// components/simulationnetwork/AutoRefreshToggle.tsx
import React from 'react';
import { Switch } from 'antd';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';

const AutoRefreshToggle: React.FC = () => {
  const autoRefresh = useSimulationNetworkStore((state) => state.autoRefresh);
  const toggleAutoRefresh = useSimulationNetworkStore((state) => state.toggleAutoRefresh);

  return (
    <div>
      <Switch checked={autoRefresh} onChange={toggleAutoRefresh} />
      <span style={{ marginLeft: 8 }}>
        Auto Refresh {autoRefresh ? '(1분마다)' : ''}
      </span>
    </div>
  );
};

export default AutoRefreshToggle;
