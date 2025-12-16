import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import { Upload, message, Spin } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import { api } from '../../api/axiosClient';
const { Dragger } = Upload;
const PartIdFinderUploader = ({ onParsed }) => {
    const [loading, setLoading] = useState(false);
    const username = localStorage.getItem('username') || 'default_user';
    const handleFileUpload = (info) => {
        const file = info.fileList[0]?.originFileObj;
        if (!file) {
            message.error('파일을 불러올 수 없습니다.');
            return;
        }
        uploadAndParseKFile(file);
    };
    const uploadAndParseKFile = async (file) => {
        const formData = new FormData();
        formData.append('file', file);
        formData.append('user', username);
        try {
            setLoading(true);
            const response = await api.post('/api/upload_dyna_file_and_find_pid', formData, {
                headers: { 'Content-Type': 'multipart/form-data' },
            });
            const data = response.data;
            onParsed(data.filename, data.parts, file);
            message.success(`${data.filename} 파일에서 ${data.parts.length}개 파트 ID 파싱 완료`);
        }
        catch (err) {
            console.error('❌ 파트 ID 파싱 실패:', err);
            message.error('서버와의 연결에 실패했거나 파일 형식이 잘못되었습니다.');
        }
        finally {
            setLoading(false);
        }
    };
    return (_jsx(Spin, { spinning: loading, tip: "\uD30C\uC77C \uC5C5\uB85C\uB4DC \uBC0F \uD30C\uC2F1 \uC911\uC785\uB2C8\uB2E4...", children: _jsxs(Dragger, { name: "file", multiple: false, beforeUpload: () => false, onChange: handleFileUpload, showUploadList: false, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "K \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uC5EC PART ID\uB97C \uCD94\uCD9C\uD569\uB2C8\uB2E4" })] }) }));
};
export default PartIdFinderUploader;
