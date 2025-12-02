import React, { useEffect, useState } from 'react';
import { Upload, Typography, message } from 'antd';
import type { UploadFile } from 'antd/es/upload/interface';
import { InboxOutlined } from '@ant-design/icons';
import LsdynaOptionTable, { LsdynaJobConfig } from './LsdynaOptionTable';

const { Dragger } = Upload;
const { Title } = Typography;

interface LsdynaFileUploaderProps {
  onDataUpdate?: (data: LsdynaJobConfig[]) => void;
  initialData?: LsdynaJobConfig[];
}

const LsdynaFileUploader: React.FC<LsdynaFileUploaderProps> = ({ onDataUpdate, initialData }) => {
  const [data, setData] = useState<LsdynaJobConfig[]>([]);

  // ✅ 초기 데이터 반영
  useEffect(() => {
    if (initialData && initialData.length > 0) {
      setData(initialData);
      onDataUpdate?.(initialData);
    }
  }, [initialData, onDataUpdate]);

  // ✅ 파일 업로드 처리
  const handleFileDrop = (info: { fileList: UploadFile[] }) => {
    const files = info.fileList
      .filter((f) => f.originFileObj && f.name.endsWith('.k'))
      .map((f) => f.originFileObj as File);

    if (files.length === 0) {
      message.warning('확장자가 .k인 파일만 업로드할 수 있습니다.');
      return;
    }

    const existingFilenames = new Set(data.map((d) => d.filename));

    const newData: LsdynaJobConfig[] = files
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
  const updateAll = <K extends keyof LsdynaJobConfig>(field: K, value: LsdynaJobConfig[K]) => {
    const updated = data.map((row) => ({ ...row, [field]: value }));
    setData(updated);
    onDataUpdate?.(updated);
  };

  // ✅ 개별 행 수정
  const updateRow = <K extends keyof LsdynaJobConfig>(
    key: string,
    field: K,
    value: LsdynaJobConfig[K]
  ) => {
    const updated = data.map((row) =>
      row.key === key ? { ...row, [field]: value } : row
    );
    setData(updated);
    onDataUpdate?.(updated);
  };

  // ✅ 행 삭제
  const deleteRow = (key: string) => {
    const updated = data.filter((row) => row.key !== key);
    setData(updated);
    onDataUpdate?.(updated);
  };

  return (
    <>
      <Title level={4}>📂 LS-DYNA K 파일 업로드</Title>
      <Dragger
        multiple
        beforeUpload={() => false}
        onChange={handleFileDrop}
        accept=".k"
        style={{ marginBottom: 24 }}
        showUploadList={false}
      >
        <p className="ant-upload-drag-icon">
          <InboxOutlined />
        </p>
        <p className="ant-upload-text">
          여기에 K 파일들을 드래그하거나 클릭하여 업로드하세요
        </p>
      </Dragger>

      <LsdynaOptionTable
        data={data}
        onUpdateAll={updateAll}
        onUpdateRow={updateRow}
        onDeleteRow={deleteRow}
      />
    </>
  );
};

export default LsdynaFileUploader;
