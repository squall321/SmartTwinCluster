/**
 * Standard Scenario Modal Component
 * 표준 규격 시나리오 선택 모달
 */
import React from 'react';
import type { StandardScenario } from '../../types/standardScenario';
interface StandardScenarioModalProps {
    visible: boolean;
    onClose: () => void;
    onSelect: (scenario: StandardScenario) => void;
}
declare const StandardScenarioModal: React.FC<StandardScenarioModalProps>;
export default StandardScenarioModal;
