// src/pages/Dashboard.tsx
import { Card, Row, Col, Typography } from 'antd';
import { useNavigate } from 'react-router-dom';
import BaseLayout from '../layouts/BaseLayout';
import { useEffect, useState } from 'react';
import styles from './Dashboard.module.css';
import FileTreeExplorer from '@components/common/FileTreeExplorer';

const { Title, Paragraph } = Typography;

const Dashboard = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const navigate = useNavigate();
  const username = localStorage.getItem('username') || 'default_user';
  const prefix = localStorage.getItem('prefix') || '';

  useEffect(() => {
    // Check for token in URL (from Auth Portal)
    const urlParams = new URLSearchParams(window.location.search);
    const urlToken = urlParams.get('token');

    if (urlToken) {
      // Save token from URL
      localStorage.setItem('jwt_token', urlToken);
      localStorage.setItem('isLoggedIn', 'true');

      // Try to decode JWT and save user info
      try {
        const base64Url = urlToken.split('.')[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(
          atob(base64)
            .split('')
            .map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
            .join('')
        );
        const payload = JSON.parse(jsonPayload);
        if (payload.sub) {
          localStorage.setItem('username', payload.sub);
        }
      } catch (e) {
        console.error('Failed to decode JWT:', e);
      }

      // Remove token from URL for security (prevent token exposure in browser history)
      window.history.replaceState({}, document.title, window.location.pathname);
      setIsLoggedIn(true);
      return;
    }

    const loggedIn = localStorage.getItem('isLoggedIn') === 'true';
    const token = localStorage.getItem('jwt_token');

    // JWT 토큰이 있으면 로그인 상태로 간주
    if (token && !loggedIn) {
      localStorage.setItem('isLoggedIn', 'true');
      setIsLoggedIn(true);
    } else if (!loggedIn && !token) {
      // 로그인되지 않았으면 로그인 페이지로 리다이렉트
      navigate('/login');
    } else {
      setIsLoggedIn(loggedIn);
    }
  }, [navigate]);

  const features = [
    {
      icon: '',
      title: '낙하 자세 생성기',
      description: '낙하 초기 자세를 손쉽게 설정할 수 있습니다.',
      onClick: () => navigate('/drop-attitude-generator'),
    },
    {
      icon: '',
      title: '전각도 다물체 동역학 낙하 시뮬레이션',
      description: '전각도 다물체 동역학 낙하 시뮬레이션 기능을 제공합니다.',
      onClick: () => navigate('/full-angle-drops-mdb'),
    },
    {
      icon: '',
      title: '전각도 낙하 시뮬레이션',
      description: '다양한 각도의 낙하 조건을 설정하고 시뮬레이션을 실행합니다.',
      onClick: () => navigate('/full-angle-drops'),
    },
    {
      icon: '',
      title: '부분 충격 생성기',
      description: '부분 충격 생성기 기능을 제공합니다.',
      onClick: () => navigate('/drop-weight-impact-test-generator'),
    },
    {
      icon: '',
      title: '전위치 부분 충격 시뮬레이션',
      description: '전위치 부분 충격 시뮬레이션 기능을 제공합니다.',
      onClick: () => navigate('/all-points-drop-weight-impact-generator'),
    },
    {
      icon: '',
      title: 'ABD 행렬 계산기',
      description: '복합재료 적층 구조의 ABD 행렬을 계산합니다.',
      onClick: () => navigate('/abd-calculator'),
    },
    {
      icon: '',
      title: 'Ramberg-Osgood 소성 재료 모델',
      description: 'Ramberg-Osgood 소성 재료 모델 기능을 제공합니다.',
      onClick: () => navigate('/ramberg-osgood'),
    },
    {
      icon: '',
      title: '점탄성 재료 모델',
      description: '점탄성 재료 모델 기능을 제공합니다.',
      onClick: () => navigate('/viscoelastic-visualizer'),
    },
    {
      icon: '',
      title: '충돌 강성 시뮬레이션',
      description: '충돌 강성 시뮬레이션 기능을 제공합니다.',
      onClick: () => navigate('/contact-stiffness-demo'),
    },
    {
      icon: '',
      title: 'MCK 시뮬레이션',
      description: 'MCK 시뮬레이션 기능을 제공합니다.',
      onClick: () => navigate('/mck-editor'),
    },
    {
      icon: '',
      title: '3점 굽힘 시뮬레이션',
      description: '3점 굽힘 시뮬레이션 기능을 제공합니다.',
      onClick: () => navigate('/three-point-bending'),
    },
    {
      icon: '',
      title: '모터 진동량 시뮬레이션',
      description: '모터 진동량 시뮬레이션 기능을 제공합니다.',
      onClick: () => navigate('/motor-level-simulation'),
    },
    {
      icon: '',
      title: 'PWM 생성기',
      description: 'PWM 생성기 기능을 제공합니다.',
      onClick: () => navigate('/pwm-generator'),
    },
    {
      icon: '',
      title: '패키지 생성기',
      description: '패키지 생성기 기능을 제공합니다.',
      onClick: () => navigate('/package-generator'),
    },
    {
      icon: '',
      title: '디스플레이 적층 고도화',
      description: '디스플레이 적층 고도화 기능을 제공합니다.',
      onClick: () => navigate('/advanced-display-builder'),
    },
    {
      icon: '',
      title: '부분 강체화',
      description: '부분 강체화 기능을 제공합니다.',
      onClick: () => navigate('/elastic-to-rigid-builder'),
    },
    {
      icon: '',
      title: '박스 모핑',
      description: '박스 모핑 기능을 제공합니다.',
      onClick: () => navigate('/box-morph'),
    },
    {
      icon: '',
      title: '휨→응력 변환기',
      description: '휨→응력 변환기 기능을 제공합니다.',
      onClick: () => navigate('/warp-to-stress'),
    },
    {
      icon: '',
      title: 'Mesh Modifier',
      description: 'Mesh Modifier 기능을 제공합니다.',
      onClick: () => navigate('/mesh-modifier'),
    },
    {
      icon: '',
      title: 'Automated Modeller',
      description: 'Automated Modeller 기능을 제공합니다.',
      onClick: () => navigate('/automated-modeller'),
    },
    {
      icon: '',
      title: 'Slurm 대시보드',
      description: 'Slurm 대시보드 기능을 제공합니다.',
      onClick: () => navigate('/slurm-status'),
    },
    {
      icon: '',
      title: '추가 기능 준비 중',
      description: '추가 기능이 여기에 표시될 예정입니다.',
      onClick: () => {},
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
      <Title level={1} style={{ marginBottom: '1rem', fontWeight: 'bold' }}>
        Smart Twin Cluster eXtreme (STC-X)
      </Title>
      {/* 설명 텍스트 */}
      <Paragraph type="secondary" style={{ fontSize: '20px', maxWidth: '960px', margin: '0 auto' }}>
        STC-X는 차세대 디지털 트윈 환경을 위한 고성능 시뮬레이션 클러스터 플랫폼입니다. <br />
        복잡한 물리 기반 모델을 HPC 환경에서 실시간으로 실행하고 분석할 수 있는 최적의 인프라를 제공합니다. <br />
        또한, 디지털 트윈 환경을 위한 다양한 시뮬레이션 툴을 제공합니다. <br />
      </Paragraph>
      {/* 배너 이미지 삽입 */}
      


          <div style={{ marginBottom: '2rem' }} /> {/* 여기가 여백 역할 */} 
          <Title level={2} style={{ marginBottom: '2rem', fontWeight: 'bold' }}>
            {username} 님의 파일 관리 페이지
          </Title>
        
          <div style={{ marginBottom: '2rem' }} /> {/* 여기가 여백 역할 */}

          <FileTreeExplorer
            username={username}
            prefix={prefix || undefined}
            allowDeleteDir={true}
          />
          
          <div style={{ marginBottom: '2rem' }} /> {/* 여기가 여백 역할 */}

          <Title level={2} style={{ marginBottom: '2rem', fontWeight: 'bold' }}>
            📊 시뮬레이션 대시보드
          </Title>
          <Row gutter={[24, 24]}>
            {features.map((feature, index) => (
              <Col xs={24} sm={12} md={8} key={index}>
                <Card
                  className={styles.cardHoverEffect}
                  hoverable
                  onClick={feature.onClick}
                  style={{
                    cursor: 'pointer',
                    height: '180px',
                    borderRadius: '12px',
                    boxShadow: '0 4px 12px rgba(0, 0, 0, 0.08)',
                    transition: 'transform 0.2s ease',
                  }}
                  bodyStyle={{ display: 'flex', flexDirection: 'column', justifyContent: 'center' }}
                >
                  <div style={{ fontSize: '24px', marginBottom: '0.5rem' }}>{feature.icon}</div>
                  <Title level={4} style={{ margin: 0, fontWeight: 600 }}>
                    {feature.title}
                  </Title>
                  <Paragraph type="secondary" style={{ marginTop: '0.5rem', fontSize: '14px' }}>
                    {feature.description}
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

export default Dashboard;
