/**
 * Enhanced SubmitLsdynaPanel with Apptainer Template Integration v2
 *
 * 새로운 기능:
 * - 템플릿으로 저장 기능
 * - 저장된 템플릿 불러오기
 * - 템플릿 기반 제출 시 template_id와 image_path 전송
 */
import React from 'react';
import type { LsdynaJobConfig } from '../uploader/LsdynaOptionTable';
interface SubmitLsdynaPanelWithTemplatesProps {
    initialConfigs?: LsdynaJobConfig[];
    autoSubmit?: boolean;
    onSubmitSuccess?: (submitted: any[]) => void;
}
declare const SubmitLsdynaPanelWithTemplates: React.FC<SubmitLsdynaPanelWithTemplatesProps>;
export default SubmitLsdynaPanelWithTemplates;
