import React, { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders'; // ✅ 반드시 필요

interface GltfViewerProps {
  file: File;
}

const GltfViewerComponent: React.FC<GltfViewerProps> = ({ file }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!file || !canvasRef.current) return;

    setLoading(true);

    const blobUrl = URL.createObjectURL(file);
    const canvas = canvasRef.current;
    const engine = new BABYLON.Engine(canvas, true);
    const scene = new BABYLON.Scene(engine);

    const camera = new BABYLON.ArcRotateCamera('camera', -Math.PI / 2, Math.PI / 2.5, 5, BABYLON.Vector3.Zero(), scene);
    const desiredSize = 1.0; // 최소 확대 기준 크기


    camera.attachControl(canvas, true);

    const light = new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene);
    light.intensity = 1;

    BABYLON.SceneLoader.AppendAsync('', blobUrl, scene, undefined, '.glb')

      .then(() => {
        const meshes = scene.meshes.filter(m => m.name !== '__root__');

        if (meshes.length > 0) {
          const bounds = meshes.map(m => m.getBoundingInfo().boundingBox);
          const min = bounds.map(b => b.minimumWorld).reduce((a, b) => BABYLON.Vector3.Minimize(a, b));
          const max = bounds.map(b => b.maximumWorld).reduce((a, b) => BABYLON.Vector3.Maximize(a, b));
          const center = min.add(max).scale(0.5);
          const size = max.subtract(min);
          const maxExtent = Math.max(size.x, size.y, size.z);

          meshes.forEach(mesh => {
            mesh.position.subtractInPlace(center);
          });

          //camera.setTarget(BABYLON.Vector3.Zero());
          //camera.radius = maxExtent * 2;
          const scaleFactor = maxExtent < 1e-6 ? 1.0 : desiredSize / maxExtent;

          // 모델을 원점 기준으로 스케일링
          meshes.forEach(mesh => {
            mesh.position.subtractInPlace(center);
            mesh.scaling.scaleInPlace(scaleFactor);
          });

          // 카메라 위치 조절
          camera.setTarget(BABYLON.Vector3.Zero());
          camera.radius = desiredSize * 2;

          // ✅ 줌 제한은 모델 스케일에 따라 동적으로 설정
          camera.lowerRadiusLimit = desiredSize * 0.2;
          camera.upperRadiusLimit = desiredSize * 10;

        }

        scene.animationGroups.forEach(group => group.start(true));
        engine.runRenderLoop(() => scene.render());

        setLoading(false);
      })
      .catch(err => {
        console.error('❌ GLB 불러오기 실패:', err);
        setLoading(false);
      });

    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);

    return () => {
      scene.dispose();
      engine.dispose();
      window.removeEventListener('resize', handleResize);
      URL.revokeObjectURL(blobUrl);
    };
  }, [file]);

  return (
    <div style={{ width: '100%', height: '600px', position: 'relative' }}>
      {loading && (
        <div style={{
          position: 'absolute',
          top: '50%', left: '50%',
          transform: 'translate(-50%, -50%)',
          background: 'rgba(255,255,255,0.8)', padding: 20,
          borderRadius: 8, boxShadow: '0 0 10px rgba(0,0,0,0.2)'
        }}>
          Loading...
        </div>
      )}
      <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />
    </div>
  );
};

export default GltfViewerComponent;
