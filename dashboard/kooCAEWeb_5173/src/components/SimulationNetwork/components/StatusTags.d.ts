import React from 'react';
import { CaseStatus } from '../types/simulationnetwork';
interface Props {
    statuses: CaseStatus[];
}
declare const StatusTags: React.FC<Props>;
export default StatusTags;
