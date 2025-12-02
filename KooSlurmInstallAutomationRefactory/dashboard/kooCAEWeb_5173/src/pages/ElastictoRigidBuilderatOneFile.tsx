import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import {
  Upload, Typography, AutoComplete, Button, message,
  Divider, Table
} from 'antd';
import { InboxOutlined, DownloadOutlined } from '@ant-design/icons';
import type { UploadChangeParam } from 'antd/es/upload';
import { api } from '../api/axiosClient';

const { Dragger } = Upload;
const { Title, Paragraph } = Typography;

interface ParsedPart {
  id: string;
  name: string;
}

const ElasticToRigidBuilder: React.FC = () => {
  const [kFileName, setKFileName] = useState<string>('Impact_1_00000001.k');
  const [allPartInfos, setAllPartInfos] = useState<ParsedPart[]>([]);
  const [excludePartIds, setExcludePartIds] = useState<ParsedPart[]>([]);
  const username = localStorage.getItem('username') || 'default_user';
  const uploadAndParseKFile = async (file: File) => {
    const formData = new FormData();
    formData.append("file", file);
    formData.append("user", username);
  
    try {
      const response = await api.post("/api/upload_dyna_file_and_find_pid", formData, {
        headers: {
          "Content-Type": "multipart/form-data"
        },
        // 필요 시 credentials 포함:
        // withCredentials: true
      });
  
      const data = response.data;
      console.log(data);
      const filename = data.filename;
      const parts = data.parts;

      
      // 상태 업데이트 예시
      setKFileName(filename);
      setAllPartInfos(parts);
      setExcludePartIds([]);
      message.success(`${filename} 파일에서 ${parts.length}개 파트 파싱 완료`);
  
    } catch (err: any) {
      console.error("❌ Axios 업로드 실패:", err);
      if (err.response?.data?.error) {
        message.error(`업로드 실패: ${err.response.data.error}`);
      } else {
        message.error("서버와의 연결에 실패했습니다.");
      }
    }
  };
  const handleFileUpload = (info: UploadChangeParam) => {
    const file = info.fileList[0]?.originFileObj;
    if (!file) {
      message.error('파일을 불러올 수 없습니다.');
      return;
    }
  
    setKFileName(file.name);
    uploadAndParseKFile(file);
  };

  const handlePartSelect = (value: string) => {
    const found = allPartInfos.find(part =>
      part.id === value || part.name === value
    );
    if (found && !excludePartIds.find(p => p.id === found.id)) {
      setExcludePartIds(prev => [...prev, found]);
    }
  };

  const exportRigidScript = () => {
    const modeId = 1;
    const excludedIds = excludePartIds.map(p => p.id);
    const allIds = allPartInfos.map(p => p.id);
    const includedIds = allIds.filter(id => !excludedIds.includes(id));

    const lines: string[] = [];
    lines.push(`*Inputfile`);
    lines.push(`${kFileName}`);
    lines.push(`*Mode`);
    lines.push(`ELASTIC_TO_RIGID,${modeId}`);
    lines.push(`**ElastictoRigid,${modeId}`);
    lines.push(`*PIDExcept,${excludedIds.join(',')}`);
    lines.push(`**EndElastictoRigid`);
    lines.push(`*End`);

    const blob = new Blob([lines.join('\n')], { type: 'text/plain;charset=utf-8' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'elasticToRigidOption.txt';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Typography.Title level={3}>Elastic to Rigid 변환 생성기</Typography.Title>
        <Paragraph>
        이 컴포넌트는 LS-DYNA의 탄성 파트를 강체로 변환하는 옵션 파일을 쉽게 생성할 수 있도록 도와줍니다. 사용자는 .k 파일을 업로드하고, 강체로 변환하지 않을 파트를 선택한 뒤, 버튼을 눌러 옵션 파일을 다운로드할 수 있습니다. 간편한 UI로 변환 설정을 빠르게 구성할 수 있습니다.
        </Paragraph>

        <Dragger
          name="file"
          multiple={false}
          beforeUpload={() => false}
          onChange={handleFileUpload}
          style={{ marginBottom: 16 }}
        >
          <p className="ant-upload-drag-icon">
            <InboxOutlined />
          </p>
          <p className="ant-upload-text">K 파일을 여기에 드래그하거나 클릭하여 선택</p>
        </Dragger>

        <Typography.Text type="secondary">{kFileName}</Typography.Text>
        <Divider />

        <Typography.Title level={4}>제외할 PART ID 또는 이름 선택</Typography.Title>
        <AutoComplete
          style={{ width: '100%' }}
          placeholder="예: 1001 또는 PI_LAYER"
          options={allPartInfos.map(part => ({
            value: part.id,
            label: `${part.id} - ${part.name}`
          }))}
          filterOption={(inputValue, option) =>
            option?.label.toLowerCase().includes(inputValue.toLowerCase()) ?? false
          }
          onSelect={handlePartSelect}
        />

        <Table
          dataSource={excludePartIds.map((p, i) => ({ ...p, key: i }))}
          columns={[
            { title: 'ID', dataIndex: 'id', key: 'id' },
            { title: '이름', dataIndex: 'name', key: 'name' },
            {
              title: '작업',
              render: (_, record) => (
                <Button danger onClick={() => {
                  setExcludePartIds(prev => prev.filter(p => p.id !== record.id));
                }}>제거</Button>
              )
            }
          ]}
          pagination={false}
          style={{ marginTop: 24 }}
        />

        <div style={{ marginTop: 32, textAlign: 'center' }}>
          <Button type="primary" icon={<DownloadOutlined />} onClick={exportRigidScript}>
            옵션파일 출력
          </Button>
        </div>
      </div>
    </BaseLayout>
  );
};

export default ElasticToRigidBuilder;
