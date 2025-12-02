import { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import React from 'react';

import { InputNumber, Upload, Button, Form, Space } from 'antd';
import { UploadOutlined } from '@ant-design/icons';
import 'antd/dist/reset.css';

interface WarpVisualizerProps {
  warpageInfo: {
    rawData: number[][];
    xLength: number;
    yLength: number;
    scaleFactor: number;
  } | null;
}

const WarpVisualizerComponent: React.FC<WarpVisualizerProps> = ({ warpageInfo }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const meshRef = useRef<BABYLON.Mesh | null>(null);
  const cameraRef = useRef<BABYLON.ArcRotateCamera | null>(null);
  const [scene, setScene] = useState<BABYLON.Scene | null>(null);

  const [xLength, setXLength] = useState(1);
  const [yLength, setYLength] = useState(1);
  const [scaleFactor, setScaleFactor] = useState(1);
  const [rawData, setRawData] = useState<number[][] | null>(null);

  // 초기화
  const aspectRatio = 16 / 9; // 또는 4 / 3으로 변경 가능

useEffect(() => {
  const canvas = canvasRef.current!;
  const engine = new BABYLON.Engine(canvas, true);
  const scene = new BABYLON.Scene(engine);
  scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);

  const camera = new BABYLON.ArcRotateCamera('camera', Math.PI / 2, Math.PI / 3, 10, BABYLON.Vector3.Zero(), scene);
  camera.attachControl(canvas, true);
  camera.wheelPrecision = 100;
  camera.panningSensibility = 1000;
  cameraRef.current = camera;

  new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene).intensity = 0.8;

  const resizeCanvas = () => {
    const container = canvas.parentElement!;
    const width = container.clientWidth;
    const height = width / aspectRatio;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    engine.resize();
  };  

  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();

  engine.runRenderLoop(() => scene.render());
  setScene(scene);

  return () => {
    engine.dispose();
    window.removeEventListener('resize', resizeCanvas);
  };
}, []);


const setCameraView = (view: 'top' | 'bottom') => {
  if (!cameraRef.current) return;
  const cam = cameraRef.current;
  const radius = cam.radius;

  cam.alpha = view === 'top' ? Math.PI / 2 : (3 * Math.PI) / 2; // Z+, Z-
  cam.beta = Math.PI / 2; // 수직 아래를 향함
  cam.radius = radius;
};


  // 시각화 함수
  const updateMesh = () => {
    if (!rawData || !scene) return;

    meshRef.current?.dispose(); // 기존 메시 제거

    const rows = rawData;
    const numRows = rows.length;
    const numCols = rows[0].length;
    const dx = xLength / (numCols - 1);
    const dy = yLength / (numRows - 1);

    const validZ: number[] = [];
    for (const row of rows) {
      for (const z of row) {
        if (z !== 9999) validZ.push(z);
      }
    }
    const minZ = Math.min(...validZ);
    const maxZ = Math.max(...validZ);

    const mesh = new BABYLON.Mesh('surface', scene);
    const vertexData = new BABYLON.VertexData();
    const positions: number[] = [];
    const indices: number[] = [];
    const colors: number[] = [];
    const validIndices: number[][] = [];

    for (let y = 0; y < numRows; y++) {
      const yPos = (numRows - 1 - y) * dy;
      for (let x = 0; x < numCols; x++) {
        const zRaw = rows[y][x];
        const z = zRaw === 9999 ? NaN : zRaw * scaleFactor;
        positions.push(x * dx, yPos, isNaN(z) ? 0 : z);

        if (isNaN(z)) {
          colors.push(1, 1, 1, 0); // 투명하게
        } else {
          const t = (z - minZ) / (maxZ - minZ);
          colors.push(t, 0, 1 - t, 1);
        }
      }
    }

    for (let y = 0; y < numRows - 1; y++) {
      for (let x = 0; x < numCols - 1; x++) {
        const i = y * numCols + x;
        const z1 = rows[y][x], z2 = rows[y][x + 1], z3 = rows[y + 1][x], z4 = rows[y + 1][x + 1];
        if ([z1, z2, z3].includes(9999)) continue;
        indices.push(i, i + 1, i + numCols);
        if ([z2, z4, z3].includes(9999)) continue;
        indices.push(i + 1, i + numCols + 1, i + numCols);
      }
    }

    vertexData.positions = positions;
    vertexData.indices = indices;
    vertexData.colors = colors;
    vertexData.applyToMesh(mesh, true);

    const material = new BABYLON.StandardMaterial('mat', scene);
    material.backFaceCulling = false;
    mesh.material = material;
    meshRef.current = mesh;

    // 카메라 자동 맞춤
    const bounding = mesh.getBoundingInfo().boundingBox;
    const center = bounding.centerWorld;
    const radius = bounding.extendSizeWorld.length();
    if (cameraRef.current) {
      cameraRef.current.setTarget(center);
      cameraRef.current.radius = radius * 2;
    }
  };

  // 파일 로드
  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    const text = await file.text();
    const rows = text.trim().split('\n').map(line =>
      line.trim().split(/\t|\s+/).map(val => {
        const num = parseFloat(val);
        return isNaN(num) ? 9999 : num;
      })
    );
    setRawData(rows);
  };

  // 값이 변경되면 시각화 자동 갱신
  useEffect(() => {
    updateMesh();
  }, [rawData, xLength, yLength, scaleFactor]);

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column' }}>
  <div style={{ padding: '1rem', background: '#fafafa' }}>
    <Form layout="inline">
      <Form.Item label="X Length">
        <InputNumber
          value={xLength}
          min={0}
          step={0.1}
          onChange={(val) => setXLength(val ?? 0)}
        />
      </Form.Item>
      <Form.Item label="Y Length">
        <InputNumber
          value={yLength}
          min={0}
          step={0.1}
          onChange={(val) => setYLength(val ?? 0)}
        />
      </Form.Item>
      <Form.Item label="Scale Factor">
        <InputNumber
          value={scaleFactor}
          min={0}
          step={0.1}
          onChange={(val) => setScaleFactor(val ?? 0)}
        />
      </Form.Item>
      <Form.Item>
        <Upload
          accept=".dat,.txt"
          beforeUpload={(file) => {
            const reader = new FileReader();
            reader.onload = (e) => {
              const fileEvent = {
                target: { files: [file] }
              } as unknown as React.ChangeEvent<HTMLInputElement>;
              handleFileChange(fileEvent);
            };
            reader.readAsText(file);
            return false; // prevent auto-upload
          }}
          showUploadList={false}
        >
          <Button icon={<UploadOutlined />}>DAT 파일 선택</Button>
        </Upload>        
      </Form.Item>
      <Form.Item>
      <Space>
        <Button onClick={() => setCameraView('top')}>🔼 Top View</Button>
        <Button onClick={() => setCameraView('bottom')}>🔽 Bottom View</Button>
      </Space>
    </Form.Item>

      
    </Form>
  </div>

  <div style={{ flex: 1, minHeight: '400px' }}>
    <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />
  </div>
</div>
  );
};

export default WarpVisualizerComponent;
