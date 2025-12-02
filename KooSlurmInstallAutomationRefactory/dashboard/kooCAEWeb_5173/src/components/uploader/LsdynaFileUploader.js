import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Upload, Typography, message } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import LsdynaOptionTable from './LsdynaOptionTable';
const { Dragger } = Upload;
const { Title } = Typography;
const LsdynaFileUploader = ({ onDataUpdate, initialData }) => {
    const [data, setData] = useState([]);
    // ✅ 초기 데이터 반영
    useEffect(() => {
        if (initialData && initialData.length > 0) {
            setData(initialData);
            onDataUpdate?.(initialData);
        }
    }, [initialData, onDataUpdate]);
    // ✅ 파일 업로드 처리
    const handleFileDrop = (info) => {
        const files = info.fileList
            .filter((f) => f.originFileObj && f.name.endsWith('.k'))
            .map((f) => f.originFileObj);
        if (files.length === 0) {
            message.warning('확장자가 .k인 파일만 업로드할 수 있습니다.');
            return;
        }
        const existingFilenames = new Set(data.map((d) => d.filename));
        const newData = files
            .filter((file) => !existingFilenames.has(file.name)) // 중복 제거
            .map((file) => ({
            key: `${file.name}_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
            filename: file.name,
            file,
            cores: 16,
            precision: 'single',
            version: 'R15',
            mode: 'SMP',
        }));
        if (newData.length === 0) {
            message.info('이미 등록된 파일은 제외되었습니다.');
        }
        const updated = [...data, ...newData];
        setData(updated);
        onDataUpdate?.(updated);
    };
    // ✅ 전체 필드 일괄 수정
    const updateAll = (field, value) => {
        const updated = data.map((row) => ({ ...row, [field]: value }));
        setData(updated);
        onDataUpdate?.(updated);
    };
    // ✅ 개별 행 수정
    const updateRow = (key, field, value) => {
        const updated = data.map((row) => row.key === key ? { ...row, [field]: value } : row);
        setData(updated);
        onDataUpdate?.(updated);
    };
    // ✅ 행 삭제
    const deleteRow = (key) => {
        const updated = data.filter((row) => row.key !== key);
        setData(updated);
        onDataUpdate?.(updated);
    };
    return (_jsxs(_Fragment, { children: [_jsx(Title, { level: 4, children: "\uD83D\uDCC2 LS-DYNA K \uD30C\uC77C \uC5C5\uB85C\uB4DC" }), _jsxs(Dragger, { multiple: true, beforeUpload: () => false, onChange: handleFileDrop, accept: ".k", style: { marginBottom: 24 }, showUploadList: false, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "\uC5EC\uAE30\uC5D0 K \uD30C\uC77C\uB4E4\uC744 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC5C5\uB85C\uB4DC\uD558\uC138\uC694" })] }), _jsx(LsdynaOptionTable, { data: data, onUpdateAll: updateAll, onUpdateRow: updateRow, onDeleteRow: deleteRow })] }));
};
export default LsdynaFileUploader;
