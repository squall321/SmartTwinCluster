import React, { useState, useMemo, useEffect } from "react";

import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider, Input, Select, Button, Space, Checkbox, Tag, InputNumber, Table } from "antd";

import DotIcon from '../Icons/DotIcon';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import {ImpactAnalysisPart, ParsedPart } from '../types/parsedPart';   
import PartDropWeightImpactTable from '../components/shared/PartDropWeightImpactTable';

import { generateDropWeightImpactTestbyPartsOptionFile } from "../components/shared/utils";
import ExportMeshModifierButton from "@components/shared/ExportMeshModifierButtonProps";
const { Title, Paragraph, Text } = Typography;
const { Option } = Select;


const cellStyle: React.CSSProperties = {
    border: '1px solid #ddd',
    padding: 8,
    textAlign: 'center',
  };
  
// 공통 옵션
const dotPatterns: ImpactAnalysisPart['impactPattern'][] = [
  '1x1', '1x2', '2x1', '2x2', '1x3', '3x1', '3x3'
];
const heightOptions = Array.from({ length: 10 }, (_, i) => 50 * (i + 1)); // 50~500

const AllPointsDropWeightImpactGenerator = () => {
    const [kFileName, setKFileName] = useState<string>('');
    const [allPartInfos, setAllPartInfos] = useState<ImpactAnalysisPart[]>([]);
    const [selectedParts, setSelectedParts] = useState<ImpactAnalysisPart[]>([]);
    const [layerGroups, setLayerGroups] = useState<any[]>([]);
    const [midMap, setMidMap] = useState<Map<string, string>>(new Map());
    const [uploadedKFile, setUploadedKFile] = useState<File | null>(null);

    // ✅ 추가: 키워드 기반 일괄 적용 상태
    const [bulkKeyword, setBulkKeyword] = useState<string>('');
    const [bulkPattern, setBulkPattern] = useState<ImpactAnalysisPart['impactPattern']>('3x3');
    const [bulkHeight, setBulkHeight] = useState<number>(200);
    const [includeNotSelected, setIncludeNotSelected] = useState<boolean>(true); // 선택 안 된 파트도 추가할지 여부
   

    const [densityCylinder, setDensityCylinder] = useState<number>(7.800e-9);
    const [youngModulusCylinder, setYoungModulusCylinder] = useState<number>(210e3);
    const [poissonRatioCylinder, setPoissonRatioCylinder] = useState<number>(0.35);

    const [youngModulusCylinderFront, setYoungModulusCylinderFront] = useState<number>(100);
    const [densityCylinderFront, setDensityCylinderFront] = useState<number>(0.900e-9);
    const [poissonRatioCylinderFront, setPoissonRatioCylinderFront] = useState<number>(0.499);

    const [densitySphere, setDensitySphere] = useState<number>(7.800e-9);
    const [youngModulusSphere, setYoungModulusSphere] = useState<number>(210e3);
    const [poissonRatioSphere, setPoissonRatioSphere] = useState<number>(0.35);

    const [densityWall, setDensityWall] = useState<number>(7.800e-9);
    const [youngModulusWall, setYoungModulusWall] = useState<number>(210e3);
    const [poissonRatioWall, setPoissonRatioWall] = useState<number>(0.35);

    const [offsetDistance, setOffsetDistance] = useState<number>(0.05);
    const [meshSize, setMeshSize] = useState<number>(1);

    const [tFinal, setTFinal] = useState<number>(0.005);
    const [dt, setDt] = useState<number>(1e-6);


    const [velocityVector, setVelocityVector] = useState<[number, number, number]>([0, 0, 0]);

    const [impactorType, setImpactorType] = useState<'cylinder' | 'sphere'>('cylinder');
    const [impactorDiameter, setImpactorDiameter] = useState<number>(8);
    const [impactorWeight, setImpactorWeight] = useState<number>(200);


    const [frontDiameter, setFrontDiameter] = useState<number>(16);  // radius1
    const [midDiameter, setMidDiameter] = useState<number>(20);      // radius2
    const [backDiameter, setBackDiameter] = useState<number>(24);    // radius3
    const [frontHeight, setFrontHeight] = useState<number>(10); // height1
    const [backHeight, setBackHeight] = useState<number>(40);   // height2

    const materialTableData = [
        {
          key: 'impactor',
          label: 'Impactor Cylinder',
          enabledFor: ['cylinder'],
          young: youngModulusCylinder,
          setYoung: setYoungModulusCylinder,
          poisson: poissonRatioCylinder,
          setPoisson: setPoissonRatioCylinder,
          density: densityCylinder,
          setDensity: setDensityCylinder,
        },
        {
          key: 'front',
          label: 'Impactor Front',
          enabledFor: ['cylinder'],
          young: youngModulusCylinderFront,
          setYoung: setYoungModulusCylinderFront,
          poisson: poissonRatioCylinderFront,
          setPoisson: setPoissonRatioCylinderFront,
          density: densityCylinderFront,
          setDensity: setDensityCylinderFront,
        },
        {
          key: 'sphere',
          label: 'Impactor Sphere',
          enabledFor: ['sphere'],
          young: youngModulusSphere,
          setYoung: setYoungModulusSphere,
          poisson: poissonRatioSphere,
          setPoisson: setPoissonRatioSphere,
          density: densitySphere,
          setDensity: setDensitySphere,
        },
        {
          key: 'wall',
          label: 'Wall',
          enabledFor: ['cylinder', 'sphere'],
          young: youngModulusWall,
          setYoung: setYoungModulusWall,
          poisson: poissonRatioWall,
          setPoisson: setPoissonRatioWall,
          density: densityWall,
          setDensity: setDensityWall,
        },
      ];

    const updateVector = (index: number, value: number) => {
    const newVec = [...velocityVector] as [number, number, number];
    newVec[index] = value;
    setVelocityVector(newVec);
    };


    

  const handlePartSelect = (part: ParsedPart) => {
    const impactPart: ImpactAnalysisPart = {
      ...part,
      impactPattern: '3x3',
      impactHeight: 200,
      impactVelocityVector: velocityVector,
      impactorType: 'sphere',
      impactorDiameter: 10,
      impactorWeight: 100
    };
    const index = selectedParts.findIndex((p) => p.id === part.id);
    let updatedParts: ImpactAnalysisPart[];
    if (index >= 0) {
      updatedParts = [...selectedParts];
      updatedParts[index] = impactPart;
    } else {
      updatedParts = [...selectedParts, impactPart];
    }
    setSelectedParts(updatedParts);
  };

  const handlePartRemove = (id: string) => {
    setSelectedParts(selectedParts.filter((p) => p.id !== id));
  };

  const handlePatternChange = (id: string, pattern: ImpactAnalysisPart['impactPattern']) => {
    const updated = selectedParts.map((p) =>
      p.id === id ? { ...p, impactPattern: pattern } : p
    );
    setSelectedParts(updated);
  };

  const handleHeightChange = (id: string, height: number) => {
    const updated = selectedParts.map((p) =>
      p.id === id ? { ...p, impactHeight: height } : p
    );
    setSelectedParts(updated);
  };

  // ✅ 추가: 키워드에 매칭되는 파트 미리 계산 (미리보기용)
  const matchedParts = useMemo(() => {
    const kw = bulkKeyword.trim().toLowerCase();
    if (!kw) return [];
    return allPartInfos.filter(p =>
      p.name.toLowerCase().includes(kw) || p.id.toLowerCase().includes(kw)
    );
  }, [bulkKeyword, allPartInfos]);

  // ✅ 추가: 키워드 일괄 적용 버튼
  const handleBulkApply = () => {
    const kw = bulkKeyword.trim().toLowerCase();
    if (!kw) return;
  
    const matched = matchedParts;
  
    const map = new Map(selectedParts.map(p => [p.id, { ...p }]));
  
    matched.forEach(p => {
      if (map.has(p.id) || includeNotSelected) {
        const base = map.get(p.id) ?? { ...p };
        map.set(p.id, {
          ...base,
          impactPattern: bulkPattern,
          impactHeight: bulkHeight,
          impactVelocityVector: velocityVector,
        });
      }
    });
  
    setSelectedParts(Array.from(map.values()));
  };

  const handleVelocityVectorChange = (id: string, vector: number[]) => {
    const updated = selectedParts.map((p) =>
      p.id === id ? { ...p, impactVelocityVector: vector } : p
    );
    setSelectedParts(updated);
  };
  

  const handleImpactorChange = (
    id: string,
    field: 'impactorType' | 'impactorDiameter' | 'impactorWeight',
    value: any
  ) => {
    const updated = selectedParts.map((p) =>
      p.id === id ? { ...p, [field]: value } : p
    );
    setSelectedParts(updated);
  };
  const partIDs = selectedParts.map(p => Number(p.id)); // 또는 적절히 파싱
  const initialVelocityXList = partIDs.map(() => velocityVector[0]);
  const initialVelocityYList = partIDs.map(() => velocityVector[1]);
  const initialVelocityZList = partIDs.map(() => velocityVector[2]);
  const locationModes = selectedParts.map(p => p.impactPattern);
  const heightList = selectedParts.map(p => p.impactHeight);

  useEffect(() => {
    if (impactorType === 'cylinder') {
      const mass = calculateCylinderWithFilletMass(
        frontDiameter,
        midDiameter,
        backDiameter,
        frontHeight,
        backHeight,
        densityCylinderFront,
        densityCylinder
      );
      setImpactorWeight(Math.round(mass*1000000)/1000000);
    }
  }, [impactorType, frontDiameter, midDiameter, backDiameter, frontHeight, backHeight, densityCylinder]);

  
  useEffect(() => {
    if (impactorType === 'sphere') {
      const mass = calculateSphereMass(impactorDiameter, densitySphere);
      setImpactorWeight(Math.round(mass));
    }
  }, [impactorType, impactorDiameter, densitySphere]);

  
  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{
        padding: 24,
        backgroundColor: '#fff',
        minHeight: '100vh',
        borderRadius: '24px',
      }}>
        <Title level={3}>전위치 부분 충격 시뮬레이션</Title>
        <Paragraph>
          선택된 파트 혹은 특정 키워드를 포함하는 모든 파트에 대한 충격 시뮬레이션을 자동화하여 실행합니다.
        </Paragraph>

        <PartIdFinderUploader
          onParsed={(filename, parts, file) => {
            setKFileName(filename);
            setAllPartInfos(parts as ImpactAnalysisPart[]);
            setSelectedParts([]);
            setLayerGroups([]);
            setMidMap(new Map());
            setUploadedKFile(file ?? null);
          }}
        />
        <Text type="secondary">{kFileName}</Text>
        <Divider />

        <Title level={4}>Part 선택</Title>
        <PartSelector allParts={allPartInfos as ParsedPart[]} onSelect={handlePartSelect} />

        <Divider />

        {/* ✅ 키워드 일괄 적용 UI 블록 */}
        <Title level={5}>키워드로 일괄 옵션 적용</Title>
        <Space wrap>
          <Input
            placeholder="키워드 (id 또는 name에 포함)"
            value={bulkKeyword}
            onChange={(e) => setBulkKeyword(e.target.value)}
            style={{ width: 200 }}
          />
          <Select
            value={bulkPattern}
            onChange={(v) => setBulkPattern(v)}
            style={{ width: 100 }}
          >
            {dotPatterns.map(p => <Option key={p} value={p}>{p}</Option>)}
          </Select>
          <Select
            value={bulkHeight}
            onChange={(v) => setBulkHeight(v)}
            style={{ width: 120 }}
            options={heightOptions.map(h => ({ value: h, label: `${h} mm` }))}
          />
        
          <InputNumber value={velocityVector[0]} onChange={(v) => updateVector(0, v ?? 0)} style={{ width: 100 }} />
          <InputNumber value={velocityVector[1]} onChange={(v) => updateVector(1, v ?? 0)} style={{ width: 100 }} />
          <InputNumber value={velocityVector[2]} onChange={(v) => updateVector(2, v ?? 0)} style={{ width: 100 }} />



           

          <Checkbox
            checked={includeNotSelected}
            onChange={(e) => setIncludeNotSelected(e.target.checked)}
          >
            선택되지 않은 파트도 포함
          </Checkbox>




          <Button type="primary" onClick={handleBulkApply}>
            일괄 적용
          </Button>

        </Space>

        {/* 매칭 결과 간단 표시 */}
        {bulkKeyword && (
          <div style={{ marginTop: 8 }}>
            <Text type="secondary">
              키워드 "<b>{bulkKeyword}</b>" 로 매칭된 파트: <Tag color="blue">{matchedParts.length}</Tag>개
            </Text>
          </div>
        )}

        <Divider />

        <PartDropWeightImpactTable
          parts={selectedParts}
          onRemove={handlePartRemove}
          onPatternChange={handlePatternChange}
          onHeightChange={handleHeightChange}
          onImpactorChange={handleImpactorChange}
          onVelocityVectorChange={handleVelocityVectorChange}
        />

            <Divider />

           

            {/* ⚙ 기타 시뮬레이션 옵션 */}
            <Divider orientation="left" orientationMargin="0">
                ⚙ 시뮬레이션 설정
            </Divider>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16 }}>
                <InputNumber
                addonBefore="tFinal (s)"
                value={tFinal}
                onChange={(v) => setTFinal(v ?? 0)}
                step={0.001}
                style={{ width: 220 }}
                />
                <InputNumber
                addonBefore="dt (s)"
                value={dt}
                onChange={(v) => setDt(v ?? 0)}
                step={1e-6}
                style={{ width: 220 }}
                />
                <InputNumber
                addonBefore="Mesh Size (mm)"
                value={meshSize}
                onChange={(v) => setMeshSize(v ?? 0)}
                style={{ width: 220 }}
                />
                <InputNumber
                addonBefore="Offset Distance (mm)"
                value={offsetDistance}
                onChange={(v) => setOffsetDistance(v ?? 0)}
                step={0.01}
                style={{ width: 220 }}
                />

            </div>

            <Divider />

            <Title level={3}>시뮬레이션 전역 옵션 - 재료 물성</Title>
            <div style={{ display: 'flex', gap: 16, alignItems: 'center', marginBottom: 16 }}>
            <Text strong>Impactor Type 선택:</Text>
            <Select
                value={impactorType}
                onChange={setImpactorType}
                style={{ width: 200 }}
                options={[
                { value: 'cylinder', label: 'Cylinder' },
                { value: 'sphere', label: 'Sphere' }
                ]}
            />
            </div>
            <div style={{ overflowX: 'auto' }}>
            <table style={{ borderCollapse: 'collapse', width: '100%', minWidth: 900 }}>
                <thead>
                <tr>
                    <th style={cellStyle}>위치</th>
                    <th style={cellStyle}>Young's Modulus (MPa)</th>
                    <th style={cellStyle}>Poisson Ratio</th>
                    <th style={cellStyle}>Density (ton/mm³)</th>
                </tr>
                </thead>
                <tbody>
                    {materialTableData.map((row) => {
                        const isEnabled = row.enabledFor?.includes(impactorType) ?? true;
                        return (
                        <tr key={row.key}>
                            <td style={cellStyle}><strong>{row.label}</strong></td>
                            <td style={cellStyle}>
                            <InputNumber
                                value={row.young}
                                onChange={(v) => row.setYoung(v ?? 0)}
                                disabled={!isEnabled}
                                style={{ width: '100%' }}
                            />
                            </td>
                            <td style={cellStyle}>
                            <InputNumber
                                value={row.poisson}
                                min={0}
                                max={0.5}
                                step={0.001}
                                onChange={(v) => row.setPoisson(v ?? 0)}
                                disabled={!isEnabled}
                                style={{ width: '100%' }}
                            />
                            </td>
                            <td style={cellStyle}>
                            <InputNumber
                                value={row.density}
                                onChange={(v) => row.setDensity(v ?? 0)}
                                disabled={!isEnabled}
                                style={{ width: '100%' }}
                            />
                            </td>
                        </tr>
                        );
                    })}
                    </tbody>
            </table>
            </div>
                
            {impactorType === 'sphere' ? (
                <div style={{ display: 'flex', gap: 16, marginTop: 16 }}>
                <InputNumber
                    addonBefore="Impactor 직경 (mm)"
                    value={impactorDiameter}
                    onChange={(v) => setImpactorDiameter(v ?? 0)}
                    min={0}
                    style={{ width: 250 }}
                />
                <InputNumber
                    addonBefore="Impactor 질량 (g)"
                    value={impactorWeight}
                    disabled={true}
                    onChange={(v) => setImpactorWeight(v ?? 0)}
                    min={0}
                    style={{ width: 250 }}
                />
                </div>
            ) : (

                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, marginTop: 16 }}>
              
             
                    <InputNumber
                    addonBefore="Front Diameter (mm)"
                    value={frontDiameter}
                    onChange={(v) => setFrontDiameter(v ?? 0)}
                    min={0}
                    style={{ width: 220 }}
                    />
                    <InputNumber
                    addonBefore="Mid Diameter (mm)"
                    value={midDiameter}
                    onChange={(v) => setMidDiameter(v ?? 0)}
                    min={0}
                    style={{ width: 220 }}
                    />
                    <InputNumber
                    addonBefore="Back Diameter (mm)"
                    value={backDiameter}
                    onChange={(v) => setBackDiameter(v ?? 0)}
                    min={0}
                    style={{ width: 220 }}
                    />
              
                    <InputNumber
                    addonBefore="Front Height (mm)"
                    value={frontHeight}
                    onChange={(v) => setFrontHeight(v ?? 0)}
                    min={0}
                    style={{ width: 220 }}
                    />
                
                    <InputNumber
                    addonBefore="Back Height (mm)"
                    value={backHeight}
                    onChange={(v) => setBackHeight(v ?? 0)}
                    min={0}
                    style={{ width: 220 }}
                    />
                
                    <InputNumber
                    addonBefore="Impactor 질량 (g)"
                    value={impactorWeight}
                    disabled={true}
                    onChange={(v) => setImpactorWeight(v ?? 0)}
                    min={0}
                    style={{ width: 220 }}
                    />
         
                </div>
            )}

            <Divider />
            <div style={{ marginTop: 16, marginBottom: 16, textAlign: 'center', display: 'flex', flexDirection: 'column', gap: 16 }}>
                
                <ExportMeshModifierButton
                    kFile={uploadedKFile}
                    kFileName={kFileName || 'UNKNOWN.k'}
                    optionFileGenerator={() => generateDropWeightImpactTestbyPartsOptionFile(
                        kFileName || 'UNKNOWN.k',
                        partIDs, 
                        initialVelocityXList,
                        initialVelocityYList,
                        initialVelocityZList,
                        locationModes,
                        heightList,
                        tFinal,
                        dt,
                        impactorType === 'cylinder' ? densityCylinder : densitySphere,
                        impactorType === 'cylinder' ? youngModulusCylinder : youngModulusSphere,
                        impactorType === 'cylinder' ? poissonRatioCylinder : poissonRatioSphere,
                        impactorType,
                        meshSize,
                        impactorType === 'cylinder' ? youngModulusCylinderFront : youngModulusSphere,
                        impactorType === 'cylinder' ? densityCylinderFront : densitySphere,
                        impactorType === 'cylinder' ? poissonRatioCylinderFront : poissonRatioSphere,
                        youngModulusWall,
                        densityWall,
                        poissonRatioWall,
                        [frontDiameter/2.0, midDiameter/2.0, frontHeight, backHeight, backDiameter/2.0],
                        [impactorDiameter/2.0],
                        offsetDistance
                        
                    )}
                    optionFileName="drop_weight_impact.txt"
                />
            </div>
            
      </div>
    </BaseLayout>
  );
};

