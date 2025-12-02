import React, { useState, useEffect, useRef } from 'react';
import { api } from '../api/axiosClient';
import { Spin, Button, message, Divider, Typography, Upload } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import type { UploadFile } from 'antd/es/upload/interface';
import { useLocation } from 'react-router-dom';

const { Dragger } = Upload;
const { Title, Paragraph } = Typography;

interface StreamRunnerProps {
  solver: string | null;
  mode: string | null;
  txtFiles?: File[];
  optFiles?: File[];
  autoSubmit?: boolean;
}

const StreamRunner: React.FC<StreamRunnerProps> = (props) => {
  const location = useLocation();
  const state = location.state as Partial<StreamRunnerProps> | undefined;

  // 📌 props > location.state > default
  const solver = props.solver ?? state?.solver ?? null;
  const mode = props.mode ?? state?.mode ?? null;
  const autoSubmit = props.autoSubmit ?? state?.autoSubmit ?? false;
  const [txtFiles, setTxtFiles] = useState<File[]>(props.txtFiles ?? state?.txtFiles ?? []);
  const [optFiles, setOptFiles] = useState<File[]>(props.optFiles ?? state?.optFiles ?? []);
  const [logs, setLogs] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const [isSubmitted, setIsSubmitted] = useState(false);
  const hasSubmittedRef = useRef(false);

  const username = localStorage.getItem('username') || 'default_user';

  const handleSubmit = async () => {
    if (txtFiles.length === 0) {
      message.warning('TXT 파일을 업로드해주세요.');
      return;
    }

    setDownloadUrl(null);
    const formData = new FormData();
    formData.append("user", username);
    formData.append("cmd_line", txtFiles.map(file => file.name).join(","));
    if (mode) formData.append("mode", mode);

    txtFiles.forEach(file => formData.append("files_txt", file));
    optFiles.forEach(file => formData.append("files_opt", file));

    let url = "/api/proxy/automation/app/meshmodifier/stream";
    if (solver === "AutomatedModeller") {
      url = "/api/proxy/automation/app/automatedmodeller/stream";
    }

    setLogs("▶️ 실행 시작...\n");
    setLoading(true);

    try {
      const response = await api.post(url, formData, {
        responseType: "text",
        headers: { 'Content-Type': 'multipart/form-data' },
      });

      const parsed = JSON.parse(response.data);
      const allOutput = parsed.results.map((res: any) => {
        const output = (res.stderr && res.stderr.trim() !== "" ? res.stderr : res.stdout).replace(/\r\n/g, "\n");
        return `📄 ${res.file}\n${output}`;
      }).join("\n\n");

      setLogs(prev => prev + allOutput + "\n✅ 실행 완료");

      const firstResult = parsed.results[0];
      if (firstResult?.download_url) {        
        setDownloadUrl(`${api.defaults.baseURL}${firstResult.download_url}`);
      }

    } catch (err: any) {
      console.error(err);
      setLogs(`❌ 오류 발생: ${err.message}`);
      message.error("실행 중 오류가 발생했습니다.");
    } finally {
      setLoading(false);
    }
  };

  const handleDownload = async () => {
    if (!downloadUrl) {
      message.error("다운로드 URL이 없습니다.");
      return; 
    }

    try {
      const response = await api.get(downloadUrl, { responseType: 'blob' });
      const blob = new Blob([response.data], { type: 'application/zip' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'results.zip';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error(error);
      message.error('다운로드 실패');
    }
  };

  // ✅ autoSubmit 트리거

  useEffect(() => {
    if (
      autoSubmit &&
      txtFiles.length > 0 &&
      !hasSubmittedRef.current
    ) {
      hasSubmittedRef.current = true;
      console.log("💥 handleSubmit 실행");
      handleSubmit();
    }
  }, [autoSubmit, txtFiles, optFiles]);
  return (
    <Spin spinning={loading} tip="업로드 및 실행 중입니다...">
      <div style={{ padding: '20px' }}>
        <Title level={3}>Stream Runner</Title>
        <Paragraph>TXT 파일과 옵션 파일을 업로드하고 해석을 실행한 후 결과를 확인하세요.</Paragraph>

        <h4>📄 TXT 파일 드래그</h4>
        <Dragger
          name="files_txt"
          multiple
          fileList={txtFiles.map(file => ({
            uid: file.name,
            name: file.name,
            status: 'done',
          }))}
          beforeUpload={() => false}
          customRequest={() => {}}
          onChange={(info) => {
            const fileList = info.fileList.map(f => f.originFileObj).filter(Boolean) as File[];
            setTxtFiles(fileList);
          }}
          onRemove={(file) => {
            setTxtFiles(prev => prev.filter(f => f.name !== file.name));
            return true;
          }}
          style={{ marginBottom: '20px' }}
        >
          <p className="ant-upload-drag-icon">📄</p>
          <p className="ant-upload-text">여기로 TXT 파일을 드래그 하세요</p>
          <p className="ant-upload-hint">여러 파일을 동시에 업로드할 수 있습니다.</p>
        </Dragger>

        <h4>⚙️ 옵션 파일 드래그</h4>
        <Dragger
          name="files_opt"
          multiple
          fileList={optFiles.map(file => ({
            uid: file.name,
            name: file.name,
            status: 'done',
          }))}
          beforeUpload={() => false}
          customRequest={() => {}}
          onChange={(info) => {
            const fileList = info.fileList.map(f => f.originFileObj).filter(Boolean) as File[];
            setOptFiles(fileList);
          }}
          onRemove={(file) => {
            setOptFiles(prev => prev.filter(f => f.name !== file.name));
            return true;
          }}
          style={{ marginBottom: '20px' }}
        >
          <p className="ant-upload-drag-icon">⚙️</p>
          <p className="ant-upload-text">여기로 옵션 파일을 드래그 하세요</p>
          <p className="ant-upload-hint">여러 옵션 파일을 동시에 업로드할 수 있습니다.</p>
        </Dragger>

        <Button type="primary" onClick={handleSubmit} style={{ marginBottom: '20px' }}>
          🚀 Submit
        </Button>

        <Divider />

        <Title level={4}>📡 실행 결과</Title>
        <pre style={{
          backgroundColor: '#111',
          color: '#0f0',
          padding: '10px',
          height: '300px',
          overflow: 'auto',
          borderRadius: '5px',
          whiteSpace: 'pre-wrap'
        }}>
          {logs}
        </pre>

        {downloadUrl && (
          <Button type="primary" icon={<DownloadOutlined />} onClick={handleDownload}>
            생성된 파일 ZIP 다운로드
          </Button>
        )}
      </div>
    </Spin>
  );
};

export default StreamRunner;
