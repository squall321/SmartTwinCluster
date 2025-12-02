import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Layout, Menu } from 'antd';
import { useLocation, useNavigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import styles from './BaseLayout.module.css';
import backgroundImage from '../images/background.png';
const { Header, Content } = Layout;
const BaseLayout = ({ children, isLoggedIn }) => {
    const navigate = useNavigate();
    const location = useLocation();
    const [selectedKey, setSelectedKey] = useState('home');
    const handleLogout = () => {
        localStorage.removeItem('isLoggedIn');
        navigate('/login');
    };
    // 경로 기반 selectedKey 업데이트
    useEffect(() => {
        const path = location.pathname;
        if (path.includes('abd-calculator'))
            setSelectedKey('abd-calculator');
        else if (path.includes('advanced-display-builder'))
            setSelectedKey('advanced-display-builder');
        else if (path.includes('elastic-to-rigid-builder'))
            setSelectedKey('elastic-to-rigid-builder');
        else if (path.includes('box-morph'))
            setSelectedKey('box-morph');
        else if (path.includes('warp-to-stress'))
            setSelectedKey('warp-to-stress');
        else if (path.includes('drop-attitude-generator'))
            setSelectedKey('drop-attitude-generator');
        else if (path.includes('full-angle-drops'))
            setSelectedKey('full-angle-drops');
        else if (path.includes('drop-weight-impact-test-generator'))
            setSelectedKey('drop-weight-impact-test-generator');
        else if (path.includes('login'))
            setSelectedKey('login');
        else
            setSelectedKey('home');
    }, [location.pathname]);
    const menuItems = [
        {
            key: 'home',
            label: '홈',
            onClick: () => navigate('/'),
        },
        {
            key: 'theories',
            label: '이론',
            children: [
                {
                    key: 'fem-structural-analysis',
                    label: '유한요소법 구조해석',
                    onClick: () => navigate('/fem-structural-analysis'),
                },
                {
                    key: 'pde-fem',
                    label: '편미분방정식 유한요소법',
                    onClick: () => navigate('/pde-fem'),
                },
            ],
        },
        {
            key: 'material-enhancement',
            label: '물성 고도화',
            children: [
                {
                    key: 'abd-calculator',
                    label: 'ABD 행렬 계산기',
                    onClick: () => navigate('/abd-calculator'),
                },
                {
                    key: 'ramberg-osgood',
                    label: 'Ramberg-Osgood 소성 재료 모델',
                    onClick: () => navigate('/ramberg-osgood'),
                },
                {
                    key: 'viscoelastic-visualizer',
                    label: '점탄성 재료 모델',
                    onClick: () => navigate('/viscoelastic-visualizer'),
                },
            ],
        },
        {
            key: "module-enhancement",
            label: "모듈 모델링 고도화",
            children: [
                {
                    key: 'contact-stiffness-demo',
                    label: '충돌 강성 시뮬레이션',
                    onClick: () => navigate('/contact-stiffness-demo'),
                },
                {
                    key: 'mck-editor',
                    label: 'MCK 시뮬레이션',
                    onClick: () => navigate('/mck-editor'),
                },
                {
                    key: 'three-point-bending',
                    label: '3점 굽힘 시뮬레이션',
                    onClick: () => navigate('/three-point-bending'),
                },
                {
                    key: "motor-simulation",
                    label: "모터",
                    children: [
                        {
                            key: "motor-level-simulation",
                            label: "모터 진동량 시뮬레이션",
                            onClick: () => navigate("/motor-level-simulation"),
                        },
                        {
                            key: "pwm-generator",
                            label: "PWM 생성기",
                            onClick: () => navigate("/pwm-generator"),
                        },
                    ],
                },
                {
                    key: "package-generator",
                    label: "패키지 생성기",
                    onClick: () => navigate("/package-generator"),
                }
            ]
        },
        {
            key: 'modeling-enhancement',
            label: '세트 모델링 고도화',
            children: [
                {
                    key: 'advanced-display-builder',
                    label: '디스플레이 적층 고도화',
                    onClick: () => navigate('/advanced-display-builder'),
                },
                {
                    key: 'advanced-battery-builder',
                    label: '배터리 모델링 고도화',
                    onClick: () => navigate('/advanced-battery-builder'),
                },
                {
                    key: 'elastic-to-rigid-builder',
                    label: '부분 강체화',
                    onClick: () => navigate('/elastic-to-rigid-builder'),
                },
                {
                    key: 'box-morph',
                    label: '박스 모핑 고도화',
                    onClick: () => navigate('/box-morph'),
                },
                {
                    key: 'warp-to-stress',
                    label: '휨→응력 변환 고도화',
                    onClick: () => navigate('/warp-to-stress'),
                },
                {
                    key: 'dimensional-tolerance',
                    label: '치수 산포 고도화',
                    onClick: () => navigate('/dimensional-tolerance'),
                }
            ],
        },
        {
            key: 'simulation-variation',
            label: '디지털 트윈 시뮬레이션',
            children: [
                {
                    key: 'drop-attitude-generator',
                    label: '낙하 자세 생성기',
                    onClick: () => navigate('/drop-attitude-generator'),
                },
                {
                    key: 'full-angle-drops-mdb',
                    label: '전각도 다물체 동역학 낙하 시뮬레이션',
                    onClick: () => navigate('/full-angle-drops-mdb'),
                },
                {
                    key: 'full-angle-drops',
                    label: '전각도 낙하 시뮬레이션',
                    onClick: () => navigate('/full-angle-drops'),
                },
                {
                    key: 'drop-weight-impact-test-generator',
                    label: '부분 충격 생성기',
                    onClick: () => navigate('/drop-weight-impact-test-generator'),
                },
                {
                    key: 'all-points-drop-weight-impact-generator',
                    label: '전위치 부분 충격 시뮬레이션',
                    onClick: () => navigate('/all-points-drop-weight-impact-generator'),
                }
            ],
        },
        {
            key: "simulation",
            label: "시뮬레이션",
            children: [
                { key: 'slurm-job-submit-dashboard',
                    label: 'Job 제출',
                    onClick: () => navigate('/slurm-job-submit-dashboard'),
                },
                {
                    key: 'slurm-status',
                    label: 'Job 상태 확인',
                    onClick: () => navigate('/slurm-status'),
                }
            ],
        },
        {
            key: 'simulation-modelling-automation',
            label: '자동화 툴 실행',
            children: [
                {
                    key: 'simulation-automation',
                    label: 'Simulation Automation',
                    onClick: () => navigate('/simulation-automation'),
                },
                {
                    key: 'mesh-modifier',
                    label: 'Mesh Modifier',
                    onClick: () => navigate('/mesh-modifier'),
                },
                {
                    key: 'automated-modeller',
                    label: 'Automated Modeller',
                    onClick: () => navigate('/automated-modeller'),
                },
            ],
        },
        {
            key: 'post',
            label: '결과 확인',
            children: [
                {
                    key: 'post-full-angle-drops',
                    label: '전각도 충돌 시뮬레이션 결과',
                    onClick: () => navigate('/post-full-angle-drops'),
                },
            ],
        },
        isLoggedIn
            ? {
                key: 'logout',
                label: '로그아웃',
                onClick: handleLogout,
            }
            : {
                key: 'login',
                label: '로그인',
                onClick: () => navigate('/login'),
            },
    ];
    return (_jsxs(Layout, { style: { minHeight: '100vh' }, children: [_jsx(Header, { style: { position: 'fixed', zIndex: 1, width: '100%', padding: 0 }, children: _jsxs("div", { style: { display: 'flex', flexDirection: 'column' }, children: [_jsxs("div", { style: {
                                height: '40px',
                                display: 'flex',
                                alignItems: 'center',
                                padding: '0 2rem',
                                color: '#00ffff',
                                fontSize: '20px',
                                fontWeight: 'bold',
                                fontFamily: 'Orbitron, Rajdhani, Poppins, sans-serif',
                                letterSpacing: '1px',
                                textShadow: '0 0 4px #00ffff',
                            }, children: ["STCX", ' ', _jsx("span", { style: {
                                        marginLeft: '0.5rem',
                                        fontWeight: 'normal',
                                        color: '#fff',
                                        fontFamily: 'Segoe UI, Roboto, sans-serif',
                                    }, children: "Smart Twin Cluster eXtreme" })] }), _jsx(Menu, { theme: "dark", mode: "horizontal", selectedKeys: [selectedKey], onClick: (e) => setSelectedKey(e.key), items: menuItems, className: styles.menu, triggerSubMenuAction: "hover", subMenuOpenDelay: 0.15, subMenuCloseDelay: 0.3, style: {
                                margin: 0,
                                width: '100%',
                                borderTop: '1px solid rgba(255,255,255,0.1)',
                                fontFamily: `'Poppins', 'Orbitron', 'Rajdhani', sans-serif`,
                                fontSize: '16px',
                                fontWeight: 500,
                                letterSpacing: '0.5px',
                                zIndex: 1000,
                            } })] }) }), _jsx(Content, { style: {
                    marginTop: 104,
                    display: 'flex',
                    justifyContent: 'center',
                    alignItems: 'flex-start',
                    minHeight: 'calc(100vh - 104px)',
                    padding: '2rem',
                    width: '100%',
                    backgroundImage: `url(${backgroundImage})`,
                    backgroundRepeat: 'no-repeat',
                    backgroundSize: '100% auto', // ⬅️ 좌우 꽉 차고 세로는 비율 유지
                    backgroundPosition: 'top center',
                    backgroundAttachment: 'fixed', // ⬅️ 배경이 스크롤 안 됨!
                }, children: _jsx("div", { style: { width: '100%', backgroundColor: 'rgba(255,255,255,0.1)' }, children: children }) })] }));
};
export default BaseLayout;
