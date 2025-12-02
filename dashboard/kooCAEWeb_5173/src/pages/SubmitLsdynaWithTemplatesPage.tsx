/**
 * SubmitLsdynaWithTemplatesPage
 *
 * Enhanced LS-DYNA job submission page with Apptainer command template integration.
 * This page demonstrates the complete Phase 3 production integration.
 */

import React, { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import SubmitLsdynaPanelWithTemplates from '../components/submit/SubmitLsdynaPanelWithTemplates';
import type { LsdynaJobConfig } from '@components/uploader/LsdynaOptionTable';

const { Title, Paragraph } = Typography;

const SubmitLsdynaWithTemplatesPage: React.FC = () => {
  const [configs, setConfigs] = useState<LsdynaJobConfig[]>([]);

  useEffect(() => {
    if (configs) {
      setConfigs(configs);
    }
  }, [configs]);

  return (
    <BaseLayout isLoggedIn>
      <div
        style={{
          padding: 24,
          backgroundColor: '#fff',
          minHeight: '100vh',
          borderRadius: '24px',
        }}
      >
        <Title level={2}>LS-DYNA 작업 제출 (템플릿 통합)</Title>

        <Paragraph style={{ fontSize: '14px', color: '#666', marginBottom: 24 }}>
          Apptainer 명령어 템플릿을 사용하여 LS-DYNA 작업을 제출할 수 있습니다.
          템플릿을 선택하면 자동으로 Slurm 스크립트가 생성되며, 필요한 매개변수가 자동으로 설정됩니다.
        </Paragraph>

        <SubmitLsdynaPanelWithTemplates initialConfigs={configs} />
      </div>
    </BaseLayout>
  );
};

export default SubmitLsdynaWithTemplatesPage;
