import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider } from 'antd';

import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import PartTable from '../components/shared/PartTable';
import ExportMeshModifierButton from '../components/shared/ExportMeshModifierButtonProps';

import { ParsedPart } from '../types/parsedPart';
import { generateRigidOptionFile, generateRigidOptionText } from '../components/shared/utils';

const { Title, Paragraph, Text } = Typography;

const ElasticToRigid: React.FC = () => {
  const [kFile, setKFile] = useState<File | null>(null);  // 🔹추가
  const [kFileName, setKFileName] = useState<string>('uploaded_file.k');
  const [allPartInfos, setAllPartInfos] = useState<ParsedPart[]>([]);
  const [excludePartIds, setExcludePartIds] = useState<ParsedPart[]>([]);

  const handlePartSelect = (part: ParsedPart) => {
    if (!excludePartIds.find(p => p.id === part.id)) {
      setExcludePartIds(prev => [...prev, part]);
    }
  };

  const handlePartRemove = (id: string) => {
    setExcludePartIds(prev => prev.filter(p => p.id !== id));
  };

  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>Elastic to Rigid 변환 설정</Title>
        <Paragraph>
          LS-DYNA K 파일을 업로드하여 파트를 분석하고, 강체로 전환하지 않을 파트를 선택하세요.<br />
          이후 옵션파일을 다운로드하여 해석 입력 파일에 사용할 수 있습니다.
        </Paragraph>

        {/* 파일 업로더 */}
        <PartIdFinderUploader
          onParsed={(filename, parts,file) => {
            setKFileName(filename);
            setAllPartInfos(parts);
            setExcludePartIds([]);
            setKFile(file ?? null);
          }}
        />
        <Text type="secondary">{kFileName}</Text>

        <Divider />

        {/* 제외할 파트 선택 */}
        <Title level={4}>제외할 Part 선택</Title>
        <PartSelector allParts={allPartInfos} onSelect={handlePartSelect} />

        {/* 제외된 Part 리스트 테이블 */}
        <PartTable
          parts={excludePartIds}
          editable={true}
          onRemove={handlePartRemove}
          title="강체로 변환하지 않을 파트 목록"
        />
        {/* 다운로드 버튼 */}
        <div style={{ marginTop: 32, textAlign: 'center' }}>
        <ExportMeshModifierButton
            kFile={kFile}
            kFileName={kFileName}
            optionFileGenerator={() => generateRigidOptionFile(kFileName, allPartInfos, excludePartIds)}
            optionFileName="elasticToRigidOption.txt"
            solver="MeshModifier"
            mode="ElasticToRigid"
            buttonLabel="🔁 해석 실행 (Mesh Modifier)"
          />
        </div>
      </div>
    </BaseLayout>
  );
};

export default ElasticToRigid;
