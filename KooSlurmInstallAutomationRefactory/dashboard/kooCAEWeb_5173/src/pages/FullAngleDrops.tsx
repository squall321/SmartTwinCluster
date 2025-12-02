import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Upload, Table, Typography, message, Spin, Button } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/axiosClient';

const { Dragger } = Upload;
const { Title } = Typography;

const FullAngleDrop = () => {
  const [data, setData] = useState<any[]>([]);
  const [columns, setColumns] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const columnNameMap: Record<string, React.ReactNode> = {
    filename: <>파일명</>,
    "Short File Name": <>파일명</>,
    Number: <>번호</>,
    EX: <>Roll<br />(Deg)</>,
    EY: <>Pitch<br />(Deg)</>,
    EZ: <>Yaw<br />(Deg)</>,
    H: <>높이<br />(m)</>,
    VX: <>속도 X<br />(mm/s)</>,
    VY: <>속도 Y<br />(mm/s)</>,
    VZ: <>속도 Z<br />(mm/s)</>,
    WX: <>각속도 X<br />(rad/s)</>,
    WY: <>각속도 Y<br />(rad/s)</>,
    WZ: <>각속도 Z<br />(rad/s)</>,
  };

  const handleUpload = async (info: any) => {
    const { fileList } = info;
    const formData = new FormData();

    fileList.forEach((file: any) => {
      if (file.originFileObj) {
        formData.append('files', file.originFileObj);
      }
    });

    const username = localStorage.getItem('username') || 'default_user';
    formData.append('user', username);

    try {
      setLoading(true);

      const res = await api.post(
        '/api/upload_lsdyna_files',
        formData,
        {
          headers: { 'Content-Type': 'multipart/form-data' },
        }
      );

      if (res.data.success) {
        const shortFilename = (full: string) => {
          const idx = full.indexOf("DA_");
          if (idx === -1) return full;
          return full.substring(0, idx - 1);
        };

        const flatData = res.data.data.map((item: any, i: number) => ({
          "Short File Name": shortFilename(item.filename),
          Number: item.parameters?.Number,
          ...item.parameters,
          __originalFile: fileList[i]?.originFileObj, // 🔑 파일 객체 저장
        }));

        const allKeys = new Set(
          flatData.flatMap((obj: Record<string, any>) => Object.keys(obj))
        );

        const dynamicColumns = Array.from(allKeys as Set<string>).map((key) => ({
          title: columnNameMap[key] || key,
          dataIndex: key,
          key,
        }));

        setColumns(dynamicColumns);
        setData(flatData);
        message.success("업로드 성공!");
      }
    } catch (err) {
      console.error(err);
      message.error('업로드 실패');
    } finally {
      setLoading(false);
    }
  };

  const handleGoToAutoSubmit = () => {
    if (data.length === 0) {
      message.warning('제출할 파일이 없습니다.');
      return;
    }

    const jobConfigs = data.map((row: any) => {
      const file = row.__originalFile;
      return {
        file,
        filename: file.name,
        cores: 32,
        precision: 'Double',
        version: 'R15',
        mode: 'MPP',
      };
    });

    navigate('/auto-submit-lsdyna', {
      state: { jobConfigs },
    });
  };

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>📱 전각도 낙하 시뮬레이션</Title>
        <p>다양한 각도의 낙하 조건을 포함한 LS-DYNA 케이스 파일(.k)을 업로드하세요.</p>

        <Spin spinning={loading} tip="파일 업로드 및 파싱 중입니다...">
          <Dragger
            multiple
            customRequest={() => {}}
            beforeUpload={() => false}
            onChange={handleUpload}
          >
            <p className="ant-upload-drag-icon">
              <InboxOutlined />
            </p>
            <p className="ant-upload-text">
              .k 파일을 이곳에 드래그하거나 클릭하여 업로드하세요
            </p>
            <p className="ant-upload-hint">
              파일명은 반드시 DA_ 키워드를 포함해야 합니다.
            </p>
          </Dragger>

          <Table
            style={{ marginTop: '2rem' }}
            dataSource={data}
            columns={columns}
            rowKey="Short File Name"
            scroll={{ x: 'max-content' }}
          />

          {data.length > 0 && (
            <div style={{ textAlign: 'right', marginTop: '1rem' }}>
              <Button type="primary" onClick={handleGoToAutoSubmit}>
                자동 제출로 이동
              </Button>
            </div>
          )}
        </Spin>
      </div>
    </BaseLayout>
  );
};

export default FullAngleDrop;
