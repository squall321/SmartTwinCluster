import React from 'react';
import MckLayout from '../../layouts/mck/MckLayout';
import BaseLayout from '../../layouts/BaseLayout';
import { Typography } from 'antd';
import ModelFormulaBox from '../../components/common/ModelFormulaBox';

const { Title, Paragraph } = Typography;

const MckEditorPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={false}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>MCK 시뮬레이션</Title>
        <Paragraph>
          이 페이지에서는 MCK 시스템 모델을 시뮬레이션할 수 있습니다.
        </Paragraph>

        {/* ✅ MCK 시스템 이론 박스 */}
        <ModelFormulaBox
          title="MCK 시스템 운동방정식"
          description="MCK 시스템의 운동방정식은 질량, 감쇠, 강성 행렬로 구성됩니다."
          formulas={[
            'M \\ddot{x}(t) + C \\dot{x}(t) + K x(t) = F(t)',
          ]}
        />

        {/* ✅ Modal 해석 이론 박스 */}
        <ModelFormulaBox
          title="Modal Analysis"
          description="모달 해석에서는 고유치 문제를 풀어 시스템의 고유진동수와 감쇠비를 구합니다."
          formulas={[
            'det\\bigl(K - \\omega^2 M\\bigr) = 0',
            '\\zeta = -\\frac{\\text{Re}(\\lambda)}{\\sqrt{\\text{Re}(\\lambda)^2 + \\text{Im}(\\lambda)^2}}',
            'f_n = \\frac{\\sqrt{\\text{Re}(\\lambda)^2 + \\text{Im}(\\lambda)^2}}{2 \\pi}',
          ]}
        />

        {/* ✅ Harmonic 해석 이론 박스 */}
        <ModelFormulaBox
          title="Harmonic Response"
          description="하모닉 해석에서는 주어진 주파수에 대해 시스템 응답을 계산합니다."
          formulas={[
            'Z(j\\omega) = -\\omega^2 M + j\\omega C + K',
            'X(j\\omega) = Z(j\\omega)^{-1} F(j\\omega)',
            '|X(j\\omega)|_{dB} = 20 \\log_{10} |X(j\\omega)|',
          ]}
        />
      </div>

      <MckLayout />
    </BaseLayout>
  );
};

export default MckEditorPage;
