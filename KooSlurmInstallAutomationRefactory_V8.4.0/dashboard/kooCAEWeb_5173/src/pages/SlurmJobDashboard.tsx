import React, { useEffect, useState } from 'react';
import { Card, Col, Row, Typography } from 'antd';
import { useNavigate } from 'react-router-dom';
import BaseLayout from '../layouts/BaseLayout';
import styles from './Dashboard.module.css';

const { Title, Paragraph } = Typography;

const SlurmJobDashboard: React.FC = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    const loggedIn = localStorage.getItem('isLoggedIn') === 'true';
    setIsLoggedIn(loggedIn);
  }, []);

  const softwareOptions = [
    {
      icon: '⚙️',
      title: 'LSDyna Job 제출',
      description: 'LSDYNA 해석을 위한 Slurm job 제출을 시작합니다.',
      onClick: () => navigate('/submit-lsdyna'),
    },
    {
      icon: '🚀',
      title: 'OpenRadioss Job 제출',
      description: 'OpenRadioss 해석을 위한 job을 구성하고 제출합니다.',
      onClick: () => navigate('/submit-openradioss'),
    },
    {
      icon: '🛠️',
      title: 'Chrono Job 제출',
      description: 'Project Chrono 시뮬레이션을 위한 job 제출 페이지입니다.',
      onClick: () => navigate('/submit-chrono'),
    },
    {
      icon: '💥',
      title: 'Bullet Job 제출',
      description: 'Bullet 물리엔진 기반 job 제출을 구성합니다.',
      onClick: () => navigate('/submit-bullet'),
    },
  ];

  return (
    <BaseLayout isLoggedIn={isLoggedIn}>
      {isLoggedIn ? (
        <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
          <Title level={2} style={{ marginBottom: '2rem', fontWeight: 'bold' }}>
            📝 Slurm Job 제출 대시보드
          </Title>
          <Row gutter={[24, 24]}>
            {softwareOptions.map((option, index) => (
              <Col xs={24} sm={12} md={8} lg={6} key={index}>
                <Card
                  className={styles.cardHoverEffect}
                  hoverable
                  onClick={option.onClick}
                  style={{
                    cursor: 'pointer',
                    height: '180px',
                    borderRadius: '12px',
                    boxShadow: '0 4px 12px rgba(0, 0, 0, 0.08)',
                    transition: 'transform 0.2s ease',
                  }}
                  bodyStyle={{ display: 'flex', flexDirection: 'column', justifyContent: 'center' }}
                >
                  <div style={{ fontSize: '24px', marginBottom: '0.5rem' }}>{option.icon}</div>
                  <Title level={4} style={{ margin: 0, fontWeight: 600 }}>
                    {option.title}
                  </Title>
                  <Paragraph type="secondary" style={{ marginTop: '0.5rem', fontSize: '14px' }}>
                    {option.description}
                  </Paragraph>
                </Card>
              </Col>
            ))}
          </Row>
        </div>
      ) : (
        <Paragraph>로그인이 필요합니다.</Paragraph>
      )}
    </BaseLayout>
  );
};

export default SlurmJobDashboard;
