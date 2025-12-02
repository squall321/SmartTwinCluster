// src/pages/SubmitLsdynaPage.tsx
import React, { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import SubmitLsdynaPanel from '../components/submit/SubmitLsdynaPanel';
import type { LsdynaJobConfig } from '@components/uploader/LsdynaOptionTable';

const { Title } = Typography;

const SubmitLsdynaPage: React.FC = () => {
  const [configs, setConfigs] = useState<LsdynaJobConfig[]>([]);

  useEffect(() => {
    if (configs) {
      setConfigs(configs);
    }
  }, [configs]);
  return (
    <BaseLayout isLoggedIn>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={2}>LS-DYNA 작업 제출</Title>
        <SubmitLsdynaPanel initialConfigs={configs} />
      </div>
    </BaseLayout>
  );
};

export default SubmitLsdynaPage;
