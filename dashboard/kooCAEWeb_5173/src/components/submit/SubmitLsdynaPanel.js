import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Button, message } from 'antd';
import LsdynaFileUploader from '../uploader/LsdynaFileUploader';
import { api } from '../../api/axiosClient';
const SubmitLsdynaPanel = ({ initialConfigs, autoSubmit = false, onSubmitSuccess, }) => {
    const [configs, setConfigs] = useState([]);
    // ✅ 최초 초기값 한 번만 반영 (무한 루프 방지)
    useEffect(() => {
        if (initialConfigs && configs.length === 0) {
            setConfigs(initialConfigs);
        }
    }, [initialConfigs, configs.length]);
    const handleDataUpdate = (updated) => {
        setConfigs(updated);
    };
    const handleSubmit = async () => {
        if (configs.length === 0) {
            message.warning('업로드된 파일이 없습니다.');
            return;
        }
        const formData = new FormData();
        configs.forEach((cfg, i) => {
            formData.append('files', cfg.file);
            formData.append(`meta[${i}]`, JSON.stringify({
                filename: cfg.filename,
                cores: cfg.cores,
                precision: cfg.precision,
                version: cfg.version,
                mode: cfg.mode,
            }));
        });
        try {
            const res = await api.post("/api/slurm/submit-lsdyna-jobs", formData, {
                headers: { 'Content-Type': 'multipart/form-data' },
            });
            if (Array.isArray(res.data.submitted)) {
                message.success(`총 ${res.data.submitted.length}개의 Job 제출 성공`);
                setConfigs([]);
                onSubmitSuccess?.(res.data.submitted);
            }
            else {
                message.error(res.data.error || '제출 실패: submitted 정보가 없습니다.');
            }
        }
        catch (err) {
            message.error(err?.response?.data?.error || err?.message || '제출 중 서버 오류 발생');
        }
    };
    // ✅ autoSubmit은 configs 상태 기준
    useEffect(() => {
        if (autoSubmit && configs.length > 0) {
            handleSubmit();
        }
    }, [configs, autoSubmit]);
    return (_jsxs(_Fragment, { children: [_jsx(LsdynaFileUploader, { onDataUpdate: handleDataUpdate, initialData: configs }), configs.length > 0 && !autoSubmit && (_jsx("div", { style: { textAlign: 'right', marginTop: '1rem' }, children: _jsx(Button, { type: "primary", onClick: handleSubmit, children: "Submit" }) }))] }));
};
export default SubmitLsdynaPanel;
