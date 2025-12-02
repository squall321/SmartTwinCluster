// src/pages/SubmitLsdynaPage.tsx
import React, { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import SubmitBulletPanel from '../components/submit/SubmitBulletPanel';

const { Title } = Typography;

const SubmitBulletPage: React.FC = () => {
 
  return (
    <BaseLayout isLoggedIn>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={2}>Bullet 작업 제출</Title>
        <SubmitBulletPanel />
      </div>
    </BaseLayout>
  );
};

export default SubmitBulletPage;