export default AllPointsDropWeightImpactGenerator;


function calculateCylinderWithFilletMass(
    d1: number,
    d2: number,
    d3: number,
    h1: number,
    h2: number,
    densityFront: number, // ton/mm³
    densityBack: number   // ton/mm³
  ): number {
    const r1 = d1 / 2;
    const r2 = d2 / 2;
    const r3 = d3 / 2;
  
    const fillet1Height = r2 - r1;
    const fillet2Height = r3 - r2;
  
    // Front: Cylinder + Fillet (cone)
    const volumeFrontCylinder = Math.PI * r1 * r1 * h1;
    const volumeFillet1 = (1 / 3) * Math.PI * fillet1Height * (r1 ** 2 + r1 * r2 + r2 ** 2);
  
    // Back: Cylinder + Fillet (cone)
    const volumeBackCylinder = Math.PI * r3 * r3 * h2;
    const volumeFillet2 = (1 / 3) * Math.PI * fillet2Height * (r2 ** 2 + r2 * r3 + r3 ** 2);
  
    const frontVolume = volumeFrontCylinder + volumeFillet1;
    const backVolume = volumeBackCylinder + volumeFillet2;
  
    const massTon = frontVolume * densityFront + backVolume * densityBack;
    return massTon * 1e6; // convert to g
  }
  
  

function calculateSphereMass(diameter: number, density: number): number {
    const radius = diameter / 2;
    const volume = (4 / 3) * Math.PI * Math.pow(radius, 3);
    const massGram = volume * density * 1e6;
    return massGram;
  }
  