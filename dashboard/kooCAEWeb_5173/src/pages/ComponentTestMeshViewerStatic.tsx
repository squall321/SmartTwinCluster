import React, { useCallback, useState } from 'react';
import { Typography, Upload, message } from 'antd';
import type { UploadProps } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import GltfViewerComponent from '../components/GLTFViewerComponent';

const { Title, Paragraph } = Typography;
const { Dragger } = Upload;

const ComponentTestMeshViewerPage: React.FC = () => {
  const [file, setFile] = useState<File | null>(null);

  const handleFile = useCallback((file: File) => {
    const name = file.name.toLowerCase();
    if (!name.endsWith('.gltf') && !name.endsWith('.glb')) {
      message.error('❌ GLTF 또는 GLB 파일만 지원됩니다.');
      return false;
    }
    setFile(file);
    return false; // 수동 업로드
  }, []);

  const uploadProps: UploadProps = {
    multiple: false,
    beforeUpload: handleFile,
    showUploadList: false,
    accept: '.gltf,.glb',
  };

  return (
    <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
      <Title level={3}>📦 GLTF/GLB 드래그 테스트</Title>
      <Paragraph>GLTF 또는 GLB 파일을 드래그하면 3D로 가시화됩니다.</Paragraph>

      <Dragger {...uploadProps} style={{ marginBottom: 32 }}>
        <p className="ant-upload-drag-icon">
          <InboxOutlined />
        </p>
        <p className="ant-upload-text">여기에 파일을 드래그하거나 클릭해서 선택하세요</p>
      </Dragger>

      {file && <GltfViewerComponent file={file} />}
    </div>
  );
};

export default ComponentTestMeshViewerPage;
