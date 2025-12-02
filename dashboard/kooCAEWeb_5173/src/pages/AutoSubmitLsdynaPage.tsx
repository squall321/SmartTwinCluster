// src/pages/AutoSubmitLsdynaPage.tsx
import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, message } from 'antd';
import SubmitLsdynaPanel from '../components/submit/SubmitLsdynaPanel';
import type { LsdynaJobConfig } from '../components/uploader/LsdynaOptionTable';

const { Title } = Typography;

const AutoSubmitLsdynaPage: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();

  const jobConfigs: LsdynaJobConfig[] = location.state?.jobConfigs || [];

  if (jobConfigs.length === 0) {
    message.warning("전달된 작업 정보가 없습니다. 다시 업로드해 주세요.");
    navigate("/full-angle-drop");
    return null;
  }

  return (
    <BaseLayout isLoggedIn>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={2}>제출 옵션 검토 및 전송</Title>
        <SubmitLsdynaPanel initialConfigs={jobConfigs} />
      </div>
    </BaseLayout>
  );
};

export default AutoSubmitLsdynaPage;
