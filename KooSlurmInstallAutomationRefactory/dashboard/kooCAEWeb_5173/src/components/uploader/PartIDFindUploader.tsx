import React, { useState } from 'react';
import { Upload, message, Spin } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import type { UploadChangeParam } from 'antd/es/upload';
import { api } from '../../api/axiosClient';

const { Dragger } = Upload;
import { ParsedPart } from '../../types/parsedPart';

interface PartIdFinderUploaderProps {
  onParsed: (filename: string, parts: ParsedPart[], file?: File) => void;
}

const PartIdFinderUploader: React.FC<PartIdFinderUploaderProps> = ({ onParsed }) => {
  const [loading, setLoading] = useState(false);
  const username = localStorage.getItem('username') || 'default_user';
  const handleFileUpload = (info: UploadChangeParam) => {
    const file = info.fileList[0]?.originFileObj as File | undefined;
    if (!file) {
      message.error('파일을 불러올 수 없습니다.');
      return;
    }
    uploadAndParseKFile(file);
  };

  const uploadAndParseKFile = async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('user', username);

    try {
      setLoading(true);

      const response = await api.post(
        '/api/upload_dyna_file_and_find_pid',
        formData,
        {
          headers: { 'Content-Type': 'multipart/form-data' },
        }
      );

      const data = response.data;

      onParsed(data.filename, data.parts, file);
      message.success(`${data.filename} 파일에서 ${data.parts.length}개 파트 ID 파싱 완료`);
    } catch (err: any) {
      console.error('❌ 파트 ID 파싱 실패:', err);
      message.error('서버와의 연결에 실패했거나 파일 형식이 잘못되었습니다.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Spin spinning={loading} tip="파일 업로드 및 파싱 중입니다...">
      <Dragger
        name="file"
        multiple={false}
        beforeUpload={() => false}
        onChange={handleFileUpload}
        showUploadList={false}
      >
        <p className="ant-upload-drag-icon">
          <InboxOutlined />
        </p>
        <p className="ant-upload-text">K 파일을 업로드하여 PART ID를 추출합니다</p>
      </Dragger>
    </Spin>
  );
};

export default PartIdFinderUploader;
