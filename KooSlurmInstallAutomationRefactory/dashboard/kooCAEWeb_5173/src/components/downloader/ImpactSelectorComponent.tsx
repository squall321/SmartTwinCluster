import React, { useEffect, useState } from 'react';
import { api } from '../../api/axiosClient';
import { Select, Spin, Typography, Button, Input, Space, List } from 'antd';
import { DeleteOutlined } from '@ant-design/icons';
import StlViewerComponent from '../StlViewerComponent';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';

const { Option } = Select;
const { Title } = Typography;

interface ImpactorFile {
  name: string;
  url: string;
}

interface ImpactPoint {
  dx: number;
  dy: number;
  dz: number;
}

interface ImpactorSelectorComponentProps {
  onChange?: (stlUrl: string, impactPoints: ImpactPoint[]) => void;
  targetBoundingBox?: { min: BABYLON.Vector3; max: BABYLON.Vector3 } | null;
}

function formatImpactorName(fileName: string): string {
  const cleanName = fileName.replace('.stl', '');
  const parts = cleanName.split('_');
  if (parts.length === 3) {
    const [piPart, weightPart, shapePart] = parts;
    const piText = piPart.replace('pi', 'π');
    const shapeText = shapePart.charAt(0).toUpperCase() + shapePart.slice(1);
    return `${shapeText} (${weightPart}, ${piText})`;
  }
  return fileName;
}

