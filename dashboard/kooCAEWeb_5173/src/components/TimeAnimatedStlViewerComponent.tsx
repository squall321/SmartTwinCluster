import React, { useEffect, useRef } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';

interface TimeAnimatedStlViewerProps {
  stlUrl: string;
  positions: BABYLON.Vector3[][];
  frame: number;
}

const TimeAnimatedStlViewerComponent: React.FC<TimeAnimatedStlViewerProps> = ({ stlUrl, positions, frame }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const meshRef = useRef<BABYLON.Mesh | null>(null);
  const vertexBufferRef = useRef<BABYLON.VertexBuffer | null>(null);
  const engineRef = useRef<BABYLON.Engine | null>(null);
  const sceneRef = useRef<BABYLON.Scene | null>(null);
  const cameraRef = useRef<BABYLON.ArcRotateCamera | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current!;
    const engine = new BABYLON.Engine(canvas, true);
    engineRef.current = engine;

    const scene = new BABYLON.Scene(engine);
    sceneRef.current = scene;
    scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);

    const camera = new BABYLON.ArcRotateCamera('cam', -Math.PI / 2, Math.PI / 2.5, 100, BABYLON.Vector3.Zero(), scene);
    camera.attachControl(canvas, true);
    camera.minZ = 0.01;
    camera.maxZ = 10000;
    cameraRef.current = camera;

    new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene).intensity = 1.0;

    BABYLON.SceneLoader.ImportMeshAsync(
      null,
      '',
      stlUrl,
      scene,
      undefined,
      '.stl'
    ).then(result => {
      const mesh = result.meshes[0] as BABYLON.Mesh;
      meshRef.current = mesh;
      mesh.convertToFlatShadedMesh();
      mesh.refreshBoundingInfo();

      // 🔵 무광 재질 적용 (반사 제거)
      const mat = new BABYLON.StandardMaterial("mat", scene);
      mat.diffuseColor = new BABYLON.Color3(0.3, 0.6, 0.8); // 색상은 자유 조절 가능
      mat.specularColor = new BABYLON.Color3(0, 0, 0);       // 반사 제거
      mat.emissiveColor = new BABYLON.Color3(0.1, 0.1, 0.1); // 약간의 기본 밝기
      mesh.material = mat;

      // 🔍 화면에 딱 맞도록 카메라 설정
      const bbox = mesh.getBoundingInfo().boundingBox;
      const center = bbox.centerWorld.clone();
      const extents = bbox.extendSizeWorld;
      const maxExtent = Math.max(extents.x, extents.y, extents.z);
      const radius = maxExtent * 3;

      camera.setTarget(center);
      camera.radius = radius;

      // 포지션 버퍼 저장
      const vertexBuffer = mesh.getVertexBuffer(BABYLON.VertexBuffer.PositionKind);
      vertexBufferRef.current = vertexBuffer || null;
    });

    engine.runRenderLoop(() => {
      scene.render();
    });

    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);
    return () => {
      engine.dispose();
      window.removeEventListener('resize', handleResize);
    };
  }, [stlUrl]);

  useEffect(() => {
    if (!meshRef.current || !positions.length || frame >= positions.length) return;

    const mesh = meshRef.current;
    const positionArray = positions[frame];

    if (positionArray.length !== mesh.getTotalVertices()) {
      console.warn('❗ 노드 수가 STL과 불일치합니다.');
      return;
    }

    const flatPositions = new Float32Array(positionArray.length * 3);
    positionArray.forEach((v, i) => {
      flatPositions[i * 3 + 0] = v.x;
      flatPositions[i * 3 + 1] = v.y;
      flatPositions[i * 3 + 2] = v.z;
    });

    const vb = new BABYLON.VertexBuffer(
      mesh.getEngine(),
      flatPositions,
      BABYLON.VertexBuffer.PositionKind,
      false
    );
    mesh.setVerticesBuffer(vb);
    mesh.refreshBoundingInfo();
  }, [frame, positions]);

  return (
    <div style={{ width: '100%', height: '600px', position: 'relative' }}>
      <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />
    </div>
  );
};

export default TimeAnimatedStlViewerComponent;
