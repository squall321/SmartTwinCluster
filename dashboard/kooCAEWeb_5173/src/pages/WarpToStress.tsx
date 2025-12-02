import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider, message } from 'antd';

import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import PartWarpageTable from '../components/shared/PartWarpageTable';
import WarpVisualizerComponent from '../components/WarpVisualizerComponent';

import { ParsedPart } from '../types/parsedPart';

const { Title, Paragraph, Text } = Typography;

type WarpageInfo = {
  rawData: number[][]; // 행렬
  xLength: number;
  yLength: number;
  scaleFactor: number;
};

const WarpToStressPage: React.FC = () => {
  const [kFileName, setKFileName] = useState<string>('uploaded_file.k');
  const [allPartInfos, setAllPartInfos] = useState<ParsedPart[]>([]);
  const [includePartIds, setIncludePartIds] = useState<ParsedPart[]>([]);
  const [selectedPartId, setSelectedPartId] = useState<string | null>(null);
  const [partWarpageMap, setPartWarpageMap] = useState<Record<string, WarpageInfo>>({});

  const handlePartSelect = (part: ParsedPart) => {
    if (!includePartIds.find(p => p.id === part.id)) {
      setIncludePartIds(prev => [...prev, part]);
    }
  };

  const handlePartRemove = (id: string) => {
    setIncludePartIds(prev => prev.filter(p => p.id !== id));
  };

  const handleUploadDat = async (partId: string, file: File) => {
    try {
      const text = await file.text();
      const rows = text.trim().split('\n').map(line =>
        line.trim().split(/\t|\s+/).map(val => {
          const num = parseFloat(val);
          return isNaN(num) ? 9999 : num;
        })
      );
      setPartWarpageMap(prev => ({
        ...prev,
        [partId]: {
          rawData: rows,
          xLength: 1,
          yLength: 1,
          scaleFactor: 1
        }
      }));
      message.success(`Part ${partId}에 DAT 파일 업로드 완료`);
    } catch (e) {
      message.error('파일 파싱 실패');
    }
  };

  const handleParamChange = (partId: string, newParams: Partial<WarpageInfo>) => {
    setPartWarpageMap(prev => ({
      ...prev,
      [partId]: {
        ...prev[partId],
        ...newParams
      }
    }));
  };

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>📦 휨→응력 변환기</Title>
        <Paragraph>
          휨(Warpage) 데이터를 이용해 유한요소 해석에 사용할 초기 응력 상태를 생성하는 도구입니다.
          .dat 형식의 변위 데이터를 불러와 전체 크기와 스케일 팩터를 지정하면, 각 지점의 변형량을 기반으로 초기 응력 분포를 계산합니다.
          생성된 응력은 구조 해석 초기 조건으로 활용할 수 있으며, 성형 잔류응력이나 열변형 등의 영향을 반영하는 데 유용합니다.
        </Paragraph>

        <PartIdFinderUploader
          onParsed={(filename, parts) => {
            setKFileName(filename);
            setAllPartInfos(parts);
            setIncludePartIds([]);
            setPartWarpageMap({});
          }}
        />
        <Text type="secondary">{kFileName}</Text>

        <Divider />

        <PartSelector allParts={allPartInfos} onSelect={handlePartSelect} />

        <Divider />

        <PartWarpageTable
          parts={includePartIds}
          editable={true}
          onRemove={handlePartRemove}
          onUploadDat={handleUploadDat}
          onViewPart={setSelectedPartId}
          datStatusMap={Object.fromEntries(includePartIds.map(p => [p.id, !!partWarpageMap[p.id]]))}
          warpageMap={partWarpageMap}
          onParamChange={handleParamChange}
          title="포함할 Part 목록"
        />
      </div>

      <WarpVisualizerComponent
        warpageInfo={selectedPartId ? partWarpageMap[selectedPartId] ?? null : null}
      />
    </BaseLayout>
  );
};

export default WarpToStressPage;