const ImpactorSelectorComponent: React.FC<ImpactorSelectorComponentProps> = ({ onChange, targetBoundingBox }) => {
  const [files, setFiles] = useState<ImpactorFile[]>([]);
  const [selectedUrl, setSelectedUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [impactPoints, setImpactPoints] = useState<ImpactPoint[]>([]);
  const [size, setSize] = useState<BABYLON.Vector3 | null>(null);
  const [centerOffset, setCenterOffset] = useState<BABYLON.Vector3 | null>(null);

  useEffect(() => {
    const fetchImpactors = async () => {
      try {
        const response = await api.post(`/api/impactors`);
        const data = response.data;
        if (data.success) {
          setFiles(data.files);
        }
      } catch (err) {
        console.error('서버 요청 실패:', err);
      } finally {
        setLoading(false);
      }
    };
    fetchImpactors();
  }, []);

  useEffect(() => {
    if (selectedUrl && onChange) {
      if (centerOffset) {
        const corrected = impactPoints.map(pt => ({
          dx: pt.dx + centerOffset.x,
          dy: pt.dy + centerOffset.y,
          dz: centerOffset.z,
        }));
        onChange(selectedUrl, corrected);
      } else {
        onChange(selectedUrl, impactPoints);
      }
    }
  }, [selectedUrl, impactPoints, centerOffset]);

  const handleSelect = async (value: string) => {
    setSelectedUrl(value);
    setImpactPoints([]);
    const engine = new BABYLON.NullEngine();
    const scene = new BABYLON.Scene(engine);

    try {
      const result = await BABYLON.SceneLoader.ImportMeshAsync(null, '', value, scene, undefined, '.stl');
      const mesh = result.meshes[0] as BABYLON.Mesh;
      mesh.forceSharedVertices();
      mesh.convertToFlatShadedMesh();
      mesh.computeWorldMatrix(true);
      mesh.refreshBoundingInfo();

      const boundingBox = mesh.getBoundingInfo().boundingBox;
      const min = boundingBox.minimumWorld;
      const max = boundingBox.maximumWorld;
      const center = max.add(min).scale(0.5);
      const sizeVec = max.subtract(min);

      setSize(sizeVec);
      setCenterOffset(center);
    } catch (e) {
      console.error('❌ STL 불러오기 실패:', e);
    }
  };

  const addCenterPoint = () => {
    if (!centerOffset) return;
    setImpactPoints((prev) => [...prev, { dx: -centerOffset.x, dy: -centerOffset.y, dz: -centerOffset.z }]);
  };

  const addCornerPoints = () => {
  if (!targetBoundingBox || !centerOffset) return;

  const { min, max } = targetBoundingBox;

  const corners = [
    new BABYLON.Vector3(min.x, 0, min.z),
    new BABYLON.Vector3(max.x, 0, min.z),
    new BABYLON.Vector3(max.x, 0, max.z),
    new BABYLON.Vector3(min.x, 0, max.z),
  ];

  const relative = corners.map((corner) => ({
    dx: corner.x - centerOffset.x,
    dy: corner.z - centerOffset.y,
    dz: 0,
  }));

  setImpactPoints(relative);
};


const addSidePoints = () => {
  if (!targetBoundingBox || !centerOffset) return;

  const { min, max } = targetBoundingBox;
  const midX = (min.x + max.x) / 2;
  const midZ = (min.z + max.z) / 2;

  const sidePoints = [
    new BABYLON.Vector3(min.x, 0, midZ), // 왼쪽
    new BABYLON.Vector3(max.x, 0, midZ), // 오른쪽
    new BABYLON.Vector3(midX, 0, min.z), // 앞
    new BABYLON.Vector3(midX, 0, max.z), // 뒤
  ];

  const relative = sidePoints.map((pt) => ({
    dx: pt.x - centerOffset.x,
    dy: pt.z - centerOffset.y,
    dz: 0,
  }));

  setImpactPoints((prev) => [...prev, ...relative]);
};

const addLongSidePoints = () => {
  if (!targetBoundingBox || !centerOffset) return;

  const { min, max } = targetBoundingBox;
  const lengthX = Math.abs(max.x - min.x);
  const lengthZ = Math.abs(max.z - min.z);
  const midX = (min.x + max.x) / 2;
  const midZ = (min.z + max.z) / 2;

  let longSidePoints: BABYLON.Vector3[] = [];

  if (lengthX >= lengthZ) {
    // 장축이 X: 좌/우 중점
    longSidePoints = [
      new BABYLON.Vector3(min.x, 0, midZ),
      new BABYLON.Vector3(max.x, 0, midZ),
    ];
  } else {
    // 장축이 Z: 앞/뒤 중점
    longSidePoints = [
      new BABYLON.Vector3(midX, 0, min.z),
      new BABYLON.Vector3(midX, 0, max.z),
    ];
  }

  const relative = longSidePoints.map((pt) => ({
    dx: pt.x - centerOffset.x,
    dy: pt.z - centerOffset.y,
    dz: 0,
  }));

  setImpactPoints((prev) => [...prev, ...relative]);
};



  const updateImpactPoint = (index: number, field: 'dx' | 'dy', value: string) => {
    const parsed = parseFloat(value);
    if (isNaN(parsed)) return;
    setImpactPoints((prev) =>
      prev.map((pt, i) => (i === index ? { ...pt, [field]: parsed } : pt))
    );
  };

  const deleteImpactPoint = (index: number) => {
    setImpactPoints((prev) => prev.filter((_, i) => i !== index));
  };

  const clearAllPoints = () => {
    setImpactPoints([]);
  };

  return (
    <div style={{ padding: '2rem' }}>
      <Title level={4}>📦 충격자 STL 선택</Title>
      {loading ? (
        <Spin size="large" />
      ) : (
        <Select
          showSearch
          placeholder="STL 파일 선택..."
          optionFilterProp="children"
          onChange={handleSelect}
          style={{ width: 300, marginBottom: '1.5rem' }}
        >
          {files.map((file) => (
            <Option key={file.url} value={file.url}>
              {formatImpactorName(file.name)}
            </Option>
          ))}
        </Select>
      )}

      {selectedUrl && (
        <div style={{ marginTop: '1.5rem' }}>
          <StlViewerComponent url={selectedUrl} />

          <div style={{ marginTop: 16 }}>
            <Button onClick={addCenterPoint} style={{ marginRight: 8 }}>🔵 중심점</Button>
            <Button onClick={addCornerPoints} style={{ marginRight: 8 }}>📐 꼭짓점</Button>
            <Button onClick={addSidePoints} style={{ marginRight: 8 }}>📏 사이드</Button>
            <Button onClick={addLongSidePoints} style={{ marginRight: 8 }}>📏 장축 사이드</Button>

            <Button onClick={clearAllPoints} danger>❌ 전체 삭제</Button>
          </div>

          <List
            size="small"
            header={<div>💥 충격 위치 리스트 (x-y 평면, 편집 가능)</div>}
            bordered
            dataSource={impactPoints}
            style={{ marginTop: 16 }}
            renderItem={(item, idx) => (
              <List.Item
                actions={[
                  <Button
                    type="text"
                    icon={<DeleteOutlined />}
                    danger
                    onClick={() => deleteImpactPoint(idx)}
                  />,
                ]}
              >
                <Space>
                  #{idx + 1}
                  dx:
                  <Input
                    value={item.dx}
                    style={{ width: 100 }}
                    onChange={(e) => updateImpactPoint(idx, 'dx', e.target.value)}
                  />
                  dy:
                  <Input
                    value={item.dy}
                    style={{ width: 100 }}
                    onChange={(e) => updateImpactPoint(idx, 'dy', e.target.value)}
                  />
                </Space>
              </List.Item>
            )}
          />
        </div>
      )}
    </div>
  );
};

export default ImpactorSelectorComponent;
