import React, { useState } from 'react';
import { Typography, Divider, Button, message } from 'antd';

import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import StlViewerComponent from './StlViewerComponent';

import { ParsedPart } from '../types/parsedPart';
import { api } from '../api/axiosClient';

const { Title, Paragraph, Text } = Typography;

interface DynaFilePartVisualizerProps {
  onReady?: (info: {
    kfile: File;
    partId: string;
    stlUrl: string;
  }) => void;
}

const DynaFilePartVisualizerComponent: React.FC<DynaFilePartVisualizerProps> = ({ onReady }) => {
  const [kFileName, setKFileName] = useState<string>('업로드된 파일 없음');
  const [allParts, setAllParts] = useState<ParsedPart[]>([]);
  const [selectedPart, setSelectedPart] = useState<ParsedPart | null>(null);
  const [uploadedFile, setUploadedFile] = useState<File | null>(null);
  const [stlUrl, setStlUrl] = useState<string | null>(null);
  const username = localStorage.getItem('username') || 'default_user';
  const handlePartSelect = (part: ParsedPart) => {
    setSelectedPart(part);
  };

  const handleConvertToStl = async () => {
    if (!uploadedFile || !selectedPart) {
      message.error('파일과 Part ID를 모두 선택해주세요.');
      return;
    }

    const formData = new FormData();
    formData.append('file', uploadedFile);
    formData.append('partid', selectedPart.id);
    formData.append('user', username);

    try {
      message.info('STL 변환 중...');
      const response = await api.post(
        '/api/convert_kfile_to_stl',
        formData,
        {
          headers: {
            'Content-Type': 'multipart/form-data',
          },
          responseType: 'blob',
        }
      );

      const blob = new Blob([response.data], { type: 'application/sla' });
      const url = URL.createObjectURL(blob);
      setStlUrl(url);
      message.success('STL 변환 성공');

      // ✅ 외부로 데이터 전달
      if (onReady) {
        onReady({
          kfile: uploadedFile,
          partId: selectedPart.id,
          stlUrl: url,
        });
      }
    } catch (err: any) {
      console.error('STL 변환 오류:', err);
      const errorText = err.response?.data?.error || err.message || '알 수 없는 오류';
      message.error(`STL 변환 실패: ${errorText}`);
    }
  };

  return (
    <div style={{ padding: 24 }}>
      <Title level={3}>Dyna K파일 파트 선택기 + STL 시각화</Title>
      <Paragraph>
        LS-DYNA의 K 파일을 업로드하고 포함된 Part를 선택한 뒤, 형상을 시각화하여 파트를 확인합니다.
      </Paragraph>

      <PartIdFinderUploader
        onParsed={(filename, parts, file) => {
          setKFileName(filename);
          setAllParts(parts);
          setUploadedFile(file || null);
          setSelectedPart(null);
          setStlUrl(null);
        }}
      />
      <Text type="secondary">📂 {kFileName}</Text>

      <Divider />

      <Title level={4}>Part 선택</Title>
      <PartSelector allParts={allParts} onSelect={handlePartSelect} />

      {selectedPart && (
        <Paragraph style={{ marginTop: 16 }}>
          선택된 Part: <Text code>{selectedPart.id}</Text>
          {selectedPart.name && <span> – {selectedPart.name}</span>}
        </Paragraph>
      )}

      <Button
        type="primary"
        style={{ marginTop: 16 }}
        onClick={handleConvertToStl}
        disabled={!uploadedFile || !selectedPart}
      >
        Part 형상 확인하기
      </Button>

      {stlUrl && (
  <>
    <Divider />
    <Title level={4}>🧊 STL Viewer</Title>
    <StlViewerComponent url={stlUrl} />

    <div style={{ marginTop: 16, display: 'flex', gap: '1rem' }}>
        {/* STL 다운로드 */}
        <Button type="default">
            <a
            href={stlUrl}
            download={`${kFileName.replace(/\.[^/.]+$/, '')}_${selectedPart?.id}.stl`}
            style={{ color: 'inherit', textDecoration: 'none' }}
            >
            STL 파일 다운로드
            </a>
        </Button>

        {/* K파일 다운로드 */}
        {uploadedFile && (
            <Button type="default">
            <a
                href={URL.createObjectURL(uploadedFile)}
                download={kFileName}
                style={{ color: 'inherit', textDecoration: 'none' }}
            >
                원본 K파일 다운로드
            </a>
            </Button>
        )}
        </div>
    </>
    )}

    </div>
  );
};

export default DynaFilePartVisualizerComponent;
