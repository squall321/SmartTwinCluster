// 📁 src/pages/StreamRunnerPage.tsx
import React from 'react';
import { useLocation } from 'react-router-dom';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import StreamRunner from '../components/StreamRunner';

const { Title, Paragraph } = Typography;

const StreamRunnerPage: React.FC = () => {
  const location = useLocation();
  const state = location.state as {
    solver?: string;
    mode?: string;
    txtFiles?: File[];
    optFiles?: File[];
    autoSubmit?: boolean;
  } || {};

  const solver = state.solver ?? "MeshModifier";
  const mode = state.mode ?? null;
  const txtFiles = state.txtFiles ?? [];
  const optFiles = state.optFiles ?? [];
  const autoSubmit = state.autoSubmit ?? false;

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{
        padding: 24,
        backgroundColor: '#fff',
        minHeight: '100vh',
        borderRadius: '24px',
      }}>
        {solver === "MeshModifier" && <Title level={3}>📦 Mesh Modifier</Title>}
        {solver === "AutomatedModeller" && <Title level={3}>📦 Automated Modeller</Title>}
        <Paragraph>
          시뮬레이션 모델에 대한 격자 수정을 위한 자동화 코드를 수행합니다.
        </Paragraph>

        <StreamRunner
          solver={solver}
          mode={mode}
          txtFiles={txtFiles}
          optFiles={optFiles}
          autoSubmit={autoSubmit}
        />
      </div>
    </BaseLayout>
  );
};

export default StreamRunnerPage;
