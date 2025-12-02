import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import MolbeideStressPlot from '../components/MolbeideStressPlot';

const { Title, Paragraph } = Typography;

const PostFullAngleDropsPage = () => {
    return (
        <BaseLayout isLoggedIn={true}>
            <div style={{ padding: 24, backgroundColor: '#fff', minHeight: '100vh', borderRadius: '24px' }}>
                <Title level={3}> 전각도 충돌 시뮬레이션 결과</Title>
                <Paragraph>
                    전각도 충돌 시뮬레이션 결과를 보여줍니다.
                </Paragraph>

                <MolbeideStressPlot />
            </div>
        </BaseLayout>
    );
};

export default PostFullAngleDropsPage;  