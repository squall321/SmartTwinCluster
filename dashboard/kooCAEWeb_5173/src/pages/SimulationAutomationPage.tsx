import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
//import SimulationNetwork from '../components/SimulationNetwork/SimulationNetwork';
import SimulationAutomationComponent from '../components/SimulationAutomation/SimulationAutomationComponent';

const { Title, Paragraph } = Typography;
interface SourceDescriptor {
    /** Human label shown as Mode node title (e.g., 001_FullAngleDrop) */
    mode: string;
    /** URL to outputPathList.txt for that mode */
    url?: string;
    /** Optional: raw text content if you already have it, for local parsing */
    text?: string;
  }

const SimulationAutomationPage: React.FC = () => {
    
    return (
        <BaseLayout isLoggedIn={true}>
            <div style={{ 
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }}>
                <Title level={3}>정규 차수 시뮬레이션 자동화</Title>
                <Paragraph>
                    개발 프로세스의 정규 차수 시뮬레이션을 자동화합니다.
                </Paragraph>
                <SimulationAutomationComponent />
            </div>
        </BaseLayout>
    );
};

export default SimulationAutomationPage;