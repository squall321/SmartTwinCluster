import React, { useEffect, useRef } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';

interface ImpactorPointViewerProps {
  url: string;
  impactPoints: { dx: number; dy: number }[];
}

const ImpactorPointViewerComponent: React.FC<ImpactorPointViewerProps> = ({ url, impactPoints }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<BABYLON.Engine | null>(null);
  const sceneRef = useRef<BABYLON.Scene | null>(null);
  const centerRef = useRef<BABYLON.Vector3 | null>(null);
  const pointsRef = useRef<BABYLON.Mesh[]>([]);
  const maxExtentRef = useRef<number>(100);  // Z 위치 조정을 위해 저장

  useEffect(() => {
    const canvas = canvasRef.current!;
    const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true });
    const scene = new BABYLON.Scene(engine);
    sceneRef.current = scene;
    engineRef.current = engine;

    const camera = new BABYLON.ArcRotateCamera('camera', 0, 0.01, 100, BABYLON.Vector3.Zero(), scene);
    camera.mode = BABYLON.Camera.ORTHOGRAPHIC_CAMERA;
    camera.allowUpsideDown = false;
    camera.attachControl(canvas, true);
    camera.panningSensibility = 1000;

    new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 0, 1), scene).intensity = 0.9;

    BABYLON.SceneLoader.ImportMeshAsync(null, '', url, scene, undefined, '.stl')
      .then((result) => {
        if (result.meshes.length === 0) {
            console.error('❌ STL 로딩됨 → 하지만 mesh 없음!');
            return;
          }
          console.log('✅ 로딩된 mesh 개수:', result.meshes.length);
        const mesh = result.meshes[0] as BABYLON.Mesh;

        mesh.computeWorldMatrix(true);
        mesh.refreshBoundingInfo();

        const bbox = mesh.getBoundingInfo().boundingBox;
        const center = bbox.centerWorld;
        const size = bbox.maximumWorld.subtract(bbox.minimumWorld);
        const maxExtent = Math.max(size.x, size.y, size.z);

        centerRef.current = center;
        maxExtentRef.current = maxExtent;

        // ✅ 반투명하게 표시
        const mat = new BABYLON.StandardMaterial('mat', scene);
        mat.diffuseColor = new BABYLON.Color3(0.5, 0.5, 0.5);
        mat.alpha = 0.2;
        mat.backFaceCulling = false; // ✅ 중요
        mesh.material = mat;

        camera.setTarget(center);
        camera.orthoLeft = -maxExtent;
        camera.orthoRight = maxExtent;
        camera.orthoTop = maxExtent;
        camera.orthoBottom = -maxExtent;
        camera.radius = maxExtent * 2;

        camera.lowerRadiusLimit = maxExtent * 0.5;
        camera.upperRadiusLimit = maxExtent * 10;
        camera.setPosition(new BABYLON.Vector3(0, -maxExtent * 2, maxExtent * 2)); // 정면에서 바라보게
        camera.setTarget(center);

        scene.executeWhenReady(() => {
          engine.runRenderLoop(() => scene.render());
        });
      })
      .catch((err) => {
        console.error('❌ STL 로딩 실패:', err);
      });

    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);

    return () => {
      engine.dispose();
      window.removeEventListener('resize', handleResize);
    };
  }, [url]);

  useEffect(() => {
    const scene = sceneRef.current;
    const center = centerRef.current;
    const maxExtent = maxExtentRef.current;
    if (!scene || !center) return;

    // 기존 점 제거
    pointsRef.current.forEach((m) => m.dispose());
    pointsRef.current = [];

    // 새 점 생성
    const newPoints = impactPoints.map(({ dx, dy }, i) => {
      const sphere = BABYLON.MeshBuilder.CreateSphere(`impact_${i}`, { diameter: maxExtent * 0.03 }, scene);
      sphere.position = new BABYLON.Vector3(center.x + dx, center.y + dy, center.z + maxExtent * 0.1);
      const mat = new BABYLON.StandardMaterial(`mat_${i}`, scene);
      mat.diffuseColor = new BABYLON.Color3(1, 0, 0);
      sphere.material = mat;
      return sphere;
    });

    pointsRef.current = newPoints;
  }, [impactPoints]);

  return (
    <div style={{ position: 'relative', width: '100%', height: '600px' }}>
      <canvas ref={canvasRef} style={{ width: '100%', height: '100%', display: 'block' }} />
    </div>
  );
};

export default ImpactorPointViewerComponent;
