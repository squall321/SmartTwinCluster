import React, { useState } from 'react';
import { Typography, Divider, Button, message } from 'antd';

import PartIdFinderUploader from '../components/uploader/PartIDFindwithBDUploader';
import PartSelector from '../components/shared/PartSelector';
import GLTFViewerComponent from './GLTFViewerComponent';
import GLBDynamicViewerComponent from './GLBDynamicViewerComponent';

import { ParsedPart } from '../types/parsedPart';
import { api } from '../api/axiosClient';

const { Title, Paragraph, Text } = Typography;

interface DynaFilePartVisualizerProps {
  onReady?: (info: {
    kfile: File;
    partId: string;
    glbFile: File;
  }) => void;
}

const DynaFilePartVisualizerGLBComponent: React.FC<DynaFilePartVisualizerProps> = ({ onReady }) => {
  const [kFileName, setKFileName] = useState<string>('업로드된 파일 없음');
  const [allParts, setAllParts] = useState<ParsedPart[]>([]);
  const [selectedPart, setSelectedPart] = useState<ParsedPart | null>(null);
  const [uploadedFile, setUploadedFile] = useState<File | null>(null);
  const [glbFile, setGlbFile] = useState<File | null>(null);
  const username = localStorage.getItem('username') || 'default_user';

  const handlePartSelect = (part: ParsedPart) => {
    setSelectedPart(part);
  };

  const handleConvertToGlb = async () => {
    if (!uploadedFile || !selectedPart) {
      message.error('파일과 Part ID를 모두 선택해주세요.');
      return;
    }

    const formData = new FormData();
    formData.append('file', uploadedFile);
    formData.append('partid', selectedPart.id);
    formData.append('user', username);

    try {
      message.info('GLB 변환 중...');
      console.log(formData.get('file'));
      console.log(formData.get('partid'));
      console.log(formData.get('user'));
      const response = await api.post(
        '/api/convert_kfile_to_glb', // ✅ API 엔드포인트
        formData,
        {
          headers: {
            'Content-Type': 'multipart/form-data',
          },
          responseType: 'blob',
        }
      );

      // Blob → File 객체로 변환
      const glbBlob = new Blob([response.data], { type: 'model/gltf-binary' });
      const glbFilename = `${kFileName.replace(/\.[^/.]+$/, '')}_${selectedPart.id}.glb`;
      const fileObj = new File([glbBlob], glbFilename, { type: 'model/gltf-binary' });

      setGlbFile(fileObj);
      message.success('GLB 변환 성공');

      if (onReady) {
        onReady({
          kfile: uploadedFile,
          partId: selectedPart.id,
          glbFile: fileObj,
        });
      }
    } catch (err: any) {
      console.error('GLB 변환 오류:', err);
      const errorText = err.response?.data?.error || err.message || '알 수 없는 오류';
      message.error(`GLB 변환 실패: ${errorText}`);
    }
  };

  return (
    <div style={{ padding: 24 }}>
      <Title level={3}>Dyna K파일 파트 선택기 + GLB 시각화</Title>
      <Paragraph>
        LS-DYNA의 K 파일을 업로드하고 포함된 Part를 선택한 뒤, GLB 형상으로 시각화하여 파트를 확인합니다.
      </Paragraph>

      <PartIdFinderUploader
        onParsed={(filename, parts, file) => {
          setKFileName(filename);
          setAllParts(parts);
          setUploadedFile(file || null);
          setSelectedPart(null);
          setGlbFile(null);
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
        onClick={handleConvertToGlb}
        disabled={!uploadedFile || !selectedPart}
      >
        Part 형상 확인하기 (GLB)
      </Button>

      {glbFile && (
        <>
          <Divider />
          <Title level={4}>🧊 GLB Viewer</Title>
          <GLBDynamicViewerComponent file={glbFile} autoScale={false} />

          <div style={{ marginTop: 16, display: 'flex', gap: '1rem' }}>
            {/* GLB 다운로드 */}
            <Button type="default">
              <a
                href={URL.createObjectURL(glbFile)}
                download={glbFile.name}
                style={{ color: 'inherit', textDecoration: 'none' }}
              >
                GLB 파일 다운로드
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

export default DynaFilePartVisualizerGLBComponent;
